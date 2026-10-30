// 穿云 1.6.0 C1 - colour tokens: a seeded colour scheme with flat surface levels, fixed status
// colours and an optional pure-black dark theme.
// Portions adapted from GPL-3.0 code, Copyright (C) chen08209 (see THIRD_PARTY_NOTICES.md).
// Part of 穿云 (GPLv3).

import 'dart:math';

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// 配色风格. 1.7.1: 忠实 (Material 3 fidelity, primary = the colour exactly as picked) is the
/// default; 标准 (tonal spot) / 鲜艳 / 表现力 / 柔和 / 单色 are the other Material 3 variants and
/// derive the primary; 鲜明 / 着色 keep the picked colour too (着色 also tints the surfaces).
enum MuseColorStyle {
  fidelity('fidelity', '忠实'),
  tonalSpot('tonalSpot', '标准'),
  vibrant('vibrant', '鲜艳'),
  expressive('expressive', '表现力'),
  vivid('vivid', '鲜明'),
  tinted('tinted', '着色'),
  soft('soft', '柔和'),
  monochrome('monochrome', '单色');

  const MuseColorStyle(this.key, this.title);

  final String key;
  final String title;

  static MuseColorStyle fromKey(String? key) => values.where((e) => e.key == key).firstOrNull ?? fidelity;

  /// 1.7.1: styles whose primary is the picked colour itself (see [museExactPrimary]).
  bool get keepsSeed => this == fidelity || this == vivid || this == tinted;

  /// The styles offered in 设置 › 外观 › 配色风格, in this order.
  static const offered = [fidelity, tonalSpot, vibrant, expressive, soft, vivid, tinted, monochrome];
}

/// 1.7.1: the default 配色风格 key (忠实).
const museDefaultColorStyle = 'fidelity';

/// 1.6.2: 景泰蓝, the default seed.
const museBrandSeed = Color(0xFF2775B6);

/// Preset seeds for 主题色: ten Chinese traditional colours, 景泰蓝 first (same order as
/// MuseAccent): 景泰蓝 宝蓝 竹青 松花 胭脂 枣红 藤黄 青碧 丁香 赭石 (1.7.1, sources on MuseAccent).
const museSeedPresets = <Color>[
  museBrandSeed,
  Color(0xFF4B5CC4),
  Color(0xFF789262),
  Color(0xFFBCE672),
  Color(0xFF9D2933),
  Color(0xFFC32136),
  Color(0xFFFFB61E),
  Color(0xFF48C0A3),
  Color(0xFFCCA4E3),
  Color(0xFF845A33),
];

/// 1.6.2: status lights (fixed, never follow 主题色): 葱青 / 杏黄 / 朱砂 / 墨灰.
const museStatusGreen = Color(0xFF0EB83A);
const museStatusYellow = Color(0xFFFFA631);
const museStatusRed = Color(0xFFFF461F);
const museStatusGrey = Color(0xFF758A99);

/// Surface tones of the dark theme (page / card / block / inset).
abstract final class MuseTone {
  static const darkPage = 6.0;
  static const darkCard = 15.0;
  static const darkBlock = 21.0;
  static const darkInset = 27.0;
  static const darkOnSurface = 97;
  static const surfaceChroma = 3.0;
  static const paperChroma = 1.5;
  static const containerChroma = 48.0;
  static const minAccent = 35.0;
  static const maxAccent = 60.0;
  static const minDarkAccent = 50.0;
  static const maxDarkAccent = 75.0;
  static const darkAccentLift = 3.0;

  /// 1.7.1: in the dark theme an exact primary darker than this contrast against the dark page
  /// is lifted (same hue / chroma) until it reaches it; the light theme never changes it.
  static const darkPrimaryContrast = 3.0;
  static const fidelityContainerChroma = 56.0;
  static const tintDivisor = 6.0;
  static const maxTintChroma = 10.0;
}

DynamicScheme _scheme(Hct source, bool dark, MuseColorStyle style) => switch (style) {
  MuseColorStyle.fidelity => SchemeFidelity(sourceColorHct: source, isDark: dark, contrastLevel: 0),
  MuseColorStyle.vivid || MuseColorStyle.tinted => SchemeContent(sourceColorHct: source, isDark: dark, contrastLevel: 0),
  MuseColorStyle.tonalSpot => SchemeTonalSpot(sourceColorHct: source, isDark: dark, contrastLevel: 0),
  MuseColorStyle.vibrant => SchemeVibrant(sourceColorHct: source, isDark: dark, contrastLevel: 0),
  MuseColorStyle.expressive => SchemeExpressive(sourceColorHct: source, isDark: dark, contrastLevel: 0),
  MuseColorStyle.soft => SchemeNeutral(sourceColorHct: source, isDark: dark, contrastLevel: 0),
  MuseColorStyle.monochrome => SchemeMonochrome(sourceColorHct: source, isDark: dark, contrastLevel: 0),
};

final _cache = <(int, bool, MuseColorStyle, bool), ColorScheme>{};

/// How many colour schemes were actually computed (cache misses; tests).
int museSchemeComputations = 0;

/// The app's colour scheme for [seed]: surfaces nearly neutral (chroma ≤ 3, light paper ≤ 1.5),
/// dark surfaces at tones 6 / 15 / 21 / 27, the accent's tone kept readable, and pure black
/// (dark only) lowering every surface so the page is #000. Results are cached.
ColorScheme museSeededScheme({
  Color seed = museBrandSeed,
  required Brightness brightness,
  MuseColorStyle style = MuseColorStyle.fidelity,
  bool pureBlack = false,
}) {
  final dark = brightness == Brightness.dark;
  final key = (seed.toARGB32(), dark, style, pureBlack && dark);
  final hit = _cache[key];
  if (hit != null) return hit;
  museSchemeComputations++;
  final source = Hct.fromInt(seed.toARGB32());
  final scheme = _scheme(source, dark, style);
  final primary = scheme.primaryPalette;
  // 1.7.1: styles that keep the picked colour build the container from its own hue at a higher
  // chroma, so large areas stay in the same family as the exact primary.
  final container = style.keepsSeed
      ? TonalPalette.of(source.hue, min(max(source.chroma, primary.chroma), MuseTone.fidelityContainerChroma))
      : TonalPalette.of(primary.hue, min(primary.chroma, MuseTone.containerChroma));
  final tint = style == MuseColorStyle.tinted ? min(source.chroma / MuseTone.tintDivisor, MuseTone.maxTintChroma) : null;
  Color neutral(DynamicColor role, double maxChroma, [double? darkTone]) {
    final palette = role.palette(scheme);
    return Color(Hct.from(palette.hue, tint ?? min(palette.chroma, maxChroma), (dark ? darkTone : null) ?? role.getTone(scheme)).toInt());
  }

  Color role(DynamicColor c) => Color(c.getArgb(scheme));
  final paper = dark ? MuseTone.surfaceChroma : MuseTone.paperChroma;
  final darkPage = dark ? neutral(MaterialDynamicColors.surface, paper, MuseTone.darkPage) : null;
  final accent = style.keepsSeed ? museExactPrimary(seed, darkPage: darkPage) : null;
  final primaryColor = accent?.$1 ?? role(MaterialDynamicColors.primary);
  var out = ColorScheme(
    brightness: brightness,
    primary: primaryColor,
    onPrimary: accent?.$2 ?? role(MaterialDynamicColors.onPrimary),
    surfaceTint: primaryColor,
    primaryContainer: Color(container.get(dark ? 30 : 90)),
    onPrimaryContainer: Color(container.get(dark ? 90 : 30)),
    secondary: role(MaterialDynamicColors.secondary),
    onSecondary: role(MaterialDynamicColors.onSecondary),
    secondaryContainer: role(MaterialDynamicColors.secondaryContainer),
    onSecondaryContainer: role(MaterialDynamicColors.onSecondaryContainer),
    tertiary: role(MaterialDynamicColors.tertiary),
    onTertiary: role(MaterialDynamicColors.onTertiary),
    tertiaryContainer: role(MaterialDynamicColors.tertiaryContainer),
    onTertiaryContainer: role(MaterialDynamicColors.onTertiaryContainer),
    error: role(MaterialDynamicColors.error),
    onError: role(MaterialDynamicColors.onError),
    errorContainer: role(MaterialDynamicColors.errorContainer),
    onErrorContainer: role(MaterialDynamicColors.onErrorContainer),
    outline: role(MaterialDynamicColors.outline),
    onSurface: dark
        ? Color(MaterialDynamicColors.onSurface.palette(scheme).get(MuseTone.darkOnSurface))
        : role(MaterialDynamicColors.onSurface),
    onSurfaceVariant: role(MaterialDynamicColors.onSurfaceVariant),
    inverseSurface: role(MaterialDynamicColors.inverseSurface),
    onInverseSurface: role(MaterialDynamicColors.inverseOnSurface),
    inversePrimary: role(MaterialDynamicColors.inversePrimary),
    shadow: role(MaterialDynamicColors.shadow),
    scrim: role(MaterialDynamicColors.scrim),
    surface: neutral(MaterialDynamicColors.surface, paper, MuseTone.darkPage),
    surfaceBright: neutral(MaterialDynamicColors.surfaceBright, paper),
    surfaceDim: neutral(MaterialDynamicColors.surfaceDim, MuseTone.surfaceChroma),
    surfaceContainerLowest: neutral(MaterialDynamicColors.surfaceContainerLowest, MuseTone.surfaceChroma),
    surfaceContainerLow: neutral(MaterialDynamicColors.surfaceContainerLow, MuseTone.surfaceChroma),
    surfaceContainer: neutral(MaterialDynamicColors.surfaceContainer, MuseTone.surfaceChroma, MuseTone.darkCard),
    surfaceContainerHigh: neutral(MaterialDynamicColors.surfaceContainerHigh, MuseTone.surfaceChroma, MuseTone.darkBlock),
    surfaceContainerHighest: neutral(MaterialDynamicColors.surfaceContainerHighest, MuseTone.surfaceChroma, MuseTone.darkInset),
    outlineVariant: neutral(MaterialDynamicColors.outlineVariant, 4),
  );
  if (pureBlack && dark) out = _pureBlack(out);
  if (_cache.length > 32) _cache.clear();
  return _cache[key] = out;
}

/// WCAG contrast ratio of two opaque colours.
double museContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// 1.7.1: black or white, whichever has the higher WCAG contrast on [c] (always ≥ 4.58:1).
Color museOnExact(Color c) =>
    museContrast(c, const Color(0xFFFFFFFF)) >= museContrast(c, const Color(0xFF000000)) ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

/// 1.7.1: primary / onPrimary for a style that keeps the picked colour: [seed] exactly (light
/// theme, and dark theme when it already reads on [darkPage]); in the dark theme a colour too dark
/// for [darkPage] (contrast < [MuseTone.darkPrimaryContrast]) is lifted in tone, same hue and
/// chroma, just enough. onPrimary is black or white by WCAG contrast.
(Color, Color) museExactPrimary(Color seed, {Color? darkPage}) {
  var primary = seed;
  if (darkPage != null && museContrast(seed, darkPage) < MuseTone.darkPrimaryContrast) {
    final h = Hct.fromInt(seed.toARGB32());
    for (var t = h.tone.ceilToDouble(); t <= 100; t++) {
      primary = Color(Hct.from(h.hue, h.chroma, t).toInt());
      if (museContrast(primary, darkPage) >= MuseTone.darkPrimaryContrast) break;
    }
  }
  return (primary, museOnExact(primary));
}

Color _shift(Color c, double delta) {
  final h = Hct.fromInt(c.toARGB32());
  return Color(Hct.from(h.hue, h.chroma, clampDouble(h.tone + delta, 0, 100)).toInt());
}

ColorScheme _pureBlack(ColorScheme s) {
  final shift = Hct.fromInt(s.surface.toARGB32()).tone;
  Color lower(Color c) => _shift(c, -shift);
  const black = Color(0xFF000000);
  return s.copyWith(
    surface: black,
    surfaceDim: black,
    surfaceContainerLowest: black,
    surfaceContainerLow: lower(s.surfaceContainerLow),
    surfaceContainer: lower(s.surfaceContainer),
    surfaceContainerHigh: lower(s.surfaceContainerHigh),
    surfaceContainerHighest: lower(s.surfaceContainerHighest),
    surfaceBright: lower(s.surfaceBright),
  );
}

/// Tone of a colour (0 = black, 100 = white).
double museTone(Color c) => Hct.fromInt(c.toARGB32()).tone;

/// Chroma of a colour.
double museChroma(Color c) => Hct.fromInt(c.toARGB32()).chroma;

final _success = TonalPalette.fromHct(Hct.fromInt(museStatusGreen.toARGB32()));
final _warning = TonalPalette.fromHct(Hct.fromInt(museStatusYellow.toARGB32()));
final _idle = TonalPalette.fromHct(Hct.fromInt(museStatusGrey.toARGB32()));

/// Status colours that never follow the seed (1.6.2: 葱青 / 杏黄 / 朱砂 / 墨灰, toned for text
/// on light / dark surfaces), and the second data series (primary at 45 %).
extension MuseSchemeStatus on ColorScheme {
  bool get _dark => brightness == Brightness.dark;
  Color get success => Color(_success.get(_dark ? 80 : 40));
  Color get successContainer => Color(_success.get(_dark ? 30 : 90));
  Color get warning => Color(_warning.get(_dark ? 80 : 40));
  Color get warningContainer => Color(_warning.get(_dark ? 30 : 90));
  /// 朱砂 (a filled destructive button keeps white text ≥ 3:1)
  Color get destructive => museStatusRed;

  /// 墨灰: not tested / not connected / unknown
  Color get idle => _dark ? Color(_idle.get(70)) : museStatusGrey;
  Color get secondSeries => primary.withValues(alpha: 0.45);
  Color get modalScrim => scrim.withValues(alpha: 0.32);

  /// Delay colour: ≤ 600 ms green, slower orange, timeout / failure red (null = not tested).
  Color? delayColor(int? ms) {
    if (ms == null) return null;
    if (ms <= 0) return error;
    if (ms <= 600) return success;
    return warning;
  }
}

/// Surface levels: page < card < block < inset. A card picks the level above the one it sits on.
enum MuseSurface {
  page,
  card,
  block,
  inset;

  MuseSurface get above => switch (this) {
    page => card,
    card => block,
    block || inset => inset,
  };

  Color color(ColorScheme s) {
    final dark = s.brightness == Brightness.dark;
    return switch (this) {
      page => dark ? s.surface : s.surfaceContainer,
      card => dark ? s.surfaceContainer : s.surfaceBright,
      block => dark ? s.surfaceContainerHigh : s.surfaceContainer,
      inset => dark ? s.surfaceContainerHighest : s.surfaceContainerHighest,
    };
  }
}

/// Tells descendants which surface level they sit on.
class MuseSurfaceScope extends InheritedWidget {
  const MuseSurfaceScope({super.key, required this.level, required super.child});

  final MuseSurface level;

  static MuseSurface of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MuseSurfaceScope>()?.level ?? MuseSurface.page;

  @override
  bool updateShouldNotify(MuseSurfaceScope old) => old.level != level;
}
