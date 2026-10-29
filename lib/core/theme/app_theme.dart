import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';

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

  /// 1.6.2: the accent colour itself (主题色), the scheme's seed
  static Color get seed => MusePalette.seed;

  // smooth on 120 Hz phones: the predictive-back aware Android transition
  static const _transitions = PageTransitionsTheme(
    builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
  );
  final AppThemeMode mode;
  final String fontFamily;

  /// 1.6.1: the Material 3 colour scheme seeded by 主题色 in the chosen 配色风格 (纯黑 lowers the
  /// dark surfaces). Material You wallpaper colours are ignored on purpose.
  ColorScheme scheme(Brightness brightness) => museSeededScheme(
    seed: seed,
    brightness: brightness,
    style: MuseColorStyle.fromKey(MusePalette.colorStyle),
    pureBlack: brightness == Brightness.dark && mode.trueBlack,
  );

  ThemeData lightTheme(ColorScheme? lightColorScheme) => _cached(scheme(Brightness.light));

  ThemeData darkTheme(ColorScheme? darkColorScheme) => _cached(scheme(Brightness.dark));

  /// 1.6.1: ThemeData is built once per (colour scheme, font) and reused, so rebuilding the app
  /// (or switching back to a style used before) does not rebuild the theme. The schemes
  /// themselves are cached by museSeededScheme; the few combinations (seeds × styles ×
  /// brightness × 纯黑) keep this small.
  static final _themes = <(ColorScheme, String), ThemeData>{};

  /// How many ThemeData were actually built (tests).
  static int debugThemeBuilds = 0;

  ThemeData _cached(ColorScheme s) => _themes.putIfAbsent((s, fontFamily), () {
    debugThemeBuilds++;
    return _theme(s);
  });

  ThemeData _theme(ColorScheme s) {
    final dark = s.brightness == Brightness.dark;
    final page = MuseSurface.page.color(s);
    final card = MuseSurface.card.color(s);
    // dialogs and sheets sit one level above the page (dark: one more, so they lift off it)
    final floating = dark ? MuseSurface.block.color(s) : card;
    return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      scaffoldBackgroundColor: page,
      canvasColor: page,
      appBarTheme: AppBarTheme(
        systemOverlayStyle: museSystemOverlayStyle(s.brightness),
        backgroundColor: page,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: s.onSurface,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedSuperellipseBorder(borderRadius: MuseRadius.cardAll),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: s.onSurfaceVariant,
        minTileHeight: MuseSize.rowMin,
        contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
        titleTextStyle: TextStyle(fontFamily: _family, fontSize: 16, height: 1.3, color: s.onSurface),
        subtitleTextStyle: TextStyle(fontFamily: _family, fontSize: 13, height: 1.35, color: s.onSurfaceVariant),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.onPrimary : s.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.primary : s.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? Colors.transparent : s.outline,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: MuseShape.full)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: s.secondaryContainer,
          selectedForegroundColor: s.onSecondaryContainer,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: MuseShape.sm,
        selectedColor: s.secondaryContainer,
        side: BorderSide(color: s.outlineVariant),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primaryContainer,
        foregroundColor: s.onPrimaryContainer,
        elevation: 0,
        shape: MuseShape.lg,
      ),
      // 1.2.1: a lighter scrim behind dialogs and bottom sheets, so the dark status bar icons
      // stay readable on the light theme while one is open (the default black54 hid them)
      dialogTheme: DialogThemeData(
        barrierColor: dark ? null : museLightScrim,
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
        shape: MuseShape.xxl,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        modalBarrierColor: dark ? null : museLightScrim,
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(color: floating, surfaceTintColor: Colors.transparent, shape: MuseShape.md),
      navigationBarTheme: _navBar(s),
      navigationRailTheme: _rail(s),
      dividerTheme: DividerThemeData(color: s.outlineVariant, thickness: MuseSize.hairline, space: MuseSize.hairline),
      fontFamily: fontFamily,
      pageTransitionsTheme: _transitions,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  String? get _family => fontFamily.isEmpty ? null : fontFamily;

  /// 1.6.1 bottom nav (Material 3): icon + label, the selected icon sits in a tonal pill.
  NavigationBarThemeData _navBar(ColorScheme s) => NavigationBarThemeData(
    height: MuseSize.navBarHeight,
    elevation: 0,
    backgroundColor: MuseSurface.card.color(s),
    surfaceTintColor: Colors.transparent,
    indicatorColor: s.secondaryContainer,
    indicatorShape: MuseShape.full,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    iconTheme: WidgetStateProperty.resolveWith(
      (st) => IconThemeData(
        size: MuseIconSize.regular,
        color: st.contains(WidgetState.selected) ? s.onSecondaryContainer : s.onSurfaceVariant,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (st) => TextStyle(
        fontFamily: _family,
        fontSize: 12,
        fontWeight: st.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        color: st.contains(WidgetState.selected) ? s.onSurface : s.onSurfaceVariant,
      ),
    ),
  );

  NavigationRailThemeData _rail(ColorScheme s) => NavigationRailThemeData(
    backgroundColor: Colors.transparent,
    indicatorColor: s.secondaryContainer,
    indicatorShape: MuseShape.full,
    selectedIconTheme: IconThemeData(size: MuseIconSize.regular, color: s.onSecondaryContainer),
    unselectedIconTheme: IconThemeData(size: MuseIconSize.regular, color: s.onSurfaceVariant),
    selectedLabelTextStyle: TextStyle(fontFamily: _family, fontSize: 12, fontWeight: FontWeight.w600, color: s.onSurface),
    unselectedLabelTextStyle: TextStyle(fontFamily: _family, fontSize: 12, fontWeight: FontWeight.w500, color: s.onSurfaceVariant),
  );

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
