import 'dart:async';
import 'dart:io';

import 'package:hiddify/features/muse/data/muse_health.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/data/bundled_compat_rule_sets.dart';
import 'package:hiddify/features/muse/data/bundled_rule_sets.dart';
import 'package:hiddify/features/muse/data/muse_prefs_migration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/logger.dart';
import 'package:hiddify/core/logger/logger_setup.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_migration.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app/widget/app.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';

import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/muse/data/windows_admin.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/desktop/recovery.dart';
import 'package:hiddify/features/muse/desktop/smoke_control.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/riverpod_observer.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:hiddify/features/muse/data/crash_recorder.dart';

/// 1.11.0 冷启动: jobs deferred until the first frame is on screen.
final museAfterFirstFrame = <Future<void> Function()>[];

/// 1.11.0: time since lazyBootstrap started (the log line 「first frame at」 reads it).
final museColdStart = Stopwatch();

Future<void> lazyBootstrap(WidgetsBinding widgetsBinding, Environment env) async {
  museColdStart.start();
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }
  // phase 1 — console and the in-memory history, before the folders are known
  logStart();
  // 穿云 1.4.1: errors also go to the local crash log (诊断 › 导出崩溃记录)
  FlutterError.onError = (d) {
    Logger.logFlutterError(d);
    MuseCrashRecorder.onFlutterError(d);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (e, st) {
    MuseCrashRecorder.record(e, st);
    return Logger.logPlatformDispatcherError(e, st);
  };

  final stopWatch = Stopwatch()..start();

  final container = ProviderContainer(
    overrides: [environmentProvider.overrideWithValue(env)],
    observers: [RiverpodObserver()],
  );

  // 穿云 1.1.1: an init step that throws is logged and skipped; runApp always runs, so a
  // broken preference or a slow disk never leaves the user on a frozen splash screen.
  try {
    await _bootstrapSteps(container, env);
  } catch (e, stackTrace) {
    Logger.bootstrap.error("bootstrap step failed, starting the app anyway", e, stackTrace);
  }

  Logger.bootstrap.info("bootstrap took [${stopWatch.elapsedMilliseconds}ms]");
  stopWatch.stop();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const App(),
    ),
  );
  // 1.11.0 冷启动: work the first frame does not need runs right after it
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final job in museAfterFirstFrame) {
      unawaited(job());
    }
    museAfterFirstFrame.clear();
    Logger.bootstrap.info("first frame at [${museColdStart.elapsedMilliseconds}ms]");
  });

  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }
}

Future<T> _init<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  final stopWatch = Stopwatch()..start();
  Logger.bootstrap.info("initializing [$name]");
  Future<T> func() => timeout != null ? initializer().timeout(Duration(milliseconds: timeout)) : initializer();
  try {
    final result = await func();
    Logger.bootstrap.debug("[$name] initialized in ${stopWatch.elapsedMilliseconds}ms");
    return result;
  } catch (e, stackTrace) {
    Logger.bootstrap.error("[$name] error initializing", e, stackTrace);
    rethrow;
  } finally {
    stopWatch.stop();
  }
}

Future<T?> _safeInit<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  try {
    return await _init(name, initializer, timeout: timeout);
  } catch (e) {
    return null;
  }
}

Future<void> _bootstrapSteps(ProviderContainer container, Environment env) async {
  await _init("directories", () => container.read(appDirectoriesProvider.future));
  // phase 2 — the folders exist, so app.log can be opened
  logAddFile(container.read(logPathResolverProvider).appFile().path);

  final appInfo = await _safeInit("app info", () => container.read(appInfoProvider.future));
  await _init("preferences", () => container.read(sharedPreferencesProvider.future));
  try {
    MuseCrashRecorder.attach(container.read(sharedPreferencesProvider).requireValue);
    // 1.13.0: 安全模式 / 上次异常 known before anything connects
    MuseHealth.attach(container.read(sharedPreferencesProvider).requireValue);
    await container.read(museHealthProvider.future).timeout(const Duration(seconds: 2));
  } catch (_) {}
  // The ring starts at a safe default and only now learns the size the user
  // picked, since nothing could be read from disk before this point.
  logRing.capacity = container.read(Preferences.logBufferSize);

  await _init("preferences migration", () async {
    try {
      await PreferencesMigration(sharedPreferences: container.read(sharedPreferencesProvider).requireValue).migrate();
    } catch (e, stackTrace) {
      Logger.bootstrap.error("preferences migration failed", e, stackTrace);
      if (env == Environment.dev) rethrow;
      Logger.bootstrap.info("clearing preferences");
      await container.read(sharedPreferencesProvider).requireValue.clear();
    }
  });
  // 穿云 1.6.0 (#217): versioned migrations of the 穿云 settings (idempotent, never throws)
  await _init("muse preferences migration", () => musePrefsMigrateStore(container.read(sharedPreferencesProvider).requireValue));
  // 穿云 1.7.0 M3: the core this process uses (Windows loads its library once per run)
  try {
    MuseCoreSelection.init(container.read(sharedPreferencesProvider).requireValue.get(museCoreKindPrefKey));
  } catch (_) {}

  // The log level decides this now. There is no second debug switch to keep in
  // sync, and the core reaches the same conclusion from the same value.
  final debug = kDebugMode || container.read(ConfigOptions.logLevel).isVerbose;

  if (PlatformUtils.isWindows) {
    // 穿云: TUN mode is only used while running as administrator
    await _safeInit("windows admin", WindowsAdmin.detect, timeout: 5000);
    // 穿云 1.2.1: a killed earlier run may have left 系统代理 pointing at its dead port: the
    // user's own settings are restored, then ChuanyunGuard.exe watches this process
    await _safeInit("stale system proxy", () async {
      final dirs = container.read(appDirectoriesProvider).requireValue;
      final dataDir = p.join(dirs.workingDir.absolute.path, 'data');
      await Directory(dataDir).create(recursive: true);
      ChuanyunPlatform.desktopDataDir = dataDir;
      if (MuseRecovery.relaunchedAfterCrash) {
        await ChuanyunPlatform.recordDisconnect('穿云异常退出后由守护进程自动重启，恢复连接');
      }
      await WindowsProxyGuard.startUp(dataDir: dataDir, mixedPort: container.read(ConfigOptions.mixedPort));
    }, timeout: 12000);
  }

  if (PlatformUtils.isDesktop) {
    await _safeInit("window controller", () => container.read(windowNotifierProvider.future));

    // relaunched by the guard after a crash: back into the tray, reconnect quietly
    final silentStart = museStartSilentlyNow(container.read);
    Logger.bootstrap.debug("silent start [${silentStart ? "Enabled" : "Disabled"}]");
    if (!silentStart) {
      await _safeInit("show window", () => container.read(windowNotifierProvider.notifier).show(focus: false));
    } else {
      Logger.bootstrap.debug("silent start, remain hidden accessible via tray");
    }
    await _safeInit("auto start service", () => container.read(autoStartNotifierProvider.future));
  }
  // phase 3 — a log file is worth its cost on desktop, or while debugging.
  // On a phone in release it only burns storage nobody reads.
  await _safeInit(
    "logging",
    () async => logFinish(keepFile: debug || PlatformUtils.isDesktop),
  );

  // marks where this run begins, since the file now spans several
  if (appInfo != null) {
    logMarkRun(appInfo.format());
    Logger.bootstrap.info(appInfo.format());
  }

  // 1.11.0 冷启动: the bundled lists are copied once per app build (a stamp in the preferences)
  // instead of every list being read from the APK on every start to compare sizes
  await _safeInit("bundled rule-sets", () async {
    final dirs = container.read(appDirectoriesProvider).requireValue;
    final prefs = container.read(sharedPreferencesProvider).requireValue;
    final stamp = appInfo == null ? '' : '${appInfo.version}+${appInfo.buildNumber}';
    final base = dirs.baseDir.absolute.path;
    if (museBundledRuleSetsCurrent(saved: prefs.getString(museRuleSetsStampKey), stamp: stamp, baseDir: base, workingDir: dirs.workingDir.absolute.path)) return;
    await museInstallBundledRuleSets(base);
    // 1.9.0 #14: 兼容内核's default lists too (first connect needs no download)
    await museInstallBundledCompatRuleSets(dirs.workingDir.absolute.path);
    if (stamp.isNotEmpty) await prefs.setString(museRuleSetsStampKey, stamp);
  }, timeout: 5000);
  await _safeInit("profile repository", () => container.read(profileRepositoryProvider.future));

  await _safeInit("translations", () => container.read(translationsProvider.future));

  await _safeInit("active profile", () => container.read(activeProfileProvider.future), timeout: 1000);
  await _safeInit("hiddify-core", () => container.read(hiddifyCoreServiceProvider).init());

  // Eagerly listen to activeProxyNotifierProvider to force synchronous evaluation in microtasks,
  // avoiding lazy build-phase flushes and sibling dependency collisions on the Home page.
  container.listen(activeProxyNotifierProvider, (previous, next) {});

  if (!kIsWeb) {
    if (PlatformUtils.isDesktop) {
      await _safeInit(
        "restore previous connection",
        () => container.read(connectionNotifierProvider.notifier).restoreConnectionOnStartup(),
        timeout: 5000,
      );
      await _safeInit("system tray", () => container.read(systemTrayNotifierProvider.future), timeout: 1000);
      if (PlatformUtils.isWindows) {
        await _safeInit("smoke control", () => MuseSmokeControl.startIfRequested(container));
      }
    }

    if (PlatformUtils.isAndroid) {
      // 1.11.0 冷启动: edge-to-edge before the first frame (the layout depends on it); the refresh
      // rate is asked for after it (a platform call the first frame does not need)
      await _safeInit("android edge-to-edge", () => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      museAfterFirstFrame.add(() => _safeInit("android display mode", FlutterDisplayMode.setHighRefreshRate));
    }
  }
}
