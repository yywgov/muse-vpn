// 穿云 1.3.0 - design tokens: the one place for spacing, radii, type, colours, motion and the
// page background. Screens use these names instead of hand-written numbers / hex literals.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';

/// Spacing scale (dp). Nothing else is used for gaps and paddings.
abstract final class MuseSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s24 = 24.0;
  static const s32 = 32.0;

  /// Page side margin: 16 on a phone, 24 on the desktop.
  static double page(BuildContext context) => MediaQuery.sizeOf(context).width >= 720 ? s24 : s16;
}

/// Corner radii: small (tags), card (cards / tiles), full (pills / buttons).
abstract final class MuseRadius {
  static const small = 8.0;
  static const card = 16.0;
  static const full = 999.0;

  static const smallAll = BorderRadius.all(Radius.circular(small));
  static const cardAll = BorderRadius.all(Radius.circular(card));
  static const fullAll = BorderRadius.all(Radius.circular(full));
}

/// 1.6.0 C1: layout breakpoints (dp) of the adaptive shell and the dashboard.
abstract final class MuseBreak {
  static const mobile = 600.0;
  static const laptop = 840.0;
  static const dashDesktop = 640.0;
  static const dashFour = 860.0;
  static const dashStandard = 1040.0;
  static const dashTall = 824.0;
  static const dashMobileMax = 560.0;
  static const dashColumnMax = 440.0;
  static const profileMin = 300.0;
  static const proxyColumn = 250.0;
}

/// 1.6.0 C1: the wider radius scale (xs..full); [card]/[small]/[full] above stay as they are.
abstract final class MuseRadiusScale {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 28.0;
  static const alert = 34.0;

  /// A radius that never exceeds half of the shortest side.
  static double fit(double shortestSide, double radius) =>
      radius > shortestSide / 2 ? shortestSide / 2 : radius;
}

/// 1.6.0 C1: text-scale aware spacing: [v] scaled by min(1 + (textScale − 1) × 0.5, 1).
double museAdaptiveSpace(BuildContext context, double v) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0);
  final k = 1 + (scale - 1) * 0.5;
  return v * (k > 1 ? 1.0 : k);
}

/// Motion: one duration and curve for fades / slides.
abstract final class MuseMotion {
  static const fast = Duration(milliseconds: 200);
  static const curve = Curves.easeOutCubic;

  /// 1.6.0 C1: FlClash-style durations
  static const mid = Duration(milliseconds: 200);
  static const common = Duration(milliseconds: 300);
  static const tab = Duration(milliseconds: 220);
  static const pressFeedback = Duration(milliseconds: 150);
  static const tabCurve = Curves.easeInOut;
  static const sheetDetents = [9 / 16, 0.9];

  /// 1.5.0: one half of a skeleton's pulse
  static const skeletonPulse = Duration(milliseconds: 900);
}

/// 1.5.0: whether the system asks for reduced motion (Android 「移除动画」, Windows 「动画效果」 off).
bool museReduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 1.5.0: [MuseMotion.fast], or no animation at all when the system asks for reduced motion.
Duration museMotion(BuildContext context) => museReduceMotion(context) ? Duration.zero : MuseMotion.fast;

/// Icon sizes (one rounded line-icon set).
abstract final class MuseIconSize {
  static const tiny = 16.0;
  static const small = 20.0;
  static const regular = 24.0;

  /// a flag emoji in its box
  static const flag = 18.0;
}

/// Fixed sizes of recurring layout parts (so screens never hand-write them).
abstract final class MuseSize {
  /// width of a key column in a details sheet («延迟», «测速时间»)
  static const labelColumn = 72.0;
  static const labelColumnWide = 96.0;

  /// the bottom element of a 首页 tile (sparkline, bar, caption)
  static const tileBottom = 20.0;

  /// room left under a list for a floating button
  static const fabClearance = 88.0;

  /// width of a message dialog's text
  static const dialogText = 468.0;

  /// the selected-row bar of a list
  static const selectedBar = 4.0;

  /// a status dot
  static const dot = 8.0;

  /// room around a full-screen loading indicator
  static const loadingInset = 64.0;

  static const hairline = 0.5;
  static const progressBar = 6.0;
  static const spinnerStroke = 2.0;

  /// node column on a wide 首页
  static const sideColumn = 380.0;

  /// right-aligned latency column of a node row
  static const latencyColumn = 64.0;

  /// flag / icon box in front of a row
  static const flagBox = 32.0;

  /// 1.6.0 C5: 节点 list layout keeps a readable column
  static const nodeListMax = 720.0;

  /// 1.5.3: a node row shows its protocol tag only while it takes at most this share of the name column
  static const protocolTagShare = 0.4;

  /// divider indent under a row with a flag box (16 + 32 + 12)
  static const rowIndent = 60.0;

  /// the hero card's big switch and its knob
  static const switchWidth = 64.0;
  static const switchHeight = 36.0;
  static const switchKnob = 28.0;

  /// the hero card's node row, a list row, a button
  static const heroRow = 56.0;
  static const button = 48.0;

  /// app icons in lists
  static const appIcon = 24.0;
  static const appIconLarge = 48.0;

  /// empty-state illustration
  static const emptyArt = 72.0;
  static const emptyIcon = 40.0;
  static const segmented = 32.0;

  /// 1.5.1: width of a three-segment control in a section header (统计 日 / 周 / 月)
  static const segmentedRange = 132.0;

  /// 1.4.0: 统计 chart height, gap between its bars, minimum bar, QR code
  static const chartHeight = 160.0;

  /// 1.6.0 #29: the delay mini line in a node's detail
  static const sparkHeight = 36.0;
  static const sparkStroke = 2.0;
  static const sparkDot = 2.5;
  static const barGap = 2.0;
  static const barMin = 4.0;
  static const qrCode = 240.0;

  /// 1.6.0 #40 / #34: the list inside 清除不可用 / 收藏排序 dialogs
  static const dialogList = 280.0;
  static const dialogWidth = 360.0;

  /// 隐私模式 blur strength
  static const privacyBlur = 6.0;

  /// 1.5.0: height of the bottom tab bar (toasts sit above it)
  static const tabBar = 64.0;

  /// 1.6.0 C1: toolbars, rows, sheets, title bar
  static const toolbar = 72.0;
  static const rowMin = 56.0;
  static const rowPadV = 10.0;
  static const sheetToolbar = 48.0;
  static const sheetAppBar = 68.0;
  static const titleBar = 32.0;
  static const captionButton = 46.0;
  static const pinIcon = 16.0;
  static const navRailCollapsed = 80.0;
  static const navSidebarExpanded = 220.0;
  static const dockHeight = 64.0;
  static const sheetHandle = 36.0;
  static const sheetHandleThickness = 4.0;
  static const menuWidth = 240.0;
  static const badge = 20.0;
}

/// 1.4.0: accent colours to pick from (one at a time; brand blue by default).
/// 1.6.0 C7: more presets, plus any custom colour stored as "#RRGGBB" in the same preference.
enum MuseAccent {
  blue('blue', '蓝', Color(0xFF2F6BFF), Color(0xFF5A8BFF), Color(0xFF1E4FD8)),
  green('green', '绿', Color(0xFF16A34A), Color(0xFF3DBE6C), Color(0xFF0F7A37)),
  purple('purple', '紫', Color(0xFF7C3AED), Color(0xFF9B67F2), Color(0xFF5B21B6)),
  teal('teal', '青', Color(0xFF0D9488), Color(0xFF2DB3A6), Color(0xFF0B6F66)),
  indigo('indigo', '靛', Color(0xFF4F46E5), Color(0xFF7069EE), Color(0xFF3730A3)),
  pink('pink', '粉', Color(0xFFDB2777), Color(0xFFE85497), Color(0xFFA31C59)),
  orange('orange', '橙', Color(0xFFD9480F), Color(0xFFE8703F), Color(0xFFA8370B));

  const MuseAccent(this.key, this.title, this.brand, this.light, this.deep);

  final String key;
  final String title;
  final Color brand;
  final Color light;
  final Color deep;

  static MuseAccent fromKey(String key) => values.where((e) => e.key == key).firstOrNull ?? blue;

  /// The preset for [key], or null when it is a custom colour / unknown.
  static MuseAccent? presetOrNull(String key) => values.where((e) => e.key == key).firstOrNull;
}

/// 1.6.0 C7: how many custom colours are kept.
const museMaxCustomAccents = 8;

/// White text on the accent needs at least this contrast (WCAG large text / UI parts).
const museAccentMinContrast = 3.0;

/// "#RRGGBB" / "RRGGBB" / "#RGB" (case-insensitive, spaces ignored) as an opaque colour; null if
/// it is not a colour.
Color? museParseHexColor(String input) {
  var s = input.trim().replaceAll(' ', '');
  if (s.startsWith('#')) s = s.substring(1);
  if (RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(s)) s = s.split('').map((c) => '$c$c').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(0xFF000000 | int.parse(s, radix: 16));
}

/// "#RRGGBB" (upper case) for [c].
String museHexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

double _contrastWithWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

/// brand / light / deep for a preference value: a preset key or a custom "#RRGGBB". A custom
/// colour too light for white text is darkened just enough to stay readable.
({Color brand, Color light, Color deep}) museAccentColors(String key) {
  final preset = MuseAccent.presetOrNull(key);
  if (preset != null) return (brand: preset.brand, light: preset.light, deep: preset.deep);
  final custom = museParseHexColor(key);
  if (custom == null) {
    const b = MuseAccent.blue;
    return (brand: b.brand, light: b.light, deep: b.deep);
  }
  var hsl = HSLColor.fromColor(custom);
  var guard = 0;
  while (_contrastWithWhite(hsl.toColor()) < museAccentMinContrast && hsl.lightness > 0.05 && guard++ < 40) {
    hsl = hsl.withLightness((hsl.lightness - 0.02).clamp(0.0, 1.0));
  }
  final brand = hsl.toColor();
  return (
    brand: brand,
    light: hsl.withLightness((hsl.lightness + 0.1).clamp(0.0, 0.9)).toColor(),
    deep: hsl.withLightness((hsl.lightness - 0.12).clamp(0.05, 1.0)).toColor(),
  );
}

/// Saved custom colours ("#RRGGBB,#RRGGBB"), valid ones only, no duplicates, newest first.
List<String> museParseCustomAccents(String raw) {
  final out = <String>[];
  for (final part in raw.split(',')) {
    final c = museParseHexColor(part);
    if (c == null) continue;
    final hex = museHexOf(c);
    if (!out.contains(hex)) out.add(hex);
    if (out.length >= museMaxCustomAccents) break;
  }
  return out;
}

/// [raw] with [hex] added at the front (kept to [museMaxCustomAccents]).
String museAddCustomAccent(String raw, String hex) {
  final c = museParseHexColor(hex);
  if (c == null) return museParseCustomAccents(raw).join(',');
  final h = museHexOf(c);
  return [h, ...museParseCustomAccents(raw).where((e) => e != h)].take(museMaxCustomAccents).join(',');
}

/// [raw] without [hex].
String museRemoveCustomAccent(String raw, String hex) =>
    museParseCustomAccents(raw).where((e) => e != hex.toUpperCase()).join(',');

/// Makes the accent stored as [key] (preset key or "#RRGGBB") the brand colour everywhere (call
/// before building the app).
void museApplyAccent(String key) {
  final c = museAccentColors(key);
  MusePalette.brand = c.brand;
  MusePalette.brandLight = c.light;
  MusePalette.brandDeep = c.deep;
}

/// 1.6.0 C7: 纯黑 (深色下的开关) — the dark page, cards and insets go to true black.
void museApplyPureBlack(bool on) => MusePalette.pureBlack = on;

/// Fixed palette. Brand blue only for primary actions and selected state; one value per status.
abstract final class MusePalette {
  // 1.4.0: the accent can be 蓝 (default) / 绿 / 紫 (设置 › 外观); set by museApplyAccent before
  // the app builds, and the app is rebuilt when it changes.
  static Color brand = MuseAccent.blue.brand;
  static Color brandLight = MuseAccent.blue.light;
  static Color brandDeep = MuseAccent.blue.deep;

  /// 1.6.0 C7: dark theme on true black (set by museApplyPureBlack before the app builds).
  static bool pureBlack = false;

  static const green = Color(0xFF22C55E);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const star = Color(0xFFFFB300);

  // light
  static const lightBgTop = Color(0xFFE2EAFC);
  static const lightBgBottom = Color(0xFFF6F8FC);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightText1 = Color(0xFF111827);
  static const lightText2 = Color(0xFF5B6472);
  static const lightText3 = Color(0xFF7C8494);
  static const lightHairline = Color(0xFFE5E7EB);
  static const lightSelected = Color(0xFFEAF1FF);
  static const lightInner = Color(0xFFF1F4F9);
  static const lightHeroIdle = Color(0xFFFFFFFF);
  static const lightShadow = Color(0x0F111827);
  static const knobShadow = Color(0x26000000);
  static const qrInk = Color(0xFF000000);

  // dark (night blue, never pure black)
  static const darkBgTop = Color(0xFF17223F);
  static const darkBgBottom = Color(0xFF0B1222);
  static const darkCard = Color(0xFF17213B);
  static const darkText1 = Color(0xFFE8ECF5);
  static const darkText2 = Color(0xFF94A0BC);
  static const darkText3 = Color(0xFF7A85A0);
  static const darkHairline = Color(0x14FFFFFF);
  static const darkSelected = Color(0xFF1D3166);
  static const darkInner = Color(0xFF1F2B4A);
  static const darkBorder = Color(0x1AFFFFFF);
  static const darkHeroTop = Color(0xFF2B57D9);
  static const darkHeroBottom = Color(0xFF17368F);
  static const darkHeroIdle = Color(0xFF1C2847);

  // 1.6.0 C7: 纯黑 (dark only)
  static const blackBg = Color(0xFF000000);
  static const blackCard = Color(0xFF111318);
  static const blackInner = Color(0xFF1A1D24);
  static const blackSelected = Color(0xFF162447);
  static const blackHeroIdle = Color(0xFF14171D);

  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const transparent = Color(0x00000000);
}

/// 1.5.0: every toast — one place (bottom centre, above the tab bar) and one colour per kind.
abstract final class MuseToast {
  static const margin = EdgeInsets.only(bottom: MuseSize.tabBar + MuseSpace.s16, right: MuseSpace.s16, left: MuseSpace.s16);
  static const alignment = AlignmentDirectional.bottomCenter;
  static const error = MusePalette.red;
  static const success = MusePalette.green;
  static Color get info => MusePalette.brand;
}

/// The palette resolved for the current brightness.
@immutable
class MuseTheme {
  const MuseTheme._(this.dark);

  factory MuseTheme.of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static const _light = MuseTheme._(false);
  static const _dark = MuseTheme._(true);

  final bool dark;

  bool get _black => dark && MusePalette.pureBlack;

  Color get card => _black ? MusePalette.blackCard : (dark ? MusePalette.darkCard : MusePalette.lightCard);
  Color get text1 => dark ? MusePalette.darkText1 : MusePalette.lightText1;
  Color get text2 => dark ? MusePalette.darkText2 : MusePalette.lightText2;
  Color get text3 => dark ? MusePalette.darkText3 : MusePalette.lightText3;
  Color get hairline => dark ? MusePalette.darkHairline : MusePalette.lightHairline;
  Color get selected => _black ? MusePalette.blackSelected : (dark ? MusePalette.darkSelected : MusePalette.lightSelected);
  Color get inner => _black ? MusePalette.blackInner : (dark ? MusePalette.darkInner : MusePalette.lightInner);
  Color get bgTop => _black ? MusePalette.blackBg : (dark ? MusePalette.darkBgTop : MusePalette.lightBgTop);
  Color get bgBottom => _black ? MusePalette.blackBg : (dark ? MusePalette.darkBgBottom : MusePalette.lightBgBottom);
  Color get heroIdle => _black ? MusePalette.blackHeroIdle : (dark ? MusePalette.darkHeroIdle : MusePalette.lightHeroIdle);

  /// The connected hero card.
  LinearGradient get heroGradient => dark
      ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: MusePalette.brand == MuseAccent.blue.brand
              ? const [MusePalette.darkHeroTop, MusePalette.darkHeroBottom]
              : [
                  Color.lerp(MusePalette.brand, MusePalette.black, 0.12)!,
                  Color.lerp(MusePalette.brandDeep, MusePalette.black, 0.38)!,
                ],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MusePalette.brandLight, MusePalette.brand],
        );

  LinearGradient get pageGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
    stops: const [0, 0.6],
  );

  /// White tile with a very light shadow (light) / faint border without shadow (dark): never both.
  BoxDecoration cardDecoration({Color? color, BorderRadius radius = MuseRadius.cardAll}) => BoxDecoration(
    color: color ?? card,
    borderRadius: radius,
    border: dark ? Border.all(color: MusePalette.darkBorder) : null,
    boxShadow: dark ? null : const [BoxShadow(color: MusePalette.lightShadow, blurRadius: 12, offset: Offset(0, 2))],
  );

  /// ShapeBorder for Material cards (dark: faint border).
  ShapeBorder cardShape({BorderRadius radius = MuseRadius.cardAll}) => RoundedRectangleBorder(
    borderRadius: radius,
    side: dark ? const BorderSide(color: MusePalette.darkBorder) : BorderSide.none,
  );

  double get cardElevation => dark ? 0 : 1.5;
  Color get shadowColor => dark ? MusePalette.transparent : MusePalette.lightShadow;
}

/// Four text levels. Numbers use tabular figures.
abstract final class MuseType {
  static const tabular = [FontFeature.tabularFigures()];

  /// size of the big tile number ([number])
  static const numberSize = 24.0;

  static TextStyle largeTitle(BuildContext context) =>
      TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, color: MuseTheme.of(context).text1, letterSpacing: 0.5);

  static TextStyle title(BuildContext context) =>
      TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w600, color: MuseTheme.of(context).text1, fontFeatures: tabular);

  /// 1.4.0: the big number on a 首页 tile (one weight for every value, digits tabular).
  static TextStyle number(BuildContext context) => TextStyle(
    fontSize: numberSize,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: MuseTheme.of(context).text1,
    fontFeatures: tabular,
  );

  static TextStyle body(BuildContext context) =>
      TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w400, color: MuseTheme.of(context).text1);

  static TextStyle caption(BuildContext context) =>
      TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w400, color: MuseTheme.of(context).text2, fontFeatures: tabular);
}

/// 1.6.0 C1: the full type ladder (size / line height in dp). The four 1.4.0 styles above stay
/// as they are until each page moves to these names.
enum MuseTextLevel {
  display(40, 44, FontWeight.w700),
  largeTitle(34, 41, FontWeight.w700),
  title1(28, 34, FontWeight.w700),
  pageTitle(24, 30, FontWeight.w700),
  title2(22, 28, FontWeight.w600),
  title3(20, 25, FontWeight.w600),
  headline(17, 22, FontWeight.w600),
  body(17, 22, FontWeight.w400),
  callout(16, 21, FontWeight.w400),
  subheadline(15, 20, FontWeight.w400),
  footnote(13, 18, FontWeight.w400),
  caption1(12, 16, FontWeight.w400),
  caption2(11, 13, FontWeight.w400);

  const MuseTextLevel(this.size, this.lineHeight, this.weight);

  final double size;
  final double lineHeight;
  final FontWeight weight;

  /// The style in [color] (defaults to the theme's onSurface); digits are always tabular.
  TextStyle style(BuildContext context, {Color? color, FontWeight? weight}) => TextStyle(
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight ?? this.weight,
    color: color ?? Theme.of(context).colorScheme.onSurface,
    fontFeatures: MuseType.tabular,
  );
}

/// The page background. 1.6.0: one flat page surface (structure by fill; the gradient and the
/// clouds are gone). Nested backgrounds paint nothing.
class MuseBackground extends StatelessWidget {
  const MuseBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.dependOnInheritedWidgetOfExactType<_MuseBackgroundScope>() != null) return child;
    return ColoredBox(
      key: const ValueKey('muse_background'),
      color: MuseTheme.of(context).bgBottom,
      child: _MuseBackgroundScope(child: child),
    );
  }
}

class _MuseBackgroundScope extends InheritedWidget {
  const _MuseBackgroundScope({required super.child});

  @override
  bool updateShouldNotify(_MuseBackgroundScope oldWidget) => false;
}
