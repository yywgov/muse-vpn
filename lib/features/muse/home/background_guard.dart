// 穿云 1.4.1 - Android: notices that the system killed 穿云 in the background (the VPN service
// recorded a start but never a stop, and it wasn't a reboot or an app update) and records it
// (counted, and a line in the disconnect history that 诊断 exports).
// 1.10.0: no dialog any more (the 后台保活 page and its per-brand steps were removed); the only
// prompt left is the one-time 「允许后台运行」 hint on the first connection (keep_alive_guide.dart).
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/android_keepalive.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Checks once, a few seconds after start-up; true when 穿云 was killed since the last start.
Future<bool> museCheckBackgroundKill(WidgetRef ref) async {
  if (!PlatformUtils.isAndroid) return false;
  await Future<void>.delayed(const Duration(seconds: 4));
  try {
    final since = await ChuanyunPlatform.connectedSince() ?? 0;
    final info = await ChuanyunPlatform.deviceInfo();
    final version = ref.read(museAppVersionProvider) ?? '';
    final last = ref.read(MusePrefs.lastRunVersion);
    final updated = last.isNotEmpty && version.isNotEmpty && last != version;
    if (version.isNotEmpty && last != version) await ref.read(MusePrefs.lastRunVersion.notifier).update(version);
    final killed = museWasKilledInBackground(
      connectedSince: since,
      running: ref.read(serviceRunningProvider),
      bootTime: info?.bootTime ?? 0,
      appUpdated: updated,
      lastReported: ref.read(MusePrefs.killReported),
    );
    if (since > 0 && !ref.read(serviceRunningProvider)) await ref.read(MusePrefs.killReported.notifier).update(since);
    if (!killed) return false;
    await ref.read(MusePrefs.killCount.notifier).update(ref.read(MusePrefs.killCount) + 1);
    unawaited(ChuanyunPlatform.recordDisconnect('穿云在后台被系统关闭（上次连接开始于 ${DateTime.fromMillisecondsSinceEpoch(since)}）'));
    return true;
  } catch (_) {
    return false;
  }
}
