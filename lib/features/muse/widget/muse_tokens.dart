// 穿云 1.3.0 - design tokens: the one place for spacing, radii, type, colours, motion and the
// page background. Screens use these names instead of hand-written numbers / hex literals.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';

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

  /// 1.6.1: the glyph on the 首页 start button
  static const large = 32.0;

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

  /// 1.6.1: height of the selected-row mark
  static const selectedMark = 24.0;

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

  /// 1.6.1: the 首页 start button (a squircle; round while disconnected)
  static const startButton = 64.0;

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

  /// 1.6.1: the Material 3 bottom navigation bar
  static const navBarHeight = 80.0;
  static const navIndicatorWidth = 64.0;
  static const navIndicatorHeight = 32.0;
  static const sheetHandle = 36.0;
  static const sheetHandleThickness = 4.0;
  static const menuWidth = 240.0;
  static const badge = 20.0;
}

/// 1.4.0: accent colours to pick from (one at a time). 1.6.0 C7: plus any custom colour stored
/// as "#RRGGBB" in the same preference. 1.6.2: ten Chinese traditional colours, 景泰蓝 by default.
/// [color] is the colour itself (the swatch and the seed of the colour scheme); [brand] / [light]
/// / [deep] are derived from it and keep white text readable (see [museAccentColors]).
enum MuseAccent {
  jingtailan('jingtailan', '景泰蓝', Color(0xFF2775B6)),
  pielan('pielan', '苤蓝', Color(0xFF6B798E)),
  zhuqing('zhuqing', '竹青', Color(0xFF789262)),
  yuebai('yuebai', '月白', Color(0xFFD6ECF0)),
  cangyinghui('cangyinghui', '苍蝇灰', Color(0xFF36282B)),
  zhujin('zhujin', '朱瑾', Color(0xFFC41E3A)),
  tenghuang('tenghuang', '藤黄', Color(0xFFFFB61E)),
  qingbi('qingbi', '青碧', Color(0xFF48C0A3)),
  dingxiang('dingxiang', '丁香', Color(0xFFCCA4E3)),
  zheshi('zheshi', '赭石', Color(0xFF845A33));

  const MuseAccent(this.key, this.title, this.color);

  final String key;
  final String title;
  final Color color;

  Color get brand => museAccentColors(key).brand;
  Color get light => museAccentColors(key).light;
  Color get deep => museAccentColors(key).deep;

  /// The default (景泰蓝).
  static const fallback = jingtailan;

  /// 1.6.2: keys saved by 1.4.0–1.6.1 (and still synced from an older device) → the new preset.
  static const legacy = <String, MuseAccent>{
    'blue': jingtailan,
    'green': zhuqing,
    'teal': qingbi,
    'purple': dingxiang,
    'indigo': pielan,
    'pink': zhujin,
    'orange': tenghuang,
  };

  static MuseAccent fromKey(String key) => presetOrNull(key) ?? fallback;

  /// The preset for [key] (a current or a 1.6.1-and-earlier key), or null when it is a custom
  /// colour / unknown.
  static MuseAccent? presetOrNull(String key) => values.where((e) => e.key == key).firstOrNull ?? legacy[key];
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

/// 1.6.2: text / icons drawn straight on [c] (a swatch, a filled chip): white while it stays
/// readable (≥ [museAccentMinContrast]), otherwise near-black ink.
Color museOnColor(Color c) => _contrastWithWhite(c) >= museAccentMinContrast ? MusePalette.white : MusePalette.ink;

typedef MuseAccentColors = ({Color seed, Color brand, Color light, Color deep});

final _accentCache = <String, MuseAccentColors>{};

/// seed / brand / light / deep for a preference value: a preset key (old 1.6.1 keys map to the
/// new presets) or a custom "#RRGGBB"; anything else is 景泰蓝. [seed] is the colour itself (the
/// colour scheme is derived from it); [brand] is darkened just enough for white text, so light
/// colours such as 月白 / 藤黄 / 丁香 stay readable. Computed once per value and cached.
MuseAccentColors museAccentColors(String key) {
  final hit = _accentCache[key];
  if (hit != null) return hit;
  final seed = MuseAccent.presetOrNull(key)?.color ?? museParseHexColor(key) ?? MuseAccent.fallback.color;
  var hsl = HSLColor.fromColor(seed);
  var guard = 0;
  while (_contrastWithWhite(hsl.toColor()) < museAccentMinContrast && hsl.lightness > 0.05 && guard++ < 50) {
    hsl = hsl.withLightness((hsl.lightness - 0.02).clamp(0.0, 1.0));
  }
  final brand = hsl.lightness == HSLColor.fromColor(seed).lightness ? seed : hsl.toColor();
  final out = (
    seed: seed,
    brand: brand,
    light: hsl.withLightness((hsl.lightness + 0.1).clamp(0.0, 0.9)).toColor(),
    deep: hsl.withLightness((hsl.lightness - 0.12).clamp(0.05, 1.0)).toColor(),
  );
  if (_accentCache.length > 32) _accentCache.clear();
  return _accentCache[key] = out;
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
  MusePalette.seed = c.seed;
  MusePalette.brand = c.brand;
  MusePalette.brandLight = c.light;
  MusePalette.brandDeep = c.deep;
}

/// 1.6.0 C7: 纯黑 (深色下的开关) — the dark page, cards and insets go to true black.
void museApplyPureBlack(bool on) => MusePalette.pureBlack = on;

/// 1.6.1: 配色风格 (a MuseColorStyle key) used to derive the app's Material 3 colour scheme.
void museApplyColorStyle(String key) => MusePalette.colorStyle = key;

/// 1.6.1: the accent (primary) of the current colour scheme — what screens paint selected
/// state and primary actions with. [MusePalette.brand] is only the seed it is derived from.
Color museBrandOf(BuildContext context) => Theme.of(context).colorScheme.primary;

/// Fixed palette. Brand blue only for primary actions and selected state; one value per status.
abstract final class MusePalette {
  // 1.4.0: the accent picked in 设置 › 外观 (1.6.2: 景泰蓝 by default); set by museApplyAccent
  // before the app builds, and the app is rebuilt when it changes.
  /// 1.6.2: the accent colour itself — the seed of the Material 3 colour scheme.
  static Color seed = MuseAccent.fallback.color;
  static Color brand = MuseAccent.fallback.brand;
  static Color brandLight = MuseAccent.fallback.light;
  static Color brandDeep = MuseAccent.fallback.deep;

  /// 1.6.0 C7: dark theme on true black (set by museApplyPureBlack before the app builds).
  static bool pureBlack = false;

  /// 1.6.1: 配色风格 key (set by museApplyColorStyle before the app builds).
  static String colorStyle = 'tonalSpot';

  // 1.6.2: status lights in Chinese traditional colours (never follow 主题色):
  // 葱青 ok / 杏黄 warning / 朱砂 error / 墨灰 idle (未测试、未连接)
  static const green = museStatusGreen;
  static const orange = museStatusYellow;
  static const red = museStatusRed;
  static const grey = museStatusGrey;
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

  /// 1.6.2: text on a light accent swatch (月白 / 藤黄 / 丁香)
  static const ink = Color(0xFF1B1B1F);
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

/// The palette resolved for the current theme. 1.6.1: every colour comes from the app's
/// Material 3 colour scheme (seeded by 主题色, see museSeededScheme) — flat filled surfaces,
/// no card shadows, no borders and no gradients.
@immutable
class MuseTheme {
  const MuseTheme._(this.scheme);

  factory MuseTheme.of(BuildContext context) => MuseTheme._(Theme.of(context).colorScheme);

  final ColorScheme scheme;

  bool get dark => scheme.brightness == Brightness.dark;

  Color get card => MuseSurface.card.color(scheme);
  Color get text1 => scheme.onSurface;
  Color get text2 => scheme.onSurfaceVariant;
  Color get text3 => scheme.outline;
  Color get hairline => scheme.outlineVariant;
  Color get selected => scheme.secondaryContainer;
  Color get inner => MuseSurface.block.color(scheme);
  Color get bgTop => MuseSurface.page.color(scheme);
  Color get bgBottom => MuseSurface.page.color(scheme);
  Color get heroIdle => card;

  /// The connected hero card: a flat primary-container fill (kept as a one-colour gradient so
  /// callers that animate between states keep working).
  LinearGradient get heroGradient => LinearGradient(colors: [scheme.primaryContainer, scheme.primaryContainer]);

  /// Text / icons on the connected hero card.
  Color get onHero => scheme.onPrimaryContainer;

  LinearGradient get pageGradient => LinearGradient(colors: [bgBottom, bgBottom]);

  /// A filled card: no shadow and no border in either brightness.
  BoxDecoration cardDecoration({Color? color, BorderRadius radius = MuseRadius.cardAll}) =>
      BoxDecoration(color: color ?? card, borderRadius: radius);

  /// ShapeBorder for Material cards (no border).
  ShapeBorder cardShape({BorderRadius radius = MuseRadius.cardAll}) => RoundedSuperellipseBorder(borderRadius: radius);

  double get cardElevation => 0;
  Color get shadowColor => MusePalette.transparent;
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
