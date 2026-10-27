import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

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

  static Color get brand => MusePalette.brand;

  // smooth on 120 Hz phones: the predictive-back aware Android transition
  static const _transitions = PageTransitionsTheme(
    builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
  );
  final AppThemeMode mode;
  final String fontFamily;

  ThemeData lightTheme(ColorScheme? lightColorScheme) {
    // 穿云: always the brand blue (Material You wallpaper colours are ignored on purpose)
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: brand).copyWith(
      primary: brand,
      onPrimary: Colors.white,
      surface: MusePalette.lightBgBottom,
      onSurface: MusePalette.lightText1,
      onSurfaceVariant: MusePalette.lightText2,
      outlineVariant: MusePalette.lightHairline,
      error: MusePalette.red,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MusePalette.lightBgBottom,
      appBarTheme: AppBarTheme(systemOverlayStyle: museSystemOverlayStyle(Brightness.light)),
      // 1.2.1: a lighter scrim behind dialogs and bottom sheets, so the dark status bar icons
      // stay readable on the light theme while one is open (the default black54 hid them)
      dialogTheme: const DialogThemeData(barrierColor: museLightScrim, backgroundColor: MusePalette.lightCard),
      bottomSheetTheme: const BottomSheetThemeData(modalBarrierColor: museLightScrim, backgroundColor: MusePalette.lightCard),
      navigationBarTheme: _navBar(false),
      navigationRailTheme: _rail(false),
      dividerTheme: const DividerThemeData(color: MusePalette.lightHairline, thickness: 0.5, space: 0.5),
      fontFamily: fontFamily,
      pageTransitionsTheme: _transitions,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  ThemeData darkTheme(ColorScheme? darkColorScheme) {
    // 穿云 1.3.0: night blue; 1.6.0 C7: 纯黑 (a switch under 深色) puts the page on true black
    final black = mode.trueBlack;
    final page = black ? MusePalette.blackBg : MusePalette.darkBgBottom;
    final card = black ? MusePalette.blackCard : MusePalette.darkCard;
    final inner = black ? MusePalette.blackInner : MusePalette.darkInner;
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark).copyWith(
      primary: brand,
      onPrimary: Colors.white,
      surface: page,
      onSurface: MusePalette.darkText1,
      onSurfaceVariant: MusePalette.darkText2,
      outlineVariant: MusePalette.darkHairline,
      surfaceContainerHighest: inner,
      surfaceContainerHigh: card,
      surfaceContainer: card,
      surfaceContainerLow: page,
      error: MusePalette.red,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      appBarTheme: AppBarTheme(systemOverlayStyle: museSystemOverlayStyle(Brightness.dark)),
      dialogTheme: DialogThemeData(backgroundColor: card),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: card),
      navigationBarTheme: _navBar(true),
      navigationRailTheme: _rail(true),
      dividerTheme: const DividerThemeData(color: MusePalette.darkHairline, thickness: 0.5, space: 0.5),
      fontFamily: fontFamily,
      pageTransitionsTheme: _transitions,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  String? get _family => fontFamily.isEmpty ? null : fontFamily;

  /// Bottom nav: icon + label; the selected item only changes colour (no pill indicator).
  NavigationBarThemeData _navBar(bool dark) {
    final idle = dark ? MusePalette.darkText2 : MusePalette.lightText2;
    return NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: dark ? (mode.trueBlack ? MusePalette.blackBg : MusePalette.darkBgBottom) : MusePalette.lightBgBottom,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: MuseIconSize.regular, color: s.contains(WidgetState.selected) ? brand : idle),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: _family,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? brand : idle,
        ),
      ),
    );
  }

  NavigationRailThemeData _rail(bool dark) {
    final idle = dark ? MusePalette.darkText2 : MusePalette.lightText2;
    return NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      selectedIconTheme: IconThemeData(size: MuseIconSize.regular, color: brand),
      unselectedIconTheme: IconThemeData(size: MuseIconSize.regular, color: idle),
      selectedLabelTextStyle: TextStyle(fontFamily: _family, fontSize: 12, fontWeight: FontWeight.w600, color: brand),
      unselectedLabelTextStyle: TextStyle(fontFamily: _family, fontSize: 12, fontWeight: FontWeight.w500, color: idle),
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
