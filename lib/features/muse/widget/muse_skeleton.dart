// 穿云 1.5.0 - skeleton placeholders: the shape of what is loading (cards, rows) in a soft pulse,
// instead of a spinner in an empty page. Still when the system asks for reduced motion.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

/// Pulses its [child] (a group of [MuseSkeletonBox]es) between two opacities.
class MuseSkeleton extends HookWidget {
  const MuseSkeleton({super.key, required this.child});

  final Widget child;

  /// [rows] list rows (a flag box + two lines), as in a node / subscription list.
  factory MuseSkeleton.rows({Key? key, int rows = 6}) => MuseSkeleton(
    key: key ?? const ValueKey('muse_skeleton'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16, vertical: MuseSpace.s12),
            child: Row(
              children: [
                const MuseSkeletonBox(width: MuseSize.flagBox, height: MuseSize.flagBox),
                const SizedBox(width: MuseSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.55, child: const MuseSkeletonBox(height: MuseSpace.s12)),
                      const SizedBox(height: MuseSpace.s8),
                      const FractionallySizedBox(widthFactor: 0.35, child: MuseSkeletonBox(height: MuseSpace.s8)),
                    ],
                  ),
                ),
                const SizedBox(width: MuseSpace.s12),
                const MuseSkeletonBox(width: MuseSize.latencyColumn * 0.6, height: MuseSpace.s12),
              ],
            ),
          ),
      ],
    ),
  );

  /// 首页 while the subscriptions are read: the hero card and four tiles.
  factory MuseSkeleton.dashboard({Key? key}) => MuseSkeleton(
    key: key ?? const ValueKey('home_skeleton'),
    child: const Column(
      children: [
        MuseSkeletonBox(height: MuseSize.heroRow * 2.4, radius: MuseRadius.cardAll, card: true),
        SizedBox(height: MuseSpace.s12),
        Row(
          children: [
            Expanded(child: MuseSkeletonBox(height: MuseSize.heroRow * 2, radius: MuseRadius.cardAll, card: true)),
            SizedBox(width: MuseSpace.s12),
            Expanded(child: MuseSkeletonBox(height: MuseSize.heroRow * 2, radius: MuseRadius.cardAll, card: true)),
          ],
        ),
        SizedBox(height: MuseSpace.s12),
        Row(
          children: [
            Expanded(child: MuseSkeletonBox(height: MuseSize.heroRow * 2, radius: MuseRadius.cardAll, card: true)),
            SizedBox(width: MuseSpace.s12),
            Expanded(child: MuseSkeletonBox(height: MuseSize.heroRow * 2, radius: MuseRadius.cardAll, card: true)),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final reduce = museReduceMotion(context);
    final c = useAnimationController(duration: MuseMotion.skeletonPulse);
    useEffect(() {
      if (reduce) {
        c.value = 1;
      } else {
        c.repeat(reverse: true);
      }
      return null;
    }, [reduce]);
    return Semantics(
      label: '加载中',
      child: ExcludeSemantics(
        child: FadeTransition(opacity: Tween(begin: 0.45, end: 1.0).animate(c), child: child),
      ),
    );
  }
}

/// One grey rounded block of a skeleton.
class MuseSkeletonBox extends StatelessWidget {
  const MuseSkeletonBox({super.key, this.width, required this.height, this.radius = MuseRadius.smallAll, this.card = false});

  final double? width;
  final double height;
  final BorderRadius radius;

  /// a whole card's outline (card colour + the card's shadow / border) instead of a grey bar
  final bool card;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: card ? mt.cardDecoration(radius: radius) : BoxDecoration(color: mt.inner, borderRadius: radius),
    );
  }
}
