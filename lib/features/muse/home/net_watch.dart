// 穿云 1.4.1 - things that watch the connection over time:
//   * 睡眠唤醒后复查 (both platforms): after the device slept, check that the connection still
//     works; on Android reconnect once when it doesn't (Windows: the connection keeper does that
//     itself and is poked here). Part of 智能保持连接, so it follows that switch.
//   * 定时连接 / 断开 (设置 › 网络; off by default).
//   * 连接质量提醒 (设置 › 网络; off by default): the current node is re-tested every minute while
//     connected and the app is in front; one notification per bad spell.
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/notify.dart';
import 'package:hiddify/features/muse/desktop/connection_keeper.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/keep_alive.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const museQualityAlertId = 2103;

final museWakeCheckProvider = Provider<void>((ref) {
  final detector = MuseWakeDetector();
  var busy = false;
  final timer = Timer.periodic(detector.interval, (_) async {
    final gap = detector.tick(DateTime.now());
    if (gap == null || busy) return;
    busy = true;
    try {
      final want = ref.read(Preferences.startedByUser);
      final keep = ref.read(Preferences.museKeepAlive);
      final running = ref.read(serviceRunningProvider);
      if (museWakeDecide(wantConnected: want, keepAlive: keep, running: running) == MuseWakeAction.none) return;
      if (PlatformUtils.isWindows) {
        // the keeper owns reconnecting on Windows; refresh what 首页 shows as well
        ref.read(museConnectionKeeperProvider)?.poke('wake');
      }
      // let Wi‑Fi / the route settle first
      await Future<void>.delayed(const Duration(seconds: 5));
      final generation = ref.read(connectionNotifierProvider.notifier).intentGeneration;
      await ref.read(museReachProvider.notifier).check();
      final ok = ref.read(museReachProvider) == MuseReach.ok;
      if (PlatformUtils.isWindows) return;
      final action = museWakeDecide(
        wantConnected: ref.read(Preferences.startedByUser),
        keepAlive: ref.read(Preferences.museKeepAlive),
        running: ref.read(serviceRunningProvider),
        reachOk: ok,
        directOk: await museHttpProbe(),
      );
      if (action != MuseWakeAction.reconnect) return;
      // a manual disconnect / connect since then wins
      if (ref.read(connectionNotifierProvider.notifier).intentGeneration != generation) return;
      ChuanyunPlatform.recordDisconnect(museKeepAliveLogLine(MuseKeepAliveStep.reconnect, '睡眠 ${gap.inMinutes} 分钟后无法访问外网，重新连接'));
      await ref.read(connectionNotifierProvider.notifier).restartAfterWatchdog();
    } catch (_) {
      // next wake
    } finally {
      busy = false;
    }
  });
  ref.onDispose(timer.cancel);
});

final museScheduleProvider = Provider<void>((ref) {
  final schedule = MuseSchedule.parse(ref.watch(MusePrefs.schedule));
  if (schedule.isOff) return;
  final timer = Timer.periodic(const Duration(seconds: 20), (_) async {
    try {
      final now = DateTime.now();
      final running = ref.read(serviceRunningProvider);
      final action = museScheduleDue(schedule, now, lastFired: ref.read(MusePrefs.scheduleLastFired), running: running);
      if (action == MuseWifiAction.none) return;
      await ref.read(MusePrefs.scheduleLastFired.notifier).update(museScheduleSlot(schedule, now, action));
      final state = ref.read(connectionNotifierProvider).valueOrNull;
      if (action == MuseWifiAction.connect && state is Disconnected) {
        ChuanyunPlatform.recordDisconnect('定时连接');
        await ref.read(connectionNotifierProvider.notifier).toggleConnection();
      } else if (action == MuseWifiAction.disconnect && state is Connected) {
        ChuanyunPlatform.recordDisconnect('定时断开');
        await ref.read(connectionNotifierProvider.notifier).toggleConnection();
      }
    } catch (_) {}
  });
  ref.onDispose(timer.cancel);
});

final museQualityAlertProvider = Provider<void>((ref) {
  if (!ref.watch(MusePrefs.qualityAlert) || !ref.watch(serviceRunningProvider)) return;
  final watch = MuseQualityWatch();
  final timer = Timer.periodic(const Duration(minutes: 1), (_) async {
    if (PlatformUtils.isAndroid && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    try {
      final group = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
      final sel = group?.items.where((e) => e.tag == group.selected).firstOrNull;
      if (group == null || sel == null) return;
      await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(sel.isGroup ? group.tag : sel.tag);
      await Future<void>.delayed(const Duration(seconds: 8));
      final now = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
      final cur = now?.items.where((e) => e.tag == now.selected).firstOrNull;
      if (cur == null) return;
      if (watch.add(cur.urlTestDelay)) {
        final name = cur.tagDisplay.isNotEmpty ? cur.tagDisplay : cur.tag;
        await museNotify(id: museQualityAlertId, title: '连接质量变差', text: '「$name」延迟高或经常超时，可以换个节点');
      }
    } catch (_) {}
  });
  ref.onDispose(timer.cancel);
});
