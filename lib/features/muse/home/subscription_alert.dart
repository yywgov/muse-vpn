// 穿云 1.1 - one system notification when the active subscription is running out: less than 10 %
// of its traffic left, or 3 days or less before it expires. Each alert is sent once per billing
// period (a renewal gives a new expiry date, so the next period alerts again).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
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
    final remaining = total - upload - download;
    if (remaining < total * 0.10) {
      final left = remaining <= 0 ? '流量已用完' : '剩余流量不足 10%（${_size(remaining)}）';
      alerts.add((key: '$profileId:traffic:$period', text: left));
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
    await ChuanyunPlatform.showAlert(
      id: museSubscriptionAlertId,
      title: '「${profile.name}」需要续费',
      text: fresh.map((a) => a.text).join('；'),
    );
  }, fireImmediately: true);
});
