import 'package:hiddify/features/muse/data/motion_level.dart';
import 'package:hiddify/features/muse/data/quick_rules_provider.dart';
import 'package:hiddify/features/muse/home/new_node_test.dart';
import 'package:hiddify/features/muse/settings/android_settings.dart' show museRestoreLauncherIconProvider;
import 'package:hiddify/features/muse/desktop/hidden_release.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/home/auto_run.dart';
import 'package:hiddify/features/muse/desktop/title_bar.dart';
import 'package:hiddify/features/muse/data/core_extras_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/traffic_recorder.dart';
import 'package:hiddify/features/muse/home/net_watch.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart' show museDefaultColorStyle;
import 'package:hiddify/features/muse/home/widget_sync.dart';
import 'package:hiddify/features/muse/desktop/launch_control.dart';
import 'package:hiddify/features/muse/widget/muse_theme_reveal.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_theme.dart';
import 'package:accessibility_tools/accessibility_tools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/desktop/wifi_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/node_memory.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/app_based_routing/overview/app_based_routing_notifier.dart';
import 'package:hiddify/features/connection/widget/connection_wrapper.dart';
import 'package:hiddify/features/muse/home/auto_fastest.dart';
import 'package:hiddify/features/muse/desktop/connection_keeper.dart';
import 'package:hiddify/features/muse/home/core_watchdog.dart';
import 'package:hiddify/features/muse/home/node_failover.dart';
import 'package:hiddify/features/muse/home/subscription_alert.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/shortcut/shortcut_wrapper.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/window/widget/window_wrapper.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

bool _debugAccessibility = false;
bool isOnPauseCalled = false;

class App extends HookConsumerWidget with WidgetsBindingObserver, PresLogger {
  const App({super.key});

  void onInactive(WidgetRef ref) {
    onPause(ref);
  }

  void onPause(WidgetRef ref) {
    if (PlatformUtils.isDesktop) return;
    isOnPauseCalled = true;
    // 穿云: on Android the app's gRPC server and listeners stay up in the background.
    // Closing them on every pause (and "inactive" fires for the notification shade too)
    // forced a full core setup on return, next to the running VPN service.
    if (PlatformUtils.isAndroid) return;
    ref.read(hiddifyCoreServiceProvider).closeFront();
  }

  void onResume(WidgetRef ref) {
    // 穿云: only re-attach to the running core; never restart or replay the connection
    ref.read(hiddifyCoreServiceProvider).resume();
    if (PlatformUtils.isWindows) ref.read(museConnectionKeeperProvider)?.poke('app resumed');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isOnPauseCalled && PlatformUtils.isAndroid) ref.invalidate(appBasedRoutingProvider);
      isOnPauseCalled = false;
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    setupStateListener(ref);
    final router = ref.watch(goRouterNotiferProvider);
    final locale = ref.watch(localePreferencesProvider);
    final themeMode = ref.watch(themePreferencesProvider);
    final blackFollow = ref.watch(MusePrefs.pureBlackFollowSystem);
    // 1.18.0 P6: 动效档位（外观 › 动效 + Android 省电模式）
    final motionLevel = ref.watch(museAppMotionLevelProvider);
    museApplyPureBlack(themeMode.trueBlack);
    // 1.16.0 B9: 跟随系统 + 纯黑
    if (themeMode == AppThemeMode.system && blackFollow) museApplyPureBlack(true);
    // 1.4.0: accent colour and text size (设置 › 外观); 1.6.0 C7: custom accent, 纯黑, 文字缩放
    museApplyAccent(ref.watch(MusePrefs.accent));
    // 1.11.0: 配色风格 is fixed to 忠实 and text follows the system font size (a saved 配色风格 /
    // 文字缩放 from an older version is ignored, never applied)
    museApplyColorStyle(museDefaultColorStyle);
    // 1.19.0 P5: 外观 › 主题（浅色 / 纯黑 / 终端绿 / 暖纸；默认按深浅色）
    final themeStyle = MuseThemeStyle.fromKey(ref.watch(MusePrefs.themeStyle));
    if (themeStyle == MuseThemeStyle.black) museApplyPureBlack(true);
    if (themeStyle == MuseThemeStyle.light) museApplyPureBlack(false);
    final theme = AppTheme(themeMode, locale.preferredFontFamily, blackWhenSystemDark: blackFollow, style: themeStyle, fontFallback: locale.preferredFontFallback);
    final activeBreakpoint = Breakpoint(context).activeBreakpoint;

    ref.listen(foregroundProfilesUpdateNotifierProvider, (_, _) {});
    if (PlatformUtils.isAndroid) ref.listen(appBasedRoutingProvider, (_, _) {});
    // 穿云 1.3.0 智能保持连接 (logic/keep_alive.dart); 1.11.0: node failover has its own switch, timed-out node
    // folding, core watchdog, Windows connection keeper (recovery, system proxy restore, wake)
    ref.listen(museNodeFailoverProvider, (_, _) {});
    ref.listen(museAutoFastestProvider, (_, _) {});
    // 1.12.0: 订阅更新后对新增节点测一次速（已连接且在前台时）
    ref.listen(museNewNodeTestProvider, (_, _) {});
    ref.listen(museTempRulesResetProvider, (_, _) {});
    ref.listen(museCoreWatchdogProvider, (_, _) {});
    ref.listen(museConnectionKeeperProvider, (_, _) {});
    // 1.4.0: 测速 settings for the core, delay cache
    ref.listen(museCoreExtrasProvider, (_, _) {});
    ref.listen(museLatencyCacheWriterProvider, (_, _) {});
    ref.listen(museTrafficRecorderProvider, (_, _) {});
    // 1.4.1: wake re-check, 定时连接/断开 (1.11.0: 连接质量提醒 removed)
    ref.listen(museWakeCheckProvider, (_, _) {});
    ref.listen(museScheduleProvider, (_, _) {});
    ref.listen(museLaunchControlProvider, (_, _) {});
    // 穿云 1.3.0: node list kept for picking while disconnected; 网速 sparkline history
    ref.listen(museNodeCacheWriterProvider, (_, _) {});
    ref.listen(museSpeedHistoryProvider, (_, _) {});
    // 穿云 1.2.8: Windows too (toast); 每个订阅记住上次的节点; 连上后探测外网
    ref.listen(museSubscriptionAlertProvider, (_, _) {});
    ref.listen(museNodeMemoryProvider, (_, _) {});
    ref.listen(museReachProvider, (_, _) {});
    if (PlatformUtils.isDesktop) ref.listen(systemTrayNotifierProvider, (_, _) {});
    // 1.6.0 C8 (Windows): 全局快捷键 (nothing registered until one is bound) and 按需运行 (idle
    // unless switched on with a Wi‑Fi listed)
    if (PlatformUtils.isWindows) {
      ref.listen(museHotkeysProvider, (_, _) {});
      ref.listen(museOnDemandProvider, (_, _) {});
      // 1.15.0 R23: 按 Wi‑Fi 切换模式（列表为空时什么都不做）
      ref.listen(museWifiModeProvider, (_, _) {});
    }
    // 1.6.0 C9 (Android): 自动运行 (once per launch, after the first frame) and 按需运行
    if (PlatformUtils.isAndroid) {
      ref.listen(museAutoRunProvider, (_, _) {});
      ref.listen(museOnDemandProvider, (_, _) {});
      ref.listen(museWifiModeProvider, (_, _) {});
      // 1.11.0: 隐藏桌面图标 removed — an icon hidden before comes back once
      ref.listen(museRestoreLauncherIconProvider, (_, _) {});
      // 1.11.0: home-screen widget (node · delay, sent only on a change)
      ref.listen(museWidgetSyncProvider, (_, _) {});
    }

    // updating ActiveBreakpointNotifier value
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeBreakpointNotifierProvider.notifier).update(activeBreakpoint);
      });
      return null;
    }, [activeBreakpoint]);
    return WindowWrapper(
      ShortcutWrapper(
        ToastificationWrapper(
          child: ConnectionWrapper(
            MaterialApp.router(
              routerConfig: router,
              locale: locale.flutterLocale,
              supportedLocales: AppLocaleUtils.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              themeMode: theme.themeMode,
              theme: theme.lightTheme(null),
              darkTheme: theme.darkTheme(null),
              title: Constants.appName,
              builder: (context, routed) {
                final theme = Theme.of(context);
                // 1.17.0 R19: no pages while the window is hidden in the tray (Windows)
                Widget child = MuseHiddenRelease(child: routed ?? const SizedBox());
                // 1.18.0 P6: 动效档位给所有页面；「关闭」同时告诉 Flutter 自带控件不做动画
                child = museWrapMotion(context, motionLevel, child);
                // 1.19.0 P5: 切换主题时的圆形揭开（一次性；关闭档直接切换）
                child = MuseThemeReveal(child: child);
                if (kDebugMode && _debugAccessibility) {
                  return AccessibilityTools(checkFontOverflows: true, child: child);
                }
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  // 穿云: edge-to-edge, the pages draw behind transparent system bars; icons follow
                  // the theme (1.2.1: also set on every app bar, see museSystemOverlayStyle)
                  value: museSystemOverlayStyle(theme.brightness),
                  // 1.6.0 C8: Windows draws 穿云's own title bar above the pages
                  child: MuseTitleBarFrame(child: child),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // @override
  // Widget build1(BuildContext context, WidgetRef ref) {
  //   setupStateListener(ref);
  //   // setupQuickSettings(ref);
  //   final router = ref.watch(routerProvider);
  //   final locale = ref.watch(localePreferencesProvider);
  //   final themeMode = ref.watch(themePreferencesProvider);
  //   final theme = AppTheme(themeMode, locale.preferredFontFamily);
  //   final upgrader = ref.watch(upgraderProvider);

  //   ref.listen(foregroundProfilesUpdateNotifierProvider, (_, __) {});

  //   return WindowWrapper(
  //     TrayWrapper(
  //       ShortcutWrapper(
  //         ConnectionWrapper(
  //           PlatformProvider(
  //               settings: PlatformSettingsData(
  //                 iosUsesMaterialWidgets: true,
  //               ),
  //               builder: (context) => DynamicColorBuilder(
  //                     builder: (ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
  //                       return PlatformApp.router(
  //                         routerConfig: router,
  //                         locale: locale.flutterLocale,
  //                         supportedLocales: AppLocaleUtils.supportedLocales,
  //                         localizationsDelegates: GlobalMaterialLocalizations.delegates,
  //                         debugShowCheckedModeBanner: false,
  //                         material: (context, platform) => MaterialAppRouterData(
  //                           theme: theme.lightTheme(lightColorScheme),
  //                           darkTheme: theme.darkTheme(darkColorScheme),
  //                           themeMode: themeMode.flutterThemeMode,
  //                         ),
  //                         cupertino: (context, platform) {
  //                           final sysDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

  //                           return CupertinoAppRouterData(theme: theme.cupertinoThemeData(sysDark, lightColorScheme, darkColorScheme));
  //                         },
  //                         title: Constants.appName,
  //                         builder: (context, child) {
  //                           child = UpgradeAlert(
  //                             upgrader: upgrader,
  //                             navigatorKey: router.routerDelegate.navigatorKey,
  //                             child: child ?? const SizedBox(),
  //                           );
  //                           if (kDebugMode && _debugAccessibility) {
  //                             return AccessibilityTools(
  //                               checkFontOverflows: true,
  //                               child: child,
  //                             );
  //                           }
  //                           return child;
  //                         },
  //                       );
  //                     },
  //                   )),
  //         ),
  //       ),
  //     ),
  //   );
  // }

  void setupStateListener(WidgetRef ref) {
    final appLifecycleState = useAppLifecycleState();

    useEffect(() {
      loggy.info("current app state");
      loggy.info(appLifecycleState);
      if (appLifecycleState == AppLifecycleState.paused) {
        onPause(ref);
      } else if (appLifecycleState == AppLifecycleState.inactive) {
        onInactive(ref);
      } else if (appLifecycleState == AppLifecycleState.resumed) {
        onResume(ref);
      }
      return null;
    }, [appLifecycleState]);
  }
}
