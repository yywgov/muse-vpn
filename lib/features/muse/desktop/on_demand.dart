// 穿云 1.6.0 C8 - 按需运行 (Windows): on a listed Wi‑Fi (home, office…) the connection is paused,
// after leaving it the connection comes back. Polls `netsh wlan show interfaces` every 15 s only
// while the switch is on and the list has a name, so nothing runs at start-up otherwise. Goes
// through the normal connect / disconnect (toggleConnection), never touches the connection state
// itself, and a manual 连接 / 断开 by the user always wins:
//   * the user disconnects while paused-or-not → nothing is resumed later;
//   * the user connects again on a listed Wi‑Fi → it is not paused again until the Wi‑Fi changes.
// The pause decision is the existing Wi‑Fi rule logic (museWifiDecide, "disconnect" rules).
// 1.6.0 C9: Android too (same state machine, Wi‑Fi name over the app's platform channel). Android
// gives the name only while 穿云 is in use, so there it also checks right when 穿云 comes back to
// the front; an unreadable name keeps the current state (never counts as leaving the Wi‑Fi).
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum MuseOnDemandStep { none, pause, resume }

/// The 按需运行 state machine (pure; one [tick] per netsh read).
class MuseOnDemand {
  MuseOnDemand({this.pausedByUs = false, this.pauseGeneration = -1});

  /// we disconnected and will reconnect after leaving the Wi‑Fi
  bool pausedByUs;

  /// the connection notifier's intent generation right after our own pause (a different value
  /// later = the user pressed 连接 / 断开 since)
  int pauseGeneration;

  /// the Wi‑Fi on which the user connected again by hand: not paused again while still on it
  String? overrideSsid;

  String? _lastSsid;

  MuseOnDemandStep tick({
    required List<String> ssids,
    required MuseSsidRead read,
    required bool running,
    required int generation,
  }) {
    if (!read.ok) return MuseOnDemandStep.none; // netsh failed: keep everything as is
    final ssid = read.ssid;
    if (ssid != _lastSsid) {
      _lastSsid = ssid;
      if (ssid != overrideSsid) overrideSsid = null;
    }
    if (pausedByUs && generation != pauseGeneration) {
      // the user pressed 连接 / 断开 since our pause: their choice stands
      pausedByUs = false;
      if (running && ssid != null && ssids.contains(ssid)) overrideSsid = ssid;
    }
    final listed = ssid != null && ssids.contains(ssid);
    if (pausedByUs) {
      if (!listed && !running) return MuseOnDemandStep.resume;
      if (!listed && running) pausedByUs = false; // came back some other way
      return MuseOnDemandStep.none;
    }
    if (!listed || ssid == overrideSsid) return MuseOnDemandStep.none;
    final rules = {for (final s in ssids) s: MuseWifiAction.disconnect};
    return museWifiDecide(rules, ssid, running: running, userStopped: false) == MuseWifiAction.disconnect
        ? MuseOnDemandStep.pause
        : MuseOnDemandStep.none;
  }

  /// after our own pause went through
  void paused(int generation) {
    pausedByUs = true;
    pauseGeneration = generation;
  }

  void resumed() {
    pausedByUs = false;
    pauseGeneration = -1;
  }
}

/// persisted so a restart while paused still resumes after leaving the Wi‑Fi
final _pausedPref = PreferencesNotifier.create<bool, bool>("muse_on_demand_paused", false);

/// netsh / Android read, overridable in tests
final museSsidReaderProvider = Provider<Future<MuseSsidRead> Function()>((_) => museReadSsid);

const museOnDemandInterval = Duration(seconds: 15);

final museOnDemandProvider = Provider<void>((ref) {
  if (!PlatformUtils.isWindows && !PlatformUtils.isAndroid && !ref.watch(museOnDemandForceProvider)) return;
  final on = ref.watch(MusePrefs.onDemand);
  final ssids = museOnDemandSsids(ref.watch(MusePrefs.wifiRules));
  if (!on || ssids.isEmpty) {
    if (ref.read(_pausedPref)) Future.microtask(() => ref.read(_pausedPref.notifier).update(false));
    return;
  }
  final notifier = ref.read(connectionNotifierProvider.notifier);
  final machine = MuseOnDemand();
  if (ref.read(_pausedPref)) machine.paused(notifier.intentGeneration);
  final read = ref.read(museSsidReaderProvider);
  var busy = false;
  Future<void> tick() async {
    if (busy) return;
    busy = true;
    try {
      final r = await read();
      final state = ref.read(connectionNotifierProvider).valueOrNull;
      if (state == null || state.isSwitching) return;
      final step = machine.tick(
        ssids: ssids,
        read: r,
        running: state is Connected,
        generation: notifier.intentGeneration,
      );
      switch (step) {
        case MuseOnDemandStep.none:
          return;
        case MuseOnDemandStep.pause:
          ChuanyunPlatform.recordDisconnect('按需运行：已连接 Wi‑Fi「${r.ssid}」，暂停连接');
          await notifier.toggleConnection();
          machine.paused(notifier.intentGeneration);
          await ref.read(_pausedPref.notifier).update(true);
        case MuseOnDemandStep.resume:
          ChuanyunPlatform.recordDisconnect('按需运行：已离开列入的 Wi‑Fi，恢复连接');
          machine.resumed();
          await ref.read(_pausedPref.notifier).update(false);
          await notifier.toggleConnection();
      }
    } catch (_) {
      // next tick
    } finally {
      busy = false;
    }
  }

  final first = Timer(const Duration(seconds: 3), tick);
  final timer = Timer.periodic(museOnDemandInterval, (_) => tick());
  AppLifecycleListener? lifecycle;
  if (PlatformUtils.isAndroid) {
    try {
      lifecycle = AppLifecycleListener(onResume: tick);
    } catch (_) {}
  }
  ref.onDispose(() {
    first.cancel();
    timer.cancel();
    lifecycle?.dispose();
  });
});

/// 1.6.0 C9: Android asks for 「位置信息」 before 按需运行 can read Wi‑Fi names (overridable in tests).
/// Answers granted / denied / blocked; null off Android (nothing to ask).
final museWifiPermissionRequestProvider = Provider<Future<String?> Function()>(
  (_) => ChuanyunPlatform.requestWifiPermission,
);

/// whether the 按需运行 page follows Android's rules (permission, foreground only)
final museOnDemandAndroidProvider = Provider<bool>((_) => PlatformUtils.isAndroid);

/// tests run the provider off Windows / Android
final museOnDemandForceProvider = Provider<bool>((_) => false);
