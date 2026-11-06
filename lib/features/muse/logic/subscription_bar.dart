// 穿云 1.2 - subscription traffic / expiry bar on 配置 tiles (pure logic, unit-tested).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/features/profile/model/profile_entity.dart';

/// What the bar shows: the remaining share (traffic when the plan has a cap, otherwise the time
/// left out of 30 days) and whether it should turn red (<10 % traffic left, or 3 days or less to
/// expiry). null = the subscription reports neither, no bar.
({double remaining, bool warn})? museSubscriptionBar(SubscriptionInfo info, {DateTime? now}) {
  final at = now ?? DateTime.now();
  const unlimitedBytes = 10 * 1024 * 1024 * 1024 * 1024; // the UI's 10 TB "unlimited" line
  final hasCap = info.total > 0 && info.total <= unlimitedBytes;
  final year = info.expire.year;
  final hasExpiry = year > 1971 && year < 2100;
  if (!hasCap && !hasExpiry) return null;
  final left = info.expire.difference(at);
  final expiringSoon = hasExpiry && left <= const Duration(days: 3);
  final trafficShare = hasCap ? ((info.total - info.upload - info.download) / info.total).clamp(0.0, 1.0) : null;
  final lowTraffic = trafficShare != null && trafficShare < 0.1;
  final remaining = trafficShare ?? (left.inHours / (30 * 24)).clamp(0.0, 1.0);
  return (remaining: remaining.toDouble(), warn: expiringSoon || lowTraffic);
}

/// 1.11.0: one bar on a 订阅 card — 流量 (remaining share of the cap) or 时间 (days left, out of 30).
typedef MuseSubBar = ({String kind, String label, String trailing, double remaining, bool warn});

/// 1.11.0: the 剩余流量 and 到期 bars of a subscription (each only when it reports that value).
/// warn = ≤10 % traffic left / 3 days or less to expiry (the same thresholds as the reminder).
List<MuseSubBar> museSubscriptionBars(SubscriptionInfo info, {DateTime? now}) {
  final at = now ?? DateTime.now();
  const unlimitedBytes = 10 * 1024 * 1024 * 1024 * 1024;
  final bars = <MuseSubBar>[];
  if (info.total > 0 && info.total <= unlimitedBytes) {
    final left = info.total - info.upload - info.download;
    final share = (left / info.total).clamp(0.0, 1.0).toDouble();
    bars.add((
      kind: 'traffic',
      label: '流量',
      trailing: left <= 0 ? '已用完' : '剩 ${(share * 100).ceil()}%',
      remaining: share,
      warn: share <= 0.1,
    ));
  }
  final year = info.expire.year;
  if (year > 1971 && year < 2100) {
    final left = info.expire.difference(at);
    final days = left.isNegative ? 0 : (left.inHours / 24).ceil();
    bars.add((
      kind: 'expiry',
      label: '到期',
      trailing: left.isNegative ? '已到期' : (days <= 1 ? '${info.expire.month}月${info.expire.day}日到期' : '剩 $days 天'),
      remaining: (left.inHours / (30 * 24)).clamp(0.0, 1.0).toDouble(),
      warn: left <= const Duration(days: 3),
    ));
  }
  return bars;
}
