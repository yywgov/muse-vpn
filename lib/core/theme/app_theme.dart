import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

/// 穿云 1.2.1: status / navigation bar icons that contrast with the page: dark icons on the light
/// theme, light icons on the dark and true-black themes. Every app bar (AppBarTheme) and the app
/// root use it, so it follows a theme change at once and no page falls back to the AppBar's
/// guess from a transparent background (which picked white icons on the light theme).
SystemUiOverlayStyle museSystemOverlayStyle(Brightness themeBrightness) {
  final dark = themeBrightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark, // Android
    statusBarBrightness: dark ? Brightness.dark : Brightness.light, // iOS
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
  );
}

/// 32 % black: dims the page behind a dialog / bottom sheet on the light theme.
const museLightScrim = Color(0x52000000);

class AppTheme {
  AppTheme(this.mode, this.fontFamily);

  static const brand = Color(0xFF2F6BFF);

  // smooth on 120 Hz phones: the predictive-back aware Android transition
  static const _transitions = PageTransitionsTheme(
    builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
  );
  final AppThemeMode mode;
  final String fontFamily;

  ThemeData lightTheme(ColorScheme? lightColorScheme) {
    // 穿云: always the brand blue (Material You wallpaper colours are ignored on purpose)
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: brand,
    ).copyWith(primary: brand, onPrimary: Colors.white, surface: const Color(0xFFF3F6FB));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF3F6FB),
      appBarTheme: AppBarTheme(systemOverlayStyle: museSystemOverlayStyle(Brightness.light)),
      // 1.2.1: a lighter scrim behind dialogs and bottom sheets, so the dark status bar icons
      // stay readable on the light theme while one is open (the default black54 hid them)
      dialogTheme: const DialogThemeData(barrierColor: museLightScrim),
      bottomSheetTheme: const BottomSheetThemeData(modalBarrierColor: museLightScrim),
      fontFamily: fontFamily,
      pageTransitionsTheme: _transitions,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  ThemeData darkTheme(ColorScheme? darkColorScheme) {
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark).copyWith(
      primary: brand,
      onPrimary: Colors.white,
      surface: mode.trueBlack ? Colors.black : const Color(0xFF0E1A3A),
      surfaceContainerHighest: mode.trueBlack ? const Color(0xFF1C1C1C) : const Color(0xFF1B2747),
      surfaceContainerHigh: mode.trueBlack ? const Color(0xFF151515) : null,
      surfaceContainer: mode.trueBlack ? const Color(0xFF101010) : null,
      surfaceContainerLow: mode.trueBlack ? const Color(0xFF0A0A0A) : null,
      surfaceContainerLowest: mode.trueBlack ? Colors.black : null,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: mode.trueBlack ? Colors.black : const Color(0xFF0E1A3A),
      appBarTheme: AppBarTheme(systemOverlayStyle: museSystemOverlayStyle(Brightness.dark)),
      fontFamily: fontFamily,
      pageTransitionsTheme: _transitions,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark, ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
    final bool isDark = switch (mode) {
      AppThemeMode.system => sysDark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
      AppThemeMode.black => true,
    };
    final def = CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light);
    // final def = CupertinoThemeData(brightness: Brightness.dark);

    // return def;
    final defaultMaterialTheme = isDark ? darkTheme(darkColorScheme) : lightTheme(lightColorScheme);
    return MaterialBasedCupertinoThemeData(
      materialTheme: defaultMaterialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: fontFamily),
          ).copyWith(),
          barBackgroundColor: def.barBackgroundColor,
          scaffoldBackgroundColor: def.scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
