import 'dart:async';
import 'dart:convert';

import 'package:hiddify/features/muse/logic/core_extras.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/logger/core_logger.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/log/model/log_level.dart' as config_log_level;
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper_stub.dart'
    if (dart.library.io) 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart' as logging;
import 'package:rxdart/rxdart.dart';

class HiddifyCoreService with InfraLogger {
  HiddifyCoreService(this.ref);
  final Ref ref;

  // CoreHiddifyCoreService() {}
  final core = getCoreInterface();

  CoreStatus currentState = const CoreStatus.stopped();
  final statusController = BehaviorSubject<CoreStatus>();
  final CallOptions? grpcOptions = null; //CallOptions(timeout: const Duration(milliseconds: 10000));
  final Map<String, StreamSubscription?> subscriptions = {};
  List<OutboundGroup> latest = [];

  /// Whether [setup] has succeeded once in this engine; the core's gRPC servers then stay up.
  bool _ready = false;
  bool get isReady => _ready;

  /// 穿云: the app came back to the foreground. On Android the core (and the VPN service)
  /// keeps running in the background, so nothing is set up again and no restart signal is
  /// sent: only a status listener that was lost is re-armed. Re-running setup used to replay
  /// the connection status (Disconnected → Connected), which vibrated and re-ran the connect
  /// animation, and set the core up again next to the running VPN service.
  ///
  /// 穿云 Windows 1.2.1: the same on desktop. The core runs inside this process and its gRPC
  /// server stays up while the window is hidden/minimised, so restoring the window used to run
  /// a full setup() (a new gRPC channel each time, a restart signal, and on any setup error a
  /// pushed 未连接). Now: re-arm a lost status listener and re-sync the state once.
  Future<void> resume() async {
    if (!_ready) return init();
    if (!PlatformUtils.isAndroid && !PlatformUtils.isDesktop) return init();
    if (!subscriptions.containsKey("bgStatusListener")) {
      _statusRecoveries = 0;
      await startListeningStatus("bg", core.bgClient);
    }
    if (PlatformUtils.isDesktop) await resyncStatus();
  }

  Future<void> init() async {
    final result = await setup().run();
    await result.match(
      (e) async {
        loggy.error(e);
        if (PlatformUtils.isIOS) return;
        // 穿云: a setup error while the core still answers is not a disconnect
        if (PlatformUtils.isDesktop && _ready && await ping()) {
          loggy.warning("setup failed but the core answers, keeping the current state: $e");
          return;
        }
        statusController.add(const CoreStatus.stopped());
        ref.read(inAppNotificationControllerProvider).showErrorToast(e);
      },
      (_) async {
        loggy.info("Hiddify-core setup done");
        ref.read(coreRestartSignalProvider.notifier).restart();
      },
    );
  }

  /// 穿云 1.2.1: the core's own state, asked directly (the status listener sends the current
  /// state first). Null when the core does not answer.
  Future<CoreStatus?> queryCoreState({Duration timeout = const Duration(seconds: 3)}) async {
    if (!core.isInitialized()) return null;
    try {
      final event = await core.bgClient
          .coreInfoListener(Empty(), options: CallOptions(timeout: timeout))
          .first
          .timeout(timeout);
      return CoreStatus.fromCoreInfo(event);
    } catch (e) {
      loggy.debug("core state query failed: $e");
      return null;
    }
  }

  /// 穿云 1.2.1: puts the core's real state on the status stream when the app shows another one
  /// (a lost or late event). Returns the core's state, null when it does not answer.
  Future<CoreStatus?> resyncStatus() async {
    final real = await queryCoreState();
    if (real == null) return null;
    if (real.runtimeType != currentState.runtimeType) {
      loggy.info("status re-sync: app showed ${currentState.runtimeType}, core is ${real.runtimeType}");
      currentState = real;
      statusController.add(real);
    }
    return real;
  }

  /// 穿云 1.2.1: re-arms the status listener when it was lost.
  Future<void> ensureStatusListener() async {
    if (!_ready || subscriptions.containsKey("bgStatusListener")) return;
    _statusRecoveries = 0;
    try {
      await startListeningStatus("bg", core.bgClient);
    } catch (e) {
      loggy.warning("re-arming the status listener failed: $e");
    }
  }

  /// Smoke tests only (CHUANYUN_SMOKE_CONTROL): the status stream breaks while the core runs.
  Future<void> debugBreakStatusStream() async {
    final sub = subscriptions.remove("bgStatusListener");
    await sub?.cancel();
    loggy.warning("smoke: status stream broken on purpose");
    unawaited(_recoverStatus("bg"));
  }

  /// Smoke tests only (CHUANYUN_SMOKE_CONTROL): the core stops without the app asking for it.
  Future<void> debugStopCoreBehindTheApp() async {
    loggy.warning("smoke: stopping the core behind the app's back");
    await core.bgClient.stop(Empty());
  }

  /// validates config by path and save it
  ///
  /// [path] is used to save validated config
  /// [tempPath] includes base config, possibly invalid
  /// [debug] indicates if debug mode (avoid in prod)

  TaskEither<String, Unit> validateConfigByPath(String path, String tempPath, bool debug) {
    return TaskEither(() async {
      try {
        final response = await core.fgClient.parse(ParseRequest(tempPath: tempPath, configPath: path, debug: false));
        if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      } catch (e) {
        await setup().run();
        final response = await core.fgClient.parse(ParseRequest(tempPath: tempPath, configPath: path, debug: false));
        if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      }
      return right(unit);
    });
  }

  TaskEither<String, String> generateFullConfigByPath(String path) {
    return TaskEither(() async {
      final response = await core.fgClient.parse(ParseRequest(configPath: path, debug: false));
      if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      return right(response.content);
    });
  }

  TaskEither<String, Unit> setup() {
    return TaskEither(() async {
      try {
        final directories = ref.read(appDirectoriesProvider).requireValue;
        final debug = kDebugMode || ref.read(ConfigOptions.logLevel).isVerbose;
        final setupResponse = await core.setup(directories, debug, 3);

        if (setupResponse.isNotEmpty) {
          return left(setupResponse);
        }

        await startListeningLogs("fg", core.fgClient);
        // await startListeningStatus("fg", core.fgClient);
        if (!core.isSingleChannel()) {
          await startListeningLogs("bg", core.bgClient);
        }
        // only the first value: a later setup must not replay a stale status
        if (!statusController.hasValue) statusController.add(currentState);
        await startListeningStatus("bg", core.bgClient);
        _ready = true;
        // ref.read(coreRestartSignalProvider.notifier).restart();
        return right(unit);
      } catch (e) {
        return left(e.toString());
      }
    });
  }

  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) {
    return TaskEither(() async {
      loggy.debug("changing options");
      // latestOptions = options;
      try {
        final res = await core.fgClient.changeHiddifySettings(
          ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(museApplyCoreExtras(options.toJson()))),
        );
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
        await core.bgClient.changeHiddifySettings(
          ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(museApplyCoreExtras(options.toJson()))),
        );
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unavailable) {
          loggy.debug("background core is not started yet! $e");
        } else {
          rethrow;
        }
      }

      return right(unit);
    });
  }

  TaskEither<ConnectionFailure, Unit> start(String path, String name, bool disableMemoryLimit) {
    return TaskEither(() async {
      statusController.add(currentState = const CoreStatus.starting());
      loggy.debug("starting");
      // 穿云 Windows: remember the user's own proxy settings before sing-box replaces them
      if (PlatformUtils.isWindows) await WindowsProxyGuard.saveBeforeConnect(ref.read(ConfigOptions.mixedPort));
      final background = await core.setupBackground(path, name);
      if (background != const CoreStatus.started()) {
        statusController.add(currentState = const CoreStatus.stopped());
        return left(background.getCoreAlert() ?? const ConnectionFailure.unexpected("failed to start core"));
      }
      // Armed again on every connect, not only when there are two channels.
      // listenSingle drops a subscription for good when its stream errors, and
      // a gRPC connection being terminated does exactly that, so a listener
      // armed once at setup does not survive the engine restarting. Re-listening
      // is idempotent: listenSingle cancels the previous one for the same key.
      await startListeningLogs("fg", core.fgClient);
      if (!core.isSingleChannel()) {
        await startListeningLogs("bg", core.bgClient);
        await startListeningStatus("bg", core.bgClient);
      }
      // if (latestOptions != null) {
      //   await core.bgClient.changeHiddifySettings(
      //     ChangeHiddifySettingsRequest(
      //       hiddifySettingsJson: jsonEncode(latestOptions!.toJson()),
      //     ),
      //   );
      // }
      // final content = await File(path).readAsString();
      // loggy.debug("starting with content: $content");
      try {
        final res = await core.bgClient.start(
          StartRequest(
            configPath: path,
            configName: name,
            // configContent: content,
            disableMemoryLimit: disableMemoryLimit,
          ),
        );
        ref.read(coreRestartSignalProvider.notifier).restart();
        if (res.messageType != MessageType.ALREADY_STARTED && res.messageType != MessageType.EMPTY) {
          final alert = res.message.contains("denied") ? CoreAlert.requestVPNPermission : CoreAlert.startFailed;
          currentState = CoreStatus.stopped(
            alert: alert,
            message: "failed to start core ${res.messageType} ${res.message}",
          );

          statusController.add(currentState);
          if (PlatformUtils.isWindows) await WindowsProxyGuard.restore("连接失败");

          return left(
            currentState.getCoreAlert() ??
                ConnectionFailure.unexpected("failed to start core ${res.messageType} ${res.message}"),
          );
        }
      } on GrpcError catch (e) {
        loggy.error("failed to start bg core: $e");
        ref.read(coreRestartSignalProvider.notifier).restart();
        if (e.code == StatusCode.unavailable) {
          return left(const ConnectionFailure.unexpected("background core is not started yet!"));
        }
        // throw InvalidConfig(e.message);
        // throw DioException.connectionError(requestOptions: RequestOptions(), reason: e.codeName, error: e);

        // throw DioException(requestOptions: RequestOptions(), error: e);
        return left(const ConnectionFailure.unexpected("failed to start background core"));
      }

      // if (res.messageType != MessageType.EMPTY) return left(res);

      return right(unit);
    });
  }

  TaskEither<String, Unit> stop() {
    return TaskEither(() async {
      loggy.debug("stopping");
      var errMsg = "";
      try {
        await core.bgClient.stop(Empty());
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unknown && !(e.message?.contains("HTTP/2") ?? false)) {
          errMsg = e.message ?? "failed to stop core: $e";

          loggy.error("failed to stop bg core: $e");
        }
      } catch (e) {
        loggy.error("failed to stop bg core: $e");
        // left("failed to stop core: $e");
      }
      if (!await core.stop()) {}
      statusController.add(currentState = const CoreStatus.stopped());
      // 穿云 Windows: sing-box only blanks the system proxy; put the user's own settings back
      if (PlatformUtils.isWindows) await WindowsProxyGuard.restore("断开");
      if (errMsg.isNotEmpty) return left(errMsg);
      return right(unit);
    });
  }

  /// Applies a changed config to the running core: first as a hot reload, which keeps the core
  /// (and its connections) running; when the core cannot hot reload it (e.g. the TUN inbound
  /// changed) or the hot reload fails, the core is restarted instead.
  TaskEither<String, Unit> reload(String path, String name, bool disableMemoryLimit) {
    return TaskEither(() async {
      loggy.debug("hot reloading");
      try {
        final res = await core.bgClient.hotReload(
          StartRequest(configPath: path, configName: name, disableMemoryLimit: disableMemoryLimit),
        );
        if (res.messageType == MessageType.EMPTY) return right(unit);
        loggy.info("hot reload not applied, restarting: ${res.messageType} ${res.message}");
      } on GrpcError catch (e) {
        loggy.warning("hot reload failed, restarting: $e");
      }
      final restarted = await restart(path, name, disableMemoryLimit).run();
      if (restarted.isRight() || !PlatformUtils.isDesktop) return restarted;
      // 穿云 Windows 1.2.1: a restart right after the stop can lose the race for the mixed port
      // (12334) or a rule-set download; one more try before giving up
      loggy.warning("restart failed, retrying once in 2 s: ${restarted.getLeft().toNullable()}");
      await Future<void>.delayed(const Duration(seconds: 2));
      final again = await restart(path, name, disableMemoryLimit).run();
      if (again.isLeft() && PlatformUtils.isWindows) await WindowsProxyGuard.restore("重启失败");
      return again;
    });
  }

  TaskEither<String, Unit> restart(String path, String name, bool disableMemoryLimit) {
    return TaskEither(() async {
      loggy.debug("restarting");
      // if (!await core.restart(path, name)) {
      try {
        final res = await core.bgClient.restart(
          StartRequest(configPath: path, configName: name, disableMemoryLimit: disableMemoryLimit, delayStart: true),
        );
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
      } on GrpcError catch (e) {
        loggy.error("failed to restart bg core: $e");
        if (e.code == StatusCode.unknown && !(e.message?.contains("HTTP/2 error") ?? false)) {
          return left("${e.message}");
        }
      }

      return right(unit);
      // await stop().run();
      // return await start(path, name, disableMemoryLimit).run();
      // }
      // if (!core.isSingleChannel()) {
      //   await startListeningStatus("bg", core.bgClient);
      //   await startListeningLogs("bg", core.bgClient);
      // }
      // return right(unit);
    });
  }

  TaskEither<String, Unit> resetTunnel() {
    return TaskEither(() async {
      // only available on iOS (and macOS later)
      if (!PlatformUtils.isIOS) {
        throw UnimplementedError("reset tunnel function unavailable on platform");
      }

      // loggy.debug("resetting tunnel");
      final res = await core.resetTunnel();
      if (res) {
        return right(unit);
      }
      return left("failed to reset tunnel");
    });
  }

  // Stream<List<OutboundGroup>> watchGroups() async* {
  //   loggy.debug("watching groups");
  //   yield* core.bgClient.outboundsInfo(Empty()).map((event) => event.items);
  //   // res?.cancel();
  // }

  Stream<OutboundGroup?> watchGroup() async* {
    loggy.debug("watching group");
    // interrupt managed by core

    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty group stream");
      return;
    }
    try {
      yield* core.bgClient.outboundsInfo(Empty()).map((event) => event.items.isEmpty ? null : event.items.first);
    } catch (e) {
      loggy.error("error watching group: $e");
      rethrow;
    }
    // //emitting first event immediately
    // yield* core.bgClient.outboundsInfo(Empty()).take(1).map((event) => event.items.isEmpty ? null : event.items.first);
    // //emitting other event after every 4 seconds(latest event)
    // yield* core.bgClient.outboundsInfo(Empty()).throttleTime(const Duration(seconds: 4), leading: false, trailing: true).map((event) => event.items.isEmpty ? null : event.items.first);
  }

  Stream<List<OutboundGroup>> watchActiveGroups() async* {
    loggy.info("watching active groups");

    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty group stream");
      return;
    }

    try {
      yield* core.bgClient
          .mainOutboundsInfo(Empty())
          .map((event) {
            return latest = event.items.toList();
          })
          .startWith(latest);
    } catch (e) {
      loggy.error("error watching active groups: $e");
      rethrow;
    }
  }

  //
  // Stream<SingboxStatus> watchStatus() => _status;

  /// 穿云 1.2 watchdog: whether the core answers a gRPC call within [timeout].
  Future<bool> ping({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      await core.bgClient.getSystemInfo(Empty(), options: CallOptions(timeout: timeout));
      return true;
    } catch (e) {
      loggy.warning("core health ping failed: $e");
      return false;
    }
  }

  ResponseStream<SystemInfo> watchStats() {
    loggy.debug("watching stats");
    try {
      return core.bgClient.getSystemInfoStream(Empty());
    } catch (e) {
      loggy.error("error watching stats: $e");
      rethrow;
    }
  }

  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) {
    return TaskEither(() async {
      loggy.debug("selecting outbound");
      try {
        final res = await core.bgClient.selectOutbound(
          SelectOutboundRequest(groupTag: groupTag, outboundTag: outboundTag),
          options: CallOptions(timeout: const Duration(seconds: 1)),
        );
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");

        return right(unit);
      } catch (e) {
        loggy.error("error selecting outbound: $e");
        rethrow;
      }
    });
  }

  TaskEither<String, Unit> urlTest(String tag) {
    return TaskEither(() async {
      loggy.debug("url test");
      try {
        final res = await core.bgClient.urlTest(UrlTestRequest(tag: tag));
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");

        return right(unit);
      } catch (e) {
        loggy.error("error in url test: $e");
        rethrow;
      }
    });
  }

  // The 300-message buffer and its BehaviorSubject are gone. They existed so
  // the logs page could show history when it opened, and only ever held the
  // engine's lines. The in-memory ring in core/logger does that for every
  // category, so the page reads it instead.

  // TaskEither<String, WarpResponse> generateWarpConfig({
  //   required String licenseKey,
  //   required String previousAccountId,
  //   required String previousAccessToken,
  // }) {
  //   return TaskEither(() async {
  //     loggy.debug("generating warp config");
  //     final warpConfig = await core.fgClient.generateWarpConfig(
  //       GenerateWarpConfigRequest(
  //         licenseKey: licenseKey,
  //         accountId: previousAccountId,
  //         accessToken: previousAccessToken,
  //       ),
  //     );
  //     // if (warpConfig.code != ResponseCode.OK) return left("${warpConfig.code} ${warpConfig.message}");
  //     final WarpResponse warp = (
  //       log: warpConfig.log,
  //       accountId: warpConfig.account.accountId,
  //       accessToken: warpConfig.account.accessToken,
  //       wireguardConfig: jsonEncode(warpConfig.config.toProto3Json()),
  //     );
  //     return right(warp);
  //   });
  // }

  Stream<CoreStatus> watchStatus() async* {
    await startListeningStatus("bg", core.bgClient);
    yield* statusController.stream;
    // .endWith(const CoreStatus.stopped());
  }

  Future<void> startListeningStatus(String key, CoreClient cc) async {
    await listenSingle<CoreStatus>(
      "${key}StatusListener",
      () => cc.coreInfoListener(Empty(), options: grpcOptions).map((event) {
        _statusRecoveries = 0;
        currentState = CoreStatus.fromCoreInfo(event);
        statusController.add(currentState);
        return currentState;
      }),
      // 穿云: the end of the status stream is not a disconnect. The stream also ends or
      // errors when the gRPC connection is reset (engine paused, HTTP/2 GOAWAY, ...), and
      // reporting "stopped" then showed 已断开 while the tunnel was still up. Re-subscribe
      // while the core's server is alive; report stopped only once it is really gone.
      onError: (error) {
        loggy.warning("status stream error in ${key}StatusListener: $error");
        _recoverStatus(key);
      },
      onDone: () {
        loggy.info("status stream ended in ${key}StatusListener");
        _recoverStatus(key);
      },
    );
  }

  bool _statusRecovering = false;

  /// Re-subscriptions since the last status event; bounded so a stream that keeps failing
  /// right away does not turn into a busy loop (resume() re-arms it later).
  int _statusRecoveries = 0;

  Future<void> _recoverStatus(String key) async {
    if (_statusRecovering) return;
    if (++_statusRecoveries > 8) {
      loggy.warning("status stream keeps failing, waiting for the next resume/connect");
      return;
    }
    _statusRecovering = true;
    try {
      // 穿云 Windows 1.2.1: on desktop the core runs in this process; whether it is alive is
      // asked over gRPC (it used to be "false" here, so every end of the status stream turned
      // into 未连接 after 300 ms while the tunnel kept running).
      final attempts = PlatformUtils.isDesktop ? 8 : 5;
      for (var attempt = 1; attempt <= attempts; attempt++) {
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
        // re-armed meanwhile (connect, resume)
        if (subscriptions.containsKey("${key}StatusListener")) return;
        final alive = PlatformUtils.isAndroid ? await core.isActiveBg() : await ping(timeout: const Duration(seconds: 3));
        if (!alive) break;
        try {
          // the core sends its current state first, so the UI is right again at once
          await startListeningStatus(key, key == "fg" ? core.fgClient : core.bgClient);
          return;
        } catch (e) {
          loggy.warning("re-subscribing status failed: $e");
        }
      }
      if (subscriptions.containsKey("${key}StatusListener")) return;
      // desktop: only a core that really stopped (or stopped answering) is shown as 未连接
      if (PlatformUtils.isDesktop) {
        final real = await queryCoreState();
        if (real != null && real is! CoreStopped) {
          loggy.info("status stream lost but the core is ${real.runtimeType}; keeping it");
          if (real.runtimeType != currentState.runtimeType) {
            currentState = real;
            statusController.add(real);
          }
          return;
        }
      }
      if (currentState is! CoreStopped) {
        loggy.info("core gRPC server is gone, reporting stopped");
        currentState = const CoreStatus.stopped();
        statusController.add(currentState);
      }
    } finally {
      _statusRecovering = false;
    }
  }

  Future<void> startListeningLogs(String key, CoreClient cc) async {
    final logLevel = ref.read(ConfigOptions.logLevel);
    final coreLogLevel = getCoreLogLevel(logLevel);
    final listenKey = "${key}LogListener";
    // await stopListenSingle(listenKey);
    await listenSingle<LogMessage>(listenKey, () {
      return cc.logListener(LogRequest(level: coreLogLevel), options: grpcOptions).map((event) {
        // Handle incoming event
        // One message becomes one record. The old code split on newlines
        // first, but the engine already sends one line per message, so the
        // split only allocated a list and multiplied the work per burst.
        coreLogFor(event.type).log(getLogLevel(event.level), event.message);
        return event;
      });
    });
  }

  Future<void> stopListenSingle(String key) async {
    // Collect keys to remove first
    final keysToRemove = subscriptions.entries
        .where((entry) => entry.key.startsWith(key))
        .map((entry) => entry.key)
        .toList();

    // Cancel and remove
    for (final k in keysToRemove) {
      final sub = subscriptions[k];
      await sub?.cancel(); // cancel the subscription

      subscriptions.remove(k);
    }
  }

  Future<StreamSubscription<T>?> listenSingle<T>(
    String key,
    Stream<T> Function() stream, {
    Function(dynamic error)? onError,
    void Function()? onDone,
  }) async {
    if (subscriptions.containsKey(key)) {
      // return subscriptions[key] as StreamSubscription<T>?;
      await stopListenSingle(key);
    }
    late final StreamSubscription<T> sub;
    sub = stream().listen(
      (event) {},
      cancelOnError: true,
      onError: (error) {
        // a listener that was replaced meanwhile must not touch its successor
        if (!identical(subscriptions[key], sub)) return;
        loggy.error('Stream error: $error');
        subscriptions.remove(key);
        onError?.call(error);
      },
      onDone: () {
        if (!identical(subscriptions[key], sub)) return;
        subscriptions.remove(key);
        onDone?.call();
      },
    );
    subscriptions[key] = sub;
    return subscriptions[key] as StreamSubscription<T>?;
  }

  /// Six engine levels onto six logging levels, nothing merged.
  ///
  /// TRACE used to have no case here and fell into the default, so trace lines
  /// arrived looking as important as info and could not be filtered out. FATAL
  /// used to collapse into error because loggy had nothing above it.
  logging.Level getLogLevel(LogLevel level) {
    return switch (level) {
      LogLevel.TRACE => logging.Level.FINEST,
      LogLevel.DEBUG => logging.Level.FINE,
      LogLevel.INFO => logging.Level.INFO,
      LogLevel.WARNING => logging.Level.WARNING,
      LogLevel.ERROR => logging.Level.SEVERE,
      LogLevel.FATAL => logging.Level.SHOUT,
      // the proto enum is a generated class, so a default is unavoidable
      _ => logging.Level.INFO,
    };
  }

  LogLevel getCoreLogLevel(config_log_level.LogLevel level) {
    return switch (level) {
      config_log_level.LogLevel.trace => LogLevel.TRACE,
      config_log_level.LogLevel.debug => LogLevel.DEBUG,
      config_log_level.LogLevel.info => LogLevel.INFO,
      config_log_level.LogLevel.warn => LogLevel.WARNING,
      config_log_level.LogLevel.error => LogLevel.ERROR,
      config_log_level.LogLevel.fatal => LogLevel.FATAL,
      config_log_level.LogLevel.panic => LogLevel.FATAL,
      // ignore: unreachable_switch_case
      _ => LogLevel.INFO, // Default case
    };
  }

  Future<void> closeFront() async {
    if (!core.isInitialized()) {
      return;
    }
    if (!core.isSingleChannel()) {
      await stopListenSingle("fg");
      await stopListenSingle("bg");
      // Only one of the two modes matches how the channel was opened, so the
      // other one always throws. Both are attempted and the failure is logged.
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL_INSECURE));
      } catch (e) {
        loggy.debug("closing fg client in insecure mode failed: $e");
      }
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL));
      } catch (e) {
        loggy.debug("closing fg client in normal mode failed: $e");
      }
    }
  }

  TaskEither<String, LANIPResponse> getLANIP() {
    return TaskEither(() async {
      try {
        final response = await core.fgClient.getLANIP(Empty());
        return right(response);
      } catch (e) {
        loggy.error("failed to get LAN IP: $e");
        return left(e.toString());
      }
    });
  }
}
