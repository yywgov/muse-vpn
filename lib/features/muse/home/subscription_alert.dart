// 穿云 1.1 - one system notification when the active subscription is running out.
// 1.2.8: at 80 % of the traffic used, again when it is used up, and 3 days or less before it
// expires; each threshold once per billing period (a renewal gives a new expiry date, so the next
// period alerts again). Android and Windows.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/notify.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Notification id shared with the Android side (ChuanyunAlerts.ID_SUBSCRIPTION).
const museSubscriptionAlertId = 2102;

typedef MuseSubscriptionAlert = ({String key, String text});

/// The alerts that apply to a subscription right now (pure, for tests).
/// [upload]/[download]/[total] in bytes; a total of 0 or above 10 TB means unlimited.
List<MuseSubscriptionAlert> museSubscriptionAlerts({
  required String profileId,
  required int upload,
  required int download,
  required int total,
  required DateTime expire,
  required DateTime now,
}) {
  final alerts = <MuseSubscriptionAlert>[];
  final period = expire.millisecondsSinceEpoch;
  const tenTB = 10 * 1024 * 1024 * 1024 * 1024;
  if (total > 0 && total <= tenTB) {
    final used = upload + download;
    final remaining = total - used;
    if (remaining <= 0) {
      alerts.add((key: '$profileId:traffic100:$period', text: '流量已用完'));
    } else if (used >= total * 0.80) {
      alerts.add((key: '$profileId:traffic80:$period', text: '流量已用 ${(used * 100 / total).floor()}%，剩余 ${_size(remaining)}'));
    }
  }
  final validExpiry = expire.year > 1971 && expire.year < 2100;
  if (validExpiry && expire.isAfter(now) && expire.difference(now) <= const Duration(days: 3)) {
    alerts.add((key: '$profileId:expire:$period', text: '订阅将于 ${expire.month}月${expire.day}日到期'));
  }
  return alerts;
}

String _size(int bytes) {
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}

final museSubscriptionAlertProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<ProfileEntity?>>(activeProfileProvider, (_, next) async {
    final profile = next.valueOrNull;
    if (profile is! RemoteProfileEntity) return;
    final info = profile.subInfo;
    if (info == null) return;
    final alerts = museSubscriptionAlerts(
      profileId: profile.id,
      upload: info.upload,
      download: info.download,
      total: info.total,
      expire: info.expire,
      now: DateTime.now(),
    );
    if (alerts.isEmpty) return;
    final sent = ref.read(Preferences.subscriptionAlertsSent).split('\n').where((e) => e.isNotEmpty).toList();
    final fresh = alerts.where((a) => !sent.contains(a.key)).toList();
    if (fresh.isEmpty) return;
    // keep the list short: only the latest 20 keys
    final updated = [...sent, ...fresh.map((a) => a.key)];
    await ref
        .read(Preferences.subscriptionAlertsSent.notifier)
        .update(updated.skip(updated.length > 20 ? updated.length - 20 : 0).join('\n'));
    await museNotify(
      id: museSubscriptionAlertId,
      title: '「${profile.name}」订阅提醒',
      text: fresh.map((a) => a.text).join('；'),
    );
  }, fireImmediately: true);
});
