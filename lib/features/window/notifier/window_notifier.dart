import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/desktop/connection_keeper.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/desktop/recovery.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/settings/service_mode_switch.dart' show MuseRead;
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'window_notifier.g.dart';

// 穿云: the pages are a phone-width column; below ~400x600 rows start to clip
/// 1.6.0 (#152): the narrowest window still lays out (phone layout under 600 dp)
const minimumWindowSize = Size(360, 560);
const defaultWindowSize = Size(900, 680);

/// 1.6.0 C8: 静默启动 / crash relaunch / --silent / 开机自启时静默 (see museStartSilently)
bool museStartSilentlyNow(MuseRead read) => museStartSilently(
  silentStart: read(Preferences.silentStart),
  afterCrash: MuseRecovery.relaunchedAfterCrash,
  args: museStartArgs,
  autostartSilent: read(MusePrefs.autostartSilent),
);

@Riverpod(keepAlive: true)
class WindowNotifier extends _$WindowNotifier with AppLogger {
  @override
  Future<void> build() async {
    if (!PlatformUtils.isDesktop) return;

    // if (Platform.isWindows) {
    //   loggy.debug("ensuring single instance");
    //   await WindowsSingleInstance.ensureSingleInstance([], "Hiddify");
    // }

    await windowManager.ensureInitialized();
    await initWindowState();
  }

  Future<void> saveWindowState() async {
    if (await windowManager.isMaximized()) {
      await ref.read(Preferences.windowMaximized.notifier).update(true);
    } else {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();

      await ref.read(Preferences.windowMaximized.notifier).update(false);
      await ref.read(Preferences.windowSize.notifier).update(size);
      await ref.read(Preferences.windowPosition.notifier).update(position);
    }
  }

  Future<void> initWindowState() async {
    final isMaximized = ref.read(Preferences.windowMaximized);
    loggy.debug("window state. maximized: $isMaximized");
    final size = ref.read(Preferences.windowSize);
    loggy.debug("window state. size: $size");
    final position = ref.read(Preferences.windowPosition);
    final isWindowVisible = position != null && await checkWindowVisivility(position, size);
    loggy.debug("window state. position: ${isWindowVisible ? position : "centered"}");
    final silentStart = museStartSilentlyNow(ref.read);
    loggy.debug("window state. silent start: ${silentStart ? "Enabled" : "Disabled"}");

    // 1.6.0 C8: 穿云's own title bar (window title string unchanged) and 窗口置顶, set before the
    // window first shows so it never flashes the system frame
    final customTitle = Platform.isWindows && ref.read(MusePrefs.customTitleBar);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: size,
        center: !isWindowVisible,
        minimumSize: minimumWindowSize,
        titleBarStyle: customTitle ? TitleBarStyle.hidden : null,
        alwaysOnTop: Platform.isWindows && ref.read(MusePrefs.alwaysOnTop) ? true : null,
      ),
    );
    if (isWindowVisible) {
      await windowManager.setPosition(position);
      loggy.debug("restoring window to position: $position");
    } else {
      loggy.debug("no previous position found, centering window");
    }
    if (isMaximized) {
      await windowManager.maximize();
      loggy.debug("restoring window to maximized state");
    }
    if (!silentStart) {
      await ref.read(windowNotifierProvider.notifier).show(focus: false);
      loggy.debug("showing app window on start");
    } else {
      loggy.debug("silent start, remain hidden accessible via tray");
    }
  }

  Future<bool> checkWindowVisivility(Offset windowPos, Size windowSize, {double tolerance = 10.0}) async {
    final Rect windowRect = windowPos & windowSize;

    final displays = await screenRetriever.getAllDisplays();

    for (final display in displays) {
      if (display.visiblePosition == null || display.visibleSize == null) {
        continue;
      }
      final Rect monitorRect = display.visiblePosition! & display.visibleSize!;
      if (windowRect.left >= (monitorRect.left - tolerance) &&
          windowRect.top >= (monitorRect.top - tolerance) &&
          windowRect.right <= (monitorRect.right + tolerance) &&
          windowRect.bottom <= (monitorRect.bottom + tolerance)) {
        return true;
      }
    }
    return false;
  }

  Future<void> show({bool focus = true}) async {
    await windowManager.show();
    if (focus) await windowManager.focus();
    // 穿云 1.2.1: the window coming back from the tray re-syncs the connection state (no setup)
    if (Platform.isWindows) {
      unawaited(ref.read(hiddifyCoreServiceProvider).resume().catchError((_) {}));
      ref.read(museConnectionKeeperProvider)?.poke('window shown');
    }
    if (Platform.isMacOS) {
      await windowManager.setSkipTaskbar(false);
    }
  }

  /// 1.6.0 C8 窗口置顶 (saved; Windows)
  Future<void> setAlwaysOnTop(bool on) async {
    await ref.read(MusePrefs.alwaysOnTop.notifier).update(on);
    if (PlatformUtils.isDesktop) await windowManager.setAlwaysOnTop(on);
  }

  /// 1.6.0 C8 自绘标题栏 on / off (saved; Windows)
  Future<void> setCustomTitleBar(bool on) async {
    await ref.read(MusePrefs.customTitleBar.notifier).update(on);
    if (Platform.isWindows) await windowManager.setTitleBarStyle(on ? TitleBarStyle.hidden : TitleBarStyle.normal);
  }

  Future<void> hide() async {
    await windowManager.hide();
    if (Platform.isMacOS) {
      await windowManager.setSkipTaskbar(true);
    }
  }

  Future<void> showOrHide() async {
    if (await windowManager.isVisible()) {
      await hide();
    } else {
      await show();
    }
  }

  Future<void> exit() async {
    await ref
        .read(connectionNotifierProvider.notifier)
        .abortConnection()
        .timeout(const Duration(seconds: 2))
        .catchError((e) {
          loggy.warning("error aborting connection on quit", e);
        });
    await trayManager.destroy();
    await windowManager.destroy();
  }
}
