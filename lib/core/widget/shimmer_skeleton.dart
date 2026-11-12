// 穿云 1.21.0 M12：扫光骨架不再无限循环——加载超过 300ms 才出现（快的加载不闪），
// 标准档最多扫 2 趟后静止；精简档 / 关闭档是静态骨架。出现前占同样大小的空位，不跳动。
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/widget/skeleton_widget.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';

class ShimmerSkeleton extends HookWidget {
  const ShimmerSkeleton({
    this.width,
    this.height,
    this.widthFactor,
    this.heightFactor,
    this.color,
    this.duration = const Duration(seconds: 1),
    super.key,
  });

  /// 加载短于它就不出现骨架。
  static const showDelay = Duration(milliseconds: 300);

  /// 标准档最多扫几趟。
  static const maxPasses = 2;

  final double? width;
  final double? height;
  final double? widthFactor;
  final double? heightFactor;
  final Color? color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final visible = useState(false);
    useEffect(() {
      final timer = Timer(showDelay, () => visible.value = true);
      return timer.cancel;
    }, const []);
    final skeleton = Skeleton(width: width, height: height, widthFactor: widthFactor, heightFactor: heightFactor);
    if (!visible.value) return Opacity(opacity: 0, child: skeleton);
    if (!museMotionRich(context)) return skeleton;
    return skeleton
        .animate(onPlay: (controller) => controller.repeat(count: maxPasses))
        .shimmer(duration: duration, angle: 45, color: color ?? Theme.of(context).colorScheme.secondary);
  }
}
