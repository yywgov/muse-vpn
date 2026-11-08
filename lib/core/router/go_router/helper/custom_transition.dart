import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';
import 'package:hiddify/utils/utils.dart';

enum TransitionType { slide, fade }

/// 穿云 1.18.0 P0: page transitions had no curve (linear, 150 / 100 ms). Now: enter 380 ms on the
/// main curve, back 200 ms accelerating out; 精简 = a short fade only, 关闭 = no animation.
Page<dynamic> customTransition(TransitionType transition, LocalKey pageKey, Widget child) {
  // On iOS, use CupertinoPage so pages get the native interactive (edge-swipe)
  // back gesture. CustomTransitionPage does not support that gesture.
  if (PlatformUtils.isIOS) {
    return CupertinoPage<dynamic>(key: pageKey, child: child);
  }
  return CustomTransitionPage<dynamic>(
    key: pageKey,
    child: child,
    transitionDuration: MuseMotion.enter,
    reverseTransitionDuration: MuseMotion.exit,
    transitionsBuilder: (context, animation, _, child) => museTransition(transition, museMotionLevel(context), animation, child, Directionality.of(context)),
  );
}

/// The transition for [level] (kept separate so tests can check each level).
Widget museTransition(TransitionType transition, MuseMotionLevel level, Animation<double> animation, Widget child, TextDirection dir) {
  if (level == MuseMotionLevel.off) return child;
  if (level == MuseMotionLevel.reduced) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.6, curve: MuseMotion.plainCurve)),
      child: child,
    );
  }
  final curved = museTransitionCurve(animation);
  return switch (transition) {
    TransitionType.slide => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
      textDirection: dir,
      child: child,
    ),
    TransitionType.fade => FadeTransition(opacity: curved, child: child),
  };
}

/// enter on [MuseMotion.curve]; going back accelerates out ([MuseMotion.exitCurve], flipped because
/// the animation runs 1 → 0).
CurvedAnimation museTransitionCurve(Animation<double> animation) =>
    CurvedAnimation(parent: animation, curve: MuseMotion.curve, reverseCurve: MuseMotion.exitCurve.flipped);
