// 穿云 1.6.0 C1 - shape tokens: every corner is a continuous-curvature superellipse.
// Design rules adapted from GPL-3.0 code, Copyright (C) chen08209 (see THIRD_PARTY_NOTICES.md).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

/// Superellipse shapes for cards, sheets, buttons and pills. Screens use these instead of
/// RoundedRectangleBorder / StadiumBorder / ClipRRect (enforced by tokens_lint_test).
abstract final class MuseShape {
  static const cardRadius = MuseRadius.cardAll;

  static BorderRadius all(double r) => BorderRadius.all(Radius.circular(r));

  static BorderRadius top(double r) => BorderRadius.vertical(top: Radius.circular(r));

  static BorderRadius bottom(double r) => BorderRadius.vertical(bottom: Radius.circular(r));

  static RoundedSuperellipseBorder of(double r, {BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(borderRadius: all(r), side: side);

  static RoundedSuperellipseBorder radius(BorderRadius r, {BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(borderRadius: r, side: side);

  static final xs = of(MuseRadiusScale.xs);
  static final sm = of(MuseRadiusScale.sm);
  static final md = of(MuseRadiusScale.md);
  static final lg = of(MuseRadiusScale.lg);
  static final xl = of(MuseRadiusScale.xl);
  static final xxl = of(MuseRadiusScale.xxl);
  static final alert = of(MuseRadiusScale.alert);

  /// pills and round buttons (replaces StadiumBorder)
  static final full = of(MuseRadius.full);

  /// the standard card
  static final card = of(MuseRadius.card);

  /// a sheet's top corners
  static final sheet = radius(top(MuseRadiusScale.xxl));

  /// The corner a box of [size] gets: one step of the scale that is at most a third of its
  /// shortest side (so small chips never turn into blobs).
  static double fit(Size size) {
    final limit = size.shortestSide / 3;
    for (final r in const [
      MuseRadiusScale.xxl,
      MuseRadiusScale.xl,
      MuseRadiusScale.lg,
      MuseRadiusScale.md,
      MuseRadiusScale.sm,
      MuseRadiusScale.xs,
    ]) {
      if (limit >= r) return r;
    }
    return 0;
  }

  /// A filled box with a superellipse outline (no shadow: list cards never cast one).
  static ShapeDecoration fill(Color color, {double r = MuseRadius.card, BorderSide side = BorderSide.none}) =>
      ShapeDecoration(color: color, shape: of(r, side: side));
}

/// Clips its child to a superellipse (replaces ClipRRect).
class MuseClip extends StatelessWidget {
  const MuseClip({super.key, this.radius = MuseShape.cardRadius, required this.child});

  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(borderRadius: radius, child: child);
}
