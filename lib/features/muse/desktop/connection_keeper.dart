// 穿云 Windows 1.2.1 - 连接守护 (connection keeper).
//
// While the user wants to be connected (Preferences.startedByUser — the user's intent, not the
// UI status) this checks every 10 s, and at once after a wake from sleep / a resume:
// - the core's own state (gRPC). Core running but the app shows 未连接 → the UI is corrected
//   (it was a lost status event), the status listener is re-armed.
// - core stopped or not answering although nobody stopped it → recovery.
// - every 30 s in 系统代理 mode: a request through the local proxy port. When that fails twice
//   while the same request without the proxy works, the core is broken → recovery.
// Recovery: retry after 2 s; if that does not bring the connection back, the user's own proxy
// settings are restored AT ONCE (the PC is never left offline because of 穿云), then retries
// follow after 5 / 15 / 30 / 60 s. After 5 failed retries it gives up, shows 未连接 and says so.
// Every step goes to data/disconnect.log (导出诊断).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/home/core_watchdog.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Waits between recovery attempts (the first right after the failure).
const museRecoveryBackoff = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 30), Duration(seconds: 60)];

/// What the keeper decides from one look at the core (pure, unit-tested).
enum KeeperAction { none, fixUi, recover }

KeeperAction museKeeperDecide({
  required bool wantConnected,
  required bool userJustStopped,
  required bool uiBusy,
  required bool uiConnected,
  required CoreStatus? core,
}) {
  if (core is CoreStarted || core is CoreHotReloading) {
    return uiConnected ? KeeperAction.none : KeeperAction.fixUi;
  }
  if (!wantConnected || userJustStopped || uiBusy) {
    // the app still shows 已连接 for a core that stopped: show the truth
    return core is CoreStopped && uiConnected && !uiBusy ? KeeperAction.fixUi : KeeperAction.none;
  }
  if (core is CoreStarting || core is CoreStopping) return KeeperAction.none;
  // stopped, or the core does not answer at all
  return KeeperAction.recover;
}

/// A wall-clock gap much longer than the tick: the PC slept / the process was suspended.
bool museLooksLikeWake(Duration sinceLastTick, Duration interval) =>
    sinceLastTick > interval + const Duration(seconds: 20);

final museConnectionKeeperProvider = Provider<MuseConnectionKeeper?>((ref) {
  if (!PlatformUtils.isWindows) return null;
  final keeper = MuseConnectionKeeper(ref);
  keeper.start();
  ref.onDispose(keeper.dispose);
  return keeper;
});

class MuseConnectionKeeper with InfraLogger {
  MuseConnectionKeeper(this.ref);
  final Ref ref;

  static const interval = Duration(seconds: 10);
  static const probeEvery = Duration(seconds: 30);

  Timer? _timer;
  final DateTime _createdAt = DateTime.now();

  /// The first 20 s after start-up belong to restoreConnectionOnStartup: no recovery then
  /// (the core may not even be set up yet).
  static const startupGrace = Duration(seconds: 20);
  DateTime _lastTick = DateTime.now();
  DateTime _lastProbe = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool _recovering = false;
  bool _proxyRestoredDuringRecovery = false;

  /// Recoveries since the connection was last fine.
  int failedAttempts = 0;

  void start() {
    _timer = Timer.periodic(interval, (_) => check(reason: 'tick'));
  }

  void dispose() => _timer?.cancel();

  /// Wake / window restore / smoke test: look now instead of at the next tick.
  void poke(String reason) => unawaited(check(reason: reason));

  void _log(String line) {
    loggy.info('keeper: $line');
    ChuanyunPlatform.recordDisconnect(line);
  }

  Future<void> check({required String reason}) async {
    final now = DateTime.now();
    final gap = now.difference(_lastTick);
    _lastTick = now;
    var wake = false;
    if (reason == 'tick' && museLooksLikeWake(gap, interval)) {
      wake = true;
      _log('检测到睡眠/挂起后恢复（间隔 ${gap.inSeconds} 秒），检查连接');
    }
    if (_busy || _recovering) return;
    _busy = true;
    try {
      final service = ref.read(hiddifyCoreServiceProvider);
      if (!service.isReady || now.difference(_createdAt) < startupGrace) return;
      final want = ref.read(Preferences.startedByUser);
      final ui = ref.read(connectionNotifierProvider).valueOrNull;
      final stoppedAt = ref.read(connectionNotifierProvider.notifier).lastIntentionalStopAt;
      final userJustStopped = stoppedAt != null && now.difference(stoppedAt) < const Duration(seconds: 15);
      await service.ensureStatusListener();
      final core = await service.queryCoreState();
      final action = museKeeperDecide(
        wantConnected: want,
        userJustStopped: userJustStopped,
        uiBusy: ui is Connecting || ui is Disconnecting,
        uiConnected: ui is Connected,
        core: core,
      );
      switch (action) {
        case KeeperAction.fixUi:
          _log('界面显示 ${museConnectionName(ui)}，内核实际为 ${museCoreName(core)}：修正界面状态');
          await service.resyncStatus();
        case KeeperAction.recover:
          _log(core == null ? '内核无响应（非用户操作），开始恢复' : '内核已停止（非用户操作），开始恢复');
          await _recover();
          return;
        case KeeperAction.none:
      }
      if (want && (core is CoreStarted) && !userJustStopped) {
        if (wake || reason != 'tick' || now.difference(_lastProbe) >= probeEvery) {
          _lastProbe = now;
          if (!await _proxyPathHealthy()) {
            _log('经本地代理端口的访问失败而直连正常：内核异常，开始恢复');
            await _recover();
            return;
          }
          // the guard restored the user's settings (the app hung / the PC slept with the port
          // silent): the core runs again, so switch 系统代理 back on by reconnecting
          if (await _systemProxyMissing()) {
            _log('系统代理已不指向穿云（守护进程恢复过或被修改），重新连接');
            await _recover();
            return;
          }
        }
        if (failedAttempts > 0) failedAttempts = 0;
      }
    } catch (e) {
      loggy.warning('keeper check failed', e);
    } finally {
      _busy = false;
    }
  }

  /// 系统代理 mode only: a plain HTTP request through 127.0.0.1:<mixed port> must work whenever
  /// the same request without the proxy works. Checked twice (3 s apart) before it counts.
  Future<bool> _proxyPathHealthy() async {
    final options = ref.read(ConfigOptions.singboxConfigOptions);
    if (!options.setSystemProxy) return true;
    final port = ref.read(ConfigOptions.mixedPort);
    for (var i = 0; i < 2; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(seconds: 3));
      if (await museHttpProbe(viaPort: port)) return true;
    }
    // proxy path fails: only the core's fault when the network itself works
    final direct = await museHttpProbe();
    if (!direct) loggy.info('keeper: proxy and direct both fail — network down, not the core');
    return !direct;
  }

  /// 系统代理 mode, core running: the system proxy no longer points at us (seen twice, 3 s apart,
  /// so a hot reload's close/re-open of the inbound does not count).
  Future<bool> _systemProxyMissing() async {
    final options = ref.read(ConfigOptions.singboxConfigOptions);
    if (!options.setSystemProxy) return false;
    for (var i = 0; i < 2; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(seconds: 3));
      final ours = await WindowsProxyGuard.pointsAtUsNow();
      if (ours != false) return false;
      if (await ref.read(hiddifyCoreServiceProvider).queryCoreState() is! CoreStarted) return false;
    }
    return true;
  }

  Future<void> _recover() async {
    if (_recovering) return;
    _recovering = true;
    _proxyRestoredDuringRecovery = false;
    ref.read(museWatchdogRecoveringProvider.notifier).state = true;
    final notifier = ref.read(connectionNotifierProvider.notifier);
    try {
      for (var i = 0; i < museRecoveryBackoff.length; i++) {
        await Future<void>.delayed(museRecoveryBackoff[i]);
        if (!ref.read(Preferences.startedByUser)) {
          _log('用户已断开，停止恢复');
          return;
        }
        final connected = await notifier.recoverConnection().timeout(
          const Duration(seconds: 40),
          onTimeout: () => false,
        );
        final ok = connected && await _confirmUp();
        if (ok) {
          failedAttempts = 0;
          _log('第 ${i + 1} 次恢复成功，已重新连接');
          unawaited(_retestNodes());
          return;
        }
        failedAttempts = i + 1;
        _log('第 ${i + 1} 次恢复失败');
        if (!_proxyRestoredDuringRecovery) {
          // never leave the PC offline while we keep trying
          _proxyRestoredDuringRecovery = true;
          final restored = await WindowsProxyGuard.restore('恢复失败');
          _log(restored ? '已恢复原系统代理设置，电脑可正常上网' : '系统代理未指向穿云，无需恢复');
        }
      }
      _log('多次恢复失败，已放弃自动重连（显示未连接）');
      await notifier.abortConnection();
      await WindowsProxyGuard.restore('放弃重连');
      await ref.read(Preferences.startedByUser.notifier).update(false);
      try {
        ref.read(inAppNotificationControllerProvider).showErrorToast('穿云已断开，已恢复原网络设置');
      } catch (_) {}
    } finally {
      _recovering = false;
      ref.read(museWatchdogRecoveringProvider.notifier).state = false;
    }
  }

  /// After a reconnect the node list could still show the previous core's results (a test cut
  /// short by the stop reads as 超时): test the current group again.
  Future<void> _retestNodes() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      final group = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
      if (group != null) await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group.tag);
    } catch (_) {
      // the core's own cycle tests the nodes anyway
    }
  }

  /// After a recovery connect: the core says started and, in 系统代理 mode, the port answers.
  Future<bool> _confirmUp() async {
    final service = ref.read(hiddifyCoreServiceProvider);
    for (var i = 0; i < 10; i++) {
      final s = await service.queryCoreState();
      if (s is CoreStarted) {
        await service.resyncStatus();
        final options = ref.read(ConfigOptions.singboxConfigOptions);
        if (!options.setSystemProxy) return true;
        return museSocksGreeting(ref.read(ConfigOptions.mixedPort));
      }
      if (s is CoreStopped) return false;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }
}

/// Stable names (release builds minify runtimeType).
String museConnectionName(ConnectionStatus? s) => switch (s) {
  Connected() => '已连接',
  Connecting() => '连接中',
  Disconnecting() => '断开中',
  Disconnected() => '未连接',
  null => '无',
};

String museCoreName(CoreStatus? s) => switch (s) {
  CoreStarted() => 'started',
  CoreStarting() => 'starting',
  CoreStopping() => 'stopping',
  CoreStopped() => 'stopped',
  CoreHotReloading() => 'hot-reloading',
  null => 'no-answer',
};

/// HEAD http://www.baidu.com/ (then www.qq.com) — through 127.0.0.1:[viaPort] as an HTTP proxy,
/// or directly. True when any answers with an HTTP status line within 8 s.
Future<bool> museHttpProbe({int? viaPort, List<String> hosts = const ['www.baidu.com', 'www.qq.com']}) async {
  for (final host in hosts) {
    Socket? socket;
    try {
      socket = viaPort != null
          ? await Socket.connect('127.0.0.1', viaPort, timeout: const Duration(seconds: 3))
          : await Socket.connect(host, 80, timeout: const Duration(seconds: 5));
      final target = viaPort != null ? 'http://$host/' : '/';
      socket.write('HEAD $target HTTP/1.1\r\nHost: $host\r\nUser-Agent: chuanyun-probe\r\nConnection: close\r\n\r\n');
      await socket.flush();
      final first = await socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .first
          .timeout(const Duration(seconds: 8));
      if (first.startsWith('HTTP/1.')) return true;
    } catch (_) {
      // next host
    } finally {
      socket?.destroy();
    }
  }
  return false;
}

/// SOCKS5 greeting to the mixed port: 05 01 00 → 05 00. Answered by the core without network.
Future<bool> museSocksGreeting(int port) async {
  Socket? socket;
  try {
    socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(seconds: 2));
    socket.add([5, 1, 0]);
    await socket.flush();
    final resp = await socket.first.timeout(const Duration(seconds: 2));
    return resp.isNotEmpty && resp[0] == 5;
  } catch (_) {
    return false;
  } finally {
    socket?.destroy();
  }
}
