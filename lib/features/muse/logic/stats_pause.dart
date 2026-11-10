// 穿云 1.20.1 后台省电：安卓应用退到后台（paused / hidden）时关掉内核每秒一次的统计流（网速、流量），回到前台
// 再打开。中间的流量不丢：今日流量按内核的会话总量差累计，回到前台的第一条读数就把后台期间的流量补上；
// 后台期间连接断开时，在断开那一刻向内核读一次总量补上最后一段（[museFinalStatsDelta]）。
// Windows / 其他平台不变（托盘要显示网速）。不加任何计时器或后台唤醒。
// Part of 穿云 (GPLv3).

import 'package:flutter/widgets.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the per-second stats stream stays closed: [pauseEnabled] (Android) and the app not on screen.
/// `inactive` (notification shade, a dialog on top, the app switcher opening) keeps it open.
bool museStatsPausedFor({required bool pauseEnabled, required AppLifecycleState? state}) =>
    pauseEnabled &&
    (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached);

/// Android only (overridable in tests).
final museStatsPauseEnabledProvider = Provider<bool>((ref) => PlatformUtils.isAndroid);

/// The app's lifecycle state, kept by a listener (null before the first change is known).
class MuseAppLifecycle extends Notifier<AppLifecycleState?> {
  @override
  AppLifecycleState? build() {
    final listener = AppLifecycleListener(onStateChange: (s) => state = s);
    ref.onDispose(listener.dispose);
    return WidgetsBinding.instance.lifecycleState;
  }
}

final museAppLifecycleProvider = NotifierProvider<MuseAppLifecycle, AppLifecycleState?>(MuseAppLifecycle.new);

/// true while the stats stream is closed (Android, app in the background).
final museStatsPausedProvider = Provider<bool>((ref) {
  if (!ref.watch(museStatsPauseEnabledProvider)) return false;
  return museStatsPausedFor(pauseEnabled: true, state: ref.watch(museAppLifecycleProvider));
});

/// One reading of the core's totals, or null when it does not answer (overridable in tests).
final museStatsReadOnceProvider = Provider<Future<SystemInfo?> Function()>((ref) {
  final core = ref.watch(hiddifyCoreServiceProvider);
  return () => core.readStats();
});

/// 1.20.1: the traffic since the last counted reading, from one final reading of the totals ([up],
/// [down]) taken as the connection ends. [base] is a copy of the counter made before the reading was
/// asked for (the live counter may be reset by the disconnect meanwhile).
(int, int) museFinalStatsDelta(MuseTrafficCounter base, int up, int down) => base.delta(up, down);
