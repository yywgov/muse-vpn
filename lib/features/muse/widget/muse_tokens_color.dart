// 穿云 1.6.0 C1 - colour tokens: a seeded colour scheme with flat surface levels, fixed status
// colours and an optional pure-black dark theme.
// Portions adapted from GPL-3.0 code, Copyright (C) chen08209 (see THIRD_PARTY_NOTICES.md).
// Part of 穿云 (GPLv3).

import 'dart:math';

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// 配色风格: 鲜明 / 着色 / 柔和 / 单色.
enum MuseColorStyle {
  vivid('vivid', '鲜明'),
  tinted('tinted', '着色'),
  soft('soft', '柔和'),
  monochrome('monochrome', '单色');

  const MuseColorStyle(this.key, this.title);

  final String key;
  final String title;

  static MuseColorStyle fromKey(String? key) => values.where((e) => e.key == key).firstOrNull ?? vivid;
}

/// The brand blue: the default seed.
const museBrandSeed = Color(0xFF2F6BFF);

/// Preset seeds for 主题色 (brand blue first).
const museSeedPresets = <Color>[
  museBrandSeed,
  Color(0xFF16A34A),
  Color(0xFF7C3AED),
  Color(0xFF0EA5E9),
  Color(0xFFDB2777),
  Color(0xFFEA580C),
  Color(0xFF0D9488),
  Color(0xFF64748B),
];

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
  static const tintDivisor = 6.0;
  static const maxTintChroma = 10.0;
}

DynamicScheme _scheme(Hct source, bool dark, MuseColorStyle style) => switch (style) {
  MuseColorStyle.vivid || MuseColorStyle.tinted => SchemeContent(sourceColorHct: source, isDark: dark, contrastLevel: 0),
  MuseColorStyle.soft => SchemeTonalSpot(sourceColorHct: source, isDark: dark, contrastLevel: 0),
  MuseColorStyle.monochrome => SchemeMonochrome(sourceColorHct: source, isDark: dark, contrastLevel: 0),
};

final _cache = <(int, bool, MuseColorStyle, bool), ColorScheme>{};

/// The app's colour scheme for [seed]: surfaces nearly neutral (chroma ≤ 3, light paper ≤ 1.5),
/// dark surfaces at tones 6 / 15 / 21 / 27, the accent's tone kept readable, and pure black
/// (dark only) lowering every surface so the page is #000. Results are cached.
ColorScheme museSeededScheme({
  Color seed = museBrandSeed,
  required Brightness brightness,
  MuseColorStyle style = MuseColorStyle.vivid,
  bool pureBlack = false,
}) {
  final dark = brightness == Brightness.dark;
  final key = (seed.toARGB32(), dark, style, pureBlack && dark);
  final hit = _cache[key];
  if (hit != null) return hit;
  final source = Hct.fromInt(seed.toARGB32());
  final scheme = _scheme(source, dark, style);
  final primary = scheme.primaryPalette;
  final container = TonalPalette.of(primary.hue, min(primary.chroma, MuseTone.containerChroma));
  final tint = style == MuseColorStyle.tinted ? min(source.chroma / MuseTone.tintDivisor, MuseTone.maxTintChroma) : null;
  Color neutral(DynamicColor role, double maxChroma, [double? darkTone]) {
    final palette = role.palette(scheme);
    return Color(Hct.from(palette.hue, tint ?? min(palette.chroma, maxChroma), (dark ? darkTone : null) ?? role.getTone(scheme)).toInt());
  }

  Color role(DynamicColor c) => Color(c.getArgb(scheme));
  final paper = dark ? MuseTone.surfaceChroma : MuseTone.paperChroma;
  final accent = switch (style) {
    MuseColorStyle.vivid || MuseColorStyle.tinted => _accent(seed, source, dark),
    _ => null,
  };
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

(Color, Color) _accent(Color seedColor, Hct seed, bool dark) {
  final tone = dark
      ? clampDouble(seed.tone + MuseTone.darkAccentLift, MuseTone.minDarkAccent, MuseTone.maxDarkAccent)
      : clampDouble(seed.tone, MuseTone.minAccent, MuseTone.maxAccent);
  final primary = tone == seed.tone ? seedColor : Color(Hct.from(seed.hue, seed.chroma, tone).toInt());
  final on = tone <= MuseTone.maxAccent ? const Color(0xFFFFFFFF) : Color(TonalPalette.of(seed.hue, seed.chroma).get(10));
  return (primary, on);
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

final _success = TonalPalette.fromHct(Hct.fromInt(0xFF4CAF50));
final _warning = TonalPalette.fromHct(Hct.fromInt(0xFFFF9800));

/// Status colours: fixed green / orange that never follow the seed, iOS-style destructive red,
/// and the second data series (primary at 45 %).
extension MuseSchemeStatus on ColorScheme {
  bool get _dark => brightness == Brightness.dark;
  Color get success => Color(_success.get(_dark ? 80 : 40));
  Color get successContainer => Color(_success.get(_dark ? 30 : 90));
  Color get warning => Color(_warning.get(_dark ? 80 : 40));
  Color get warningContainer => Color(_warning.get(_dark ? 30 : 90));
  Color get destructive => Color(_dark ? 0xFFFF4245 : 0xFFFF383C);
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
