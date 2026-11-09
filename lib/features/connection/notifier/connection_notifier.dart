import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/model/startup_connection.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/crash_recorder.dart';
import 'package:hiddify/features/muse/data/muse_health.dart';
import 'package:hiddify/features/muse/home/core_profile.dart';
import 'package:hiddify/features/muse/logic/connect_flow.dart';
import 'package:hiddify/features/muse/logic/startup_restore.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'connection_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  @override
  Stream<ConnectionStatus> build() async* {
    if (Platform.isIOS) {
      await _connectionRepo.setup().mapLeft((l) {
        loggy.error("error setting up connection repository", l);
      }).run();
    }

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      final shouldReconnect = next == null || previous.id != next.id;
      if (shouldReconnect) {
        await reconnect(next);
      }
    });
    ref.watch(coreRestartSignalProvider);

    yield* _connectionRepo.watchConnectionStatus().doOnData((event) {
      // 1.5.3: a stopped core runs no subscription (a restart by the tile / watchdog is then trusted)
      if (event is Disconnected) Future.microtask(() => _read(museCoreProfileIdProvider.notifier).state = null);
      // 穿云 Windows 1.2.1: a failure no longer drops the user's intent on Windows; the connection
      // keeper retries with backoff and gives up (startedByUser = false) itself.
      if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop && !PlatformUtils.isWindows) {
        Future.microtask(() => _read(Preferences.startedByUser.notifier).update(false));
      }
      // One call for every status buried failures at info, next to the ordinary
      // comings and goings. A failure carries the core's own panic text, which
      // is the last thing that should need hunting for.
      final status = "connection status: ${event.format()}";
      if (event case Disconnected(connectionFailure: final failure?)) {
        loggy.error(status);
        // 穿云: also into the disconnect log kept by the VPN service (导出诊断)
        ChuanyunPlatform.recordDisconnect("界面收到断开及错误: $failure");
        // 1.5.0: keep the core's last log lines for 诊断 before newer lines push them out
        MuseCrashRecorder.recordCoreTail('$failure');
        // 1.13.0: local crash log / 「上次异常」, two in a row → 安全模式
        Future.microtask(() async {
          await MuseHealth.startFailed('$failure');
          await _read(museHealthProvider.notifier).refresh();
        });
      } else {
        loggy.info(status);
        // 1.13.0: 被其他 VPN 断开 is written by the service; 首页 reads it on the next status
        if (event is Disconnected) Future.microtask(() => _read(museHealthProvider.notifier).refresh());
        if (event is Connected) {
          Future.microtask(() async {
            await MuseHealth.startOk();
            await _read(museHealthProvider.notifier).refresh();
          });
        }
      }
    });
  }


  // 1.17.0: reads after an await / from status callbacks go through the container. Every core
  // start bumps coreRestartSignalProvider (watched in build), which marks this notifier "outdated"
  // until its next rebuild; a ref.read in that window trips riverpod's debug assertion
  // "Cannot use ref functions after the dependency of a provider changed but before the provider
  // rebuilt" (首页「上次异常」 in debug / e2e builds since 1.13.0). Release builds drop the
  // assertion, so behaviour is the same; this only removes the debug-only error.
  T _read<T>(ProviderListenable<T> provider) => ref.container.read(provider);

  ConnectionRepository get _connectionRepo => _read(connectionRepositoryProvider);

  Future<void> mayConnect() async {
    if (state case AsyncData(:final value)) {
      if (value case Disconnected()) return _connect();
    }
  }

  /// Restores the tunnel on desktop start when the user had it running before quitting,
  /// so a session started manually survives a reboot or an autostart login.
  Future<void> restoreConnectionOnStartup() async {
    final startedByUser = _read(Preferences.startedByUser);
    final activeProfile = await _read(activeProfileProvider.future);
    final shouldRestore = shouldRestoreConnectionOnStartup(
      isDesktop: PlatformUtils.isDesktop,
      startedByUser: startedByUser,
      hasActiveProfile: activeProfile != null,
    );
    if (!shouldRestore) {
      loggy.debug("no previous connection to restore");
      return;
    }
    loggy.info("restoring previous connection on startup");
    intentGeneration++;
    await _read(Preferences.startedByUser.notifier).update(true);
    // 1.19.3: one transient gRPC / connection error no longer drops the intent (startup_restore.dart)
    await _connect(restoring: true);
  }

  Future<void> toggleConnection() async {
    if (state case AsyncError()) {
      await _connect();
    } else if (state case AsyncData(:final value)) {
      switch (value) {
        case Disconnected() when _preparing:
          // 穿云 1.5.0: tapped again while the config is still being prepared: stop before the
          // core is asked to start
          loggy.info("connect tapped while preparing: cancelling");
          await _cancelConnect();
        case Disconnected():
          intentGeneration++;
          await _read(Preferences.startedByUser.notifier).update(true);
          await _connect();
        case Connected():
          // default:
          intentGeneration++;
          await _read(Preferences.startedByUser.notifier).update(false);
          await _disconnect();
        case Connecting():
          // 穿云 1.2.2: a tap while the connection keeper is reconnecting cancels the recovery.
          // 1.5.0: a tap while connecting cancels any connect (state machine in
          // logic/connect_flow.dart); a connect that finishes after that is undone.
          loggy.info(_recoveryInFlight != null ? "connect tapped during recovery: stopping" : "connect cancelled");
          await _cancelConnect();
        case Disconnecting():
          // 1.5.0: 断开中 ignores taps (the button is disabled meanwhile)
          loggy.debug("disconnecting, tap ignored");
      }
    }
  }

  Future<void> _cancelConnect() async {
    intentGeneration++;
    await _read(Preferences.startedByUser.notifier).update(false);
    _setPreparing(false);
    await _disconnect();
  }

  /// 1.5.0: true while the app builds and checks the config, before the core is asked to start
  /// (the status is still 未连接 then). Shown as 「准备配置」.
  bool _preparing = false;

  bool get preparing => _preparing;

  void _setPreparing(bool v) {
    if (_preparing == v) return;
    _preparing = v;
    try {
      _read(museConnectPreparingProvider.notifier).state = v;
    } catch (_) {}
  }

  Future<void> reconnect(ProfileEntity? profile) async {
    if (state case AsyncData(:final value) when value == const Connected()) {
      if (profile == null) {
        loggy.info("no active profile, disconnecting");
        return _disconnect();
      }
      loggy.info("active profile changed, reconnecting");
      intentGeneration++;
      await _read(Preferences.startedByUser.notifier).update(true);
      await _connectionRepo.reconnect(profile, _read(Preferences.disableMemoryLimit)).map((done) {
        // 1.5.3: the node list follows the new subscription (fresh group stream from the reloaded core)
        _read(museCoreProfileIdProvider.notifier).state = profile.id;
        ref.container.invalidate(proxiesOverviewNotifierProvider);
        return done;
      }).mapLeft((err) async {
        loggy.warning("error reconnecting", err);
        state = AsyncError(err, StackTrace.current);
        await _read(dialogNotifierProvider.notifier)
            .showCustomAlertFromErr(museFriendlyPresent(err.present(_read(translationsProvider).requireValue)));
      }).run();
    }
  }

  /// 穿云 1.2.1: when the app itself last stopped the core on purpose (button, tray, quit, a
  /// profile removed, a run-mode switch). A stop shortly after that is not unexpected.
  DateTime? lastIntentionalStopAt;

  /// 穿云 1.2.2: bumped on every connect / disconnect the user asks for (button, tray, start-up
  /// restore). A recovery started under an older value no longer speaks for the user: it stops,
  /// and a connect it already made is undone when the user has asked to be disconnected since.
  int intentGeneration = 0;

  Future<bool>? _recoveryInFlight;

  /// Whether a keeper recovery is running right now (its connect may outlive the keeper's wait).
  bool get recoveryInFlight => _recoveryInFlight != null;

  /// 穿云 Windows 1.2.1: the connection keeper's recovery: stop whatever is left of the core and
  /// connect again with the active profile. True when the core reports started afterwards.
  ///
  /// 1.2.2: only one runs at a time. A caller that gave up waiting (timeout) and calls again
  /// gets the attempt that is still running instead of a second disconnect/connect on top of it.
  /// [generation] is [intentGeneration] when the recovery began.
  Future<bool> recoverConnection({required int generation}) {
    final running = _recoveryInFlight;
    if (running != null) return running;
    late final Future<bool> attempt;
    attempt = _recoverOnce(generation).whenComplete(() {
      if (identical(_recoveryInFlight, attempt)) _recoveryInFlight = null;
    });
    _recoveryInFlight = attempt;
    return attempt;
  }

  bool _userTookOver(int generation) => generation != intentGeneration || !_read(Preferences.startedByUser);

  Future<bool> _recoverOnce(int generation) async {
    final profile = await _read(activeProfileProvider.future);
    if (profile == null || _userTookOver(generation)) return false;
    await _connectionRepo.disconnect().run();
    if (_userTookOver(generation)) return false;
    final res = await _connectionRepo.connect(profile, _read(Preferences.disableMemoryLimit)).run();
    final ok = res.match((err) {
      loggy.warning("recovery connect failed", err);
      return false;
    }, (_) => true);
    if (_userTookOver(generation)) {
      // the user tapped 断开 while this connect was running: honour that, not the recovery
      if (!_read(Preferences.startedByUser)) {
        loggy.info("recovery finished after the user disconnected: stopping again");
        lastIntentionalStopAt = DateTime.now();
        await _connectionRepo.disconnect().run();
      }
      return false;
    }
    return ok;
  }

  /// 穿云 1.2.1: 系统代理 ↔ TUN needs a real restart. It used to call toggleConnection twice; the
  /// second call landed while the status was still 断开中 and was ignored ("debounce"), so
  /// switching the run mode left 穿云 disconnected.
  Future<void> restartForModeChange() async {
    if (state case AsyncData(value: Connected())) {
      lastIntentionalStopAt = DateTime.now();
      await _connectionRepo.disconnect().run();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        if (state case AsyncData(value: Disconnected())) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await _connect();
    }
  }

  /// 穿云 1.2 watchdog: the core stopped answering while connected. Restart it in place
  /// (reconnect); when that fails too, stop and start again.
  Future<void> restartAfterWatchdog() async {
    final profile = await _read(activeProfileProvider.future);
    if (profile == null) return;
    loggy.warning("core watchdog: core not answering, restarting");
    final ok = await _connectionRepo
        .reconnect(profile, _read(Preferences.disableMemoryLimit))
        .match((err) {
          loggy.warning("watchdog reconnect failed", err);
          return false;
        }, (_) => true)
        .run();
    if (ok) return;
    await _connectionRepo.disconnect().run();
    await _connectionRepo.connect(profile, _read(Preferences.disableMemoryLimit)).run();
  }

  Future<void> abortConnection() async {
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting():
          loggy.debug("aborting connection");
          await _disconnect();
        default:
      }
    }
  }

  final _singleStart = SingleCall();

  Future<void> _connect({bool restoring = false}) async {
    _singleStart.run(
      () async {
        await _connectThrottled(restoring: restoring);
      },
      onIgnored: () {
        loggy.debug("connect called while another connect/disconnect is still running, ignoring");
      },
    );
  }

  /// 1.19.3: stops whatever a failed start-up restore left of the core (marked as our own stop, so
  /// the connection keeper does not treat it as an unexpected one).
  Future<void> _releaseCore() async {
    lastIntentionalStopAt = DateTime.now();
    try {
      await _connectionRepo.disconnect().run();
    } catch (e) {
      loggy.debug("releasing the core after a failed restore: $e");
    }
  }

  Future<void> _connectThrottled({bool restoring = false}) async {
    final generation = intentGeneration;
    _setPreparing(true);
    final activeProfile = await _read(activeProfileProvider.future);
    if (activeProfile == null) {
      _setPreparing(false);
      loggy.info("no active profile, not connecting");
      return;
    }
    // cancelled while preparing: the core was never asked
    if (generation != intentGeneration) {
      _setPreparing(false);
      return;
    }
    Future<Either<ConnectionFailure, Unit>> attempt() =>
        _connectionRepo.connect(activeProfile, _read(Preferences.disableMemoryLimit)).run();
    final result = restoring
        ? await museRestoreConnect<ConnectionFailure>(
            attempt: attempt,
            isTransient: museIsTransientCoreFailure,
            reopenChannel: _connectionRepo.reopenCoreChannel,
            release: _releaseCore,
            stillWanted: () => generation == intentGeneration && _read(Preferences.startedByUser),
            log: loggy.warning,
          )
        : await attempt();
    _setPreparing(false);
    await result.match((ConnectionFailure err) async {
      if (generation != intentGeneration) return; // cancelled: no error dialog for it
      loggy.warning("error connecting", err);
      //Go err is not normal object to see the go errors are string and need to be dumped
      await _read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(museFriendlyPresent(err.present(_read(translationsProvider).requireValue)));
      loggy.warning(err);
      await _read(Preferences.startedByUser.notifier).update(false);
      state = AsyncError(err, StackTrace.current);
    }, (_) async {
      _read(museCoreProfileIdProvider.notifier).state = activeProfile.id;
      // 1.5.3: the subscription was switched while the core was starting: reload with the new one
      final now = _read(activeProfileProvider).valueOrNull;
      if (generation == intentGeneration && now != null && now.id != activeProfile.id) {
        loggy.info("active profile changed while connecting, reloading");
        Future.microtask(() => reconnect(now));
      }
      // 1.5.0: the user cancelled while the core was starting: undo the connect
      if (generation != intentGeneration && !_read(Preferences.startedByUser)) {
        loggy.info("connect finished after it was cancelled: stopping again");
        await _disconnect();
      }
    });
  }

  Future<void> _disconnect() async {
    lastIntentionalStopAt = DateTime.now();
    await _connectionRepo.disconnect().mapLeft((err) {
      loggy.warning("error disconnecting", err);
      _read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(_read(translationsProvider).requireValue));
      state = AsyncError(err, StackTrace.current);
    }).run();
  }
}

/// 穿云 1.5.0: the app is building / checking the config before the core starts (「准备配置」).
final museConnectPreparingProvider = StateProvider<bool>((ref) => false);

@Riverpod(keepAlive: true)
bool serviceRunning(Ref ref) {
  // ref.watch(coreRestartSignalProvider);
  return ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
}

class SingleCall {
  bool _running = false;

  Future<T> run<T>(Future<T> Function() task, {required T onIgnored}) async {
    if (_running) return onIgnored;

    _running = true;
    try {
      return await task();
    } finally {
      _running = false;
    }
  }
}

/// Whether the core is hot reloading; only the connection button shows it.
final hotReloadingProvider = StreamProvider<bool>(
  (ref) => ref.watch(connectionRepositoryProvider).watchHotReloading(),
);
