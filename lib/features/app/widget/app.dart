import 'package:accessibility_tools/accessibility_tools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
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
    final theme = AppTheme(themeMode, locale.preferredFontFamily);
    final activeBreakpoint = Breakpoint(context).activeBreakpoint;

    ref.listen(foregroundProfilesUpdateNotifierProvider, (_, _) {});
    if (PlatformUtils.isAndroid) ref.listen(appBasedRoutingProvider, (_, _) {});
    ref.listen(museNodeFailoverProvider, (_, _) {});
    ref.listen(museAutoFastestProvider, (_, _) {});
    ref.listen(museCoreWatchdogProvider, (_, _) {});
    // 穿云 Windows 1.2.1: 连接守护 (auto-recovery, system proxy restore, wake from sleep)
    ref.listen(museConnectionKeeperProvider, (_, _) {});
    if (PlatformUtils.isAndroid) ref.listen(museSubscriptionAlertProvider, (_, _) {});
    if (PlatformUtils.isDesktop) ref.listen(systemTrayNotifierProvider, (_, _) {});

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
              themeMode: themeMode.flutterThemeMode,
              theme: theme.lightTheme(null),
              darkTheme: theme.darkTheme(null),
              title: Constants.appName,
              builder: (context, child) {
                final theme = Theme.of(context);
                child = child ?? const SizedBox();
                if (kDebugMode && _debugAccessibility) {
                  return AccessibilityTools(checkFontOverflows: true, child: child);
                }
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  // 穿云: edge-to-edge, the pages draw behind transparent system bars; icons follow
                  // the theme (1.2.1: also set on every app bar, see museSystemOverlayStyle)
                  value: museSystemOverlayStyle(theme.brightness),
                  child: child,
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
