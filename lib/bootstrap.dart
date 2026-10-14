import 'dart:async';

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
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
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

Future<void> lazyBootstrap(WidgetsBinding widgetsBinding, Environment env) async {
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }
  // phase 1 — console and the in-memory history, before the folders are known
  logStart();
  FlutterError.onError = Logger.logFlutterError;
  WidgetsBinding.instance.platformDispatcher.onError = Logger.logPlatformDispatcherError;

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

  // The log level decides this now. There is no second debug switch to keep in
  // sync, and the core reaches the same conclusion from the same value.
  final debug = kDebugMode || container.read(ConfigOptions.logLevel).isVerbose;

  if (PlatformUtils.isWindows) {
    // 穿云: TUN mode is only used while running as administrator
    await _safeInit("windows admin", WindowsAdmin.detect, timeout: 5000);
    // a killed earlier run may have left 系统代理 pointing at its dead port
    await _safeInit(
      "stale system proxy",
      () => WindowsProxyGuard.clearStale(container.read(ConfigOptions.mixedPort)),
      timeout: 6000,
    );
  }

  if (PlatformUtils.isDesktop) {
    await _safeInit("window controller", () => container.read(windowNotifierProvider.future));

    final silentStart = container.read(Preferences.silentStart);
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
    }

    if (PlatformUtils.isAndroid) {
      await _safeInit("android display mode", () async {
        await FlutterDisplayMode.setHighRefreshRate();
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      });
    }
  }
}
