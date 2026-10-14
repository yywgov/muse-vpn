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
