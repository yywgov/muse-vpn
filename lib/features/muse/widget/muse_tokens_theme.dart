// 穿云 1.19.0 P5 主题：外观 › 主题 = 默认（按「深浅色」）/ 浅色 / 纯黑 / 终端绿 / 暖纸。
// 浅色、纯黑复用已有的配色（纯黑即 1.6.0 C7 / 1.16.0 B9 的纯黑背景）；终端绿、暖纸是两套固定的令牌色板，
// 正文与次要文字对每一层表面都满足 WCAG 4.5:1（测试 v1190_theme_test 校验）。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';

enum MuseThemeStyle {
  /// 默认：按 外观 › 深浅色（跟随系统 / 浅色 / 深色，含纯黑开关），即 1.18 的行为
  auto('auto', '默认'),
  light('light', '浅色'),
  black('black', '纯黑'),
  terminal('terminal', '终端绿'),
  paper('paper', '暖纸');

  const MuseThemeStyle(this.key, this.title);

  final String key;
  final String title;

  static MuseThemeStyle fromKey(String? key) => values.where((e) => e.key == key).firstOrNull ?? auto;

  /// 这个主题固定的深浅；默认主题为 null（按深浅色设置）。
  ThemeMode? get forcedMode => switch (this) {
    auto => null,
    light || paper => ThemeMode.light,
    black || terminal => ThemeMode.dark,
  };

  /// 自带色板的主题（主题色不生效）。
  bool get ownPalette => this == terminal || this == paper;

  String get describe => switch (this) {
    auto => '按「深浅色」设置',
    light => '始终浅色',
    black => '纯黑背景，有机发光屏幕更省电',
    terminal => '黑底绿字，自带配色',
    paper => '米色纸面、深棕文字，自带配色',
  };
}

/// 终端绿：近黑的绿底、荧光绿文字。
const museTerminalScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF39FF7A),
  onPrimary: Color(0xFF00210C),
  primaryContainer: Color(0xFF0F3A1E),
  onPrimaryContainer: Color(0xFF9DFFB8),
  secondary: Color(0xFF7CE0A0),
  onSecondary: Color(0xFF00210C),
  secondaryContainer: Color(0xFF143322),
  onSecondaryContainer: Color(0xFFB5F5CB),
  tertiary: Color(0xFFC8F55A),
  onTertiary: Color(0xFF1C2600),
  tertiaryContainer: Color(0xFF2D3A0C),
  onTertiaryContainer: Color(0xFFE2FF9E),
  error: Color(0xFFFF7A6B),
  onError: Color(0xFF3B0600),
  errorContainer: Color(0xFF4A1212),
  onErrorContainer: Color(0xFFFFD6D6),
  surface: Color(0xFF050805),
  onSurface: Color(0xFF6CFF94),
  onSurfaceVariant: Color(0xFF46C46E),
  surfaceDim: Color(0xFF050805),
  surfaceBright: Color(0xFF1A2B1D),
  surfaceContainerLowest: Color(0xFF020302),
  surfaceContainerLow: Color(0xFF0A100B),
  surfaceContainer: Color(0xFF0C130D),
  surfaceContainerHigh: Color(0xFF132015),
  surfaceContainerHighest: Color(0xFF1A2B1D),
  outline: Color(0xFF2E7A47),
  outlineVariant: Color(0xFF1E3A26),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFCFF5D9),
  onInverseSurface: Color(0xFF0C130D),
  inversePrimary: Color(0xFF00873A),
  surfaceTint: Color(0xFF39FF7A),
);

/// 暖纸：米色纸面、深棕文字、赭石强调色。
const museWarmPaperScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF8B4513),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF2D9C2),
  onPrimaryContainer: Color(0xFF3E1C05),
  secondary: Color(0xFF6B5B2E),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFEADFB8),
  onSecondaryContainer: Color(0xFF2E2608),
  tertiary: Color(0xFF2F6B5A),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFCFE8DE),
  onTertiaryContainer: Color(0xFF0E2E25),
  error: Color(0xFFA32A1F),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF7D4CE),
  onErrorContainer: Color(0xFF410A05),
  surface: Color(0xFFF6EFDF),
  onSurface: Color(0xFF2E2418),
  onSurfaceVariant: Color(0xFF5A4A36),
  surfaceDim: Color(0xFFE3D7BE),
  surfaceBright: Color(0xFFFBF6EA),
  surfaceContainerLowest: Color(0xFFFFFBF2),
  surfaceContainerLow: Color(0xFFF3EBD9),
  surfaceContainer: Color(0xFFEFE6D2),
  surfaceContainerHigh: Color(0xFFE9DFC8),
  surfaceContainerHighest: Color(0xFFE3D7BE),
  outline: Color(0xFF8A7A62),
  outlineVariant: Color(0xFFD4C6AA),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF3A3024),
  onInverseSurface: Color(0xFFF6EFDF),
  inversePrimary: Color(0xFFF0B48A),
  surfaceTint: Color(0xFF8B4513),
);

/// 主题自带的色板（只对终端绿 / 暖纸有）；其余返回 null，用主题色生成的配色。
ColorScheme? museThemeOwnScheme(MuseThemeStyle style) => switch (style) {
  MuseThemeStyle.terminal => museTerminalScheme,
  MuseThemeStyle.paper => museWarmPaperScheme,
  _ => null,
};

/// 揭开过渡的时长（标准档）；精简档淡入用 [museThemeFadeMs]。
const museThemeRevealMs = 400;
const museThemeFadeMs = 200;
