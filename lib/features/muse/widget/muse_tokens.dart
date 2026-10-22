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

/// Motion: one duration and curve for fades / slides.
abstract final class MuseMotion {
  static const fast = Duration(milliseconds: 200);
  static const curve = Curves.easeOutCubic;
}

/// Icon sizes (one rounded line-icon set).
abstract final class MuseIconSize {
  static const small = 20.0;
  static const regular = 24.0;
}

/// Fixed palette. Brand blue only for primary actions and selected state; one value per status.
abstract final class MusePalette {
  static const brand = Color(0xFF2F6BFF);
  static const brandLight = Color(0xFF5A8BFF);
  static const brandDeep = Color(0xFF1E4FD8);

  static const green = Color(0xFF22C55E);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const star = Color(0xFFFFB300);

  // light
  static const lightBgTop = Color(0xFFE2EAFC);
  static const lightBgBottom = Color(0xFFF6F8FC);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightText1 = Color(0xFF111827);
  static const lightText2 = Color(0xFF6B7280);
  static const lightText3 = Color(0xFF9CA3AF);
  static const lightHairline = Color(0xFFE5E7EB);
  static const lightSelected = Color(0xFFEAF1FF);
  static const lightInner = Color(0xFFF1F4F9);
  static const lightHeroIdle = Color(0xFFFFFFFF);
  static const lightShadow = Color(0x0F111827);
  static const knobShadow = Color(0x26000000);

  // dark (night blue, never pure black)
  static const darkBgTop = Color(0xFF17223F);
  static const darkBgBottom = Color(0xFF0B1222);
  static const darkCard = Color(0xFF17213B);
  static const darkText1 = Color(0xFFE8ECF5);
  static const darkText2 = Color(0xFF94A0BC);
  static const darkText3 = Color(0xFF66728F);
  static const darkHairline = Color(0x14FFFFFF);
  static const darkSelected = Color(0xFF1D3166);
  static const darkInner = Color(0xFF1F2B4A);
  static const darkBorder = Color(0x1AFFFFFF);
  static const darkHeroTop = Color(0xFF2B57D9);
  static const darkHeroBottom = Color(0xFF17368F);
  static const darkHeroIdle = Color(0xFF1C2847);

  static const white = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000);
}

/// The palette resolved for the current brightness.
@immutable
class MuseTheme {
  const MuseTheme._(this.dark);

  factory MuseTheme.of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static const _light = MuseTheme._(false);
  static const _dark = MuseTheme._(true);

  final bool dark;

  Color get card => dark ? MusePalette.darkCard : MusePalette.lightCard;
  Color get text1 => dark ? MusePalette.darkText1 : MusePalette.lightText1;
  Color get text2 => dark ? MusePalette.darkText2 : MusePalette.lightText2;
  Color get text3 => dark ? MusePalette.darkText3 : MusePalette.lightText3;
  Color get hairline => dark ? MusePalette.darkHairline : MusePalette.lightHairline;
  Color get selected => dark ? MusePalette.darkSelected : MusePalette.lightSelected;
  Color get inner => dark ? MusePalette.darkInner : MusePalette.lightInner;
  Color get bgTop => dark ? MusePalette.darkBgTop : MusePalette.lightBgTop;
  Color get bgBottom => dark ? MusePalette.darkBgBottom : MusePalette.lightBgBottom;
  Color get heroIdle => dark ? MusePalette.darkHeroIdle : MusePalette.lightHeroIdle;

  /// The connected hero card.
  LinearGradient get heroGradient => dark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MusePalette.darkHeroTop, MusePalette.darkHeroBottom],
        )
      : const LinearGradient(
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

  static TextStyle largeTitle(BuildContext context) =>
      TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, color: MuseTheme.of(context).text1, letterSpacing: 0.5);

  static TextStyle title(BuildContext context) =>
      TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w600, color: MuseTheme.of(context).text1, fontFeatures: tabular);

  static TextStyle body(BuildContext context) =>
      TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w400, color: MuseTheme.of(context).text1);

  static TextStyle caption(BuildContext context) =>
      TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w400, color: MuseTheme.of(context).text2, fontFeatures: tabular);
}

/// The page background: night-blue / blue-grey gradient with a few faint clouds. Painted once and
/// cached (RepaintBoundary + static painter), so scrolling never repaints it.
class MuseBackground extends StatelessWidget {
  const MuseBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // already painted further up (the desktop shell paints one background behind every page)
    if (context.dependOnInheritedWidgetOfExactType<_MuseBackgroundScope>() != null) return child;
    final theme = MuseTheme.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              key: const ValueKey('muse_background'),
              isComplex: true,
              painter: MuseCloudPainter(dark: theme.dark, top: theme.bgTop, bottom: theme.bgBottom),
            ),
          ),
        ),
        _MuseBackgroundScope(child: child),
      ],
    );
  }
}

class _MuseBackgroundScope extends InheritedWidget {
  const _MuseBackgroundScope({required super.child});

  @override
  bool updateShouldNotify(_MuseBackgroundScope oldWidget) => false;
}

class MuseCloudPainter extends CustomPainter {
  const MuseCloudPainter({required this.dark, required this.top, required this.bottom});

  final bool dark;
  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
          stops: const [0, 0.6],
        ).createShader(rect),
    );
    final alpha = dark ? 0.035 : 0.6;
    final paint = Paint()
      ..color = MusePalette.white.withValues(alpha: alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    // cloud size follows the width, capped so a wide window doesn't get huge blobs
    final unit = size.width.clamp(280.0, 520.0) / 10;
    _cloud(canvas, Offset(size.width - unit * 1.6, unit * 1.2), unit * 1.15, paint);
    _cloud(canvas, Offset(unit * 0.4, size.height * 0.48), unit * 0.85, paint);
    _cloud(canvas, Offset(unit * 2.2, size.height - unit * 0.6), unit * 1.0, paint);
  }

  /// A cloud: a flat base with three puffs on top.
  static void _cloud(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: r * 4.2, height: r * 1.3), Radius.circular(r * 0.65)))
      ..addOval(Rect.fromCircle(center: c.translate(-r * 1.0, -r * 0.45), radius: r * 0.8))
      ..addOval(Rect.fromCircle(center: c.translate(r * 0.15, -r * 0.8), radius: r * 1.05))
      ..addOval(Rect.fromCircle(center: c.translate(r * 1.2, -r * 0.35), radius: r * 0.7));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MuseCloudPainter old) => old.dark != dark || old.top != top || old.bottom != bottom;
}
