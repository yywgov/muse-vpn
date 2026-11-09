// 穿云 1.19.0 P5 切换主题时的圆形揭开：切换前把当前画面截成一张图盖在上面，新主题在下面画好后，
// 从点按位置开一个圆洞向外扩散（标准档 400ms），露出新主题；精简档改为旧画面淡出；关闭档不截图、直接切换。
// 一次性：动画结束即释放截图和控制器，不再调度帧。
// Part of 穿云 (GPLv3).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_theme.dart';

class MuseThemeReveal extends StatefulWidget {
  const MuseThemeReveal({super.key, required this.child});

  final Widget child;

  static MuseThemeRevealState? maybeOf(BuildContext context) => context.findAncestorStateOfType<MuseThemeRevealState>();

  /// 切换主题：先按动效档位截图（关闭档不截），再执行 [change]，然后播放一次揭开。
  /// [center] 为点按位置（全局坐标），没有时从画面中心开始。
  static Future<void> run(BuildContext context, Offset? center, Future<void> Function() change) async {
    final state = maybeOf(context);
    final level = museMotionLevel(context);
    final started = state != null && level != MuseMotionLevel.off && state.capture(center, level);
    await change();
    if (started) state.play();
  }

  @override
  State<MuseThemeReveal> createState() => MuseThemeRevealState();
}

class MuseThemeRevealState extends State<MuseThemeReveal> with TickerProviderStateMixin {
  final _boundary = GlobalKey();
  ui.Image? _old;
  Offset? _center;
  var _fade = false;
  AnimationController? _controller;

  /// 测试用：揭开是否正在进行
  bool get revealing => _old != null;

  /// 截下当前画面；失败（还没画过等）返回 false，就直接切换。
  bool capture(Offset? center, MuseMotionLevel level) {
    final ro = _boundary.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.hasSize) return false;
    ui.Image image;
    try {
      image = ro.toImageSync(pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);
    } catch (_) {
      return false;
    }
    _finish();
    final box = ro.size;
    final local = center == null ? null : ro.globalToLocal(center);
    setState(() {
      _old = image;
      _center = local ?? box.center(Offset.zero);
      _fade = level == MuseMotionLevel.reduced;
    });
    return true;
  }

  void play() {
    if (_old == null || !mounted) return;
    final c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _fade ? museThemeFadeMs : museThemeRevealMs),
    );
    _controller = c;
    c.addListener(() => setState(() {}));
    c.forward().whenCompleteOrCancel(() {
      if (mounted && _controller == c) setState(_finish);
    });
  }

  void _finish() {
    _controller?.dispose();
    _controller = null;
    _old?.dispose();
    _old = null;
  }

  @override
  void dispose() {
    _finish();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (old != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('theme_reveal_overlay'),
                painter: MuseRevealPainter(old, _center ?? Offset.zero, _controller?.value ?? 0, fade: _fade),
              ),
            ),
          ),
      ],
    );
  }
}

/// 旧画面：标准档挖掉半径随 [t] 增大的圆；精简档按 1 - [t] 淡出。
class MuseRevealPainter extends CustomPainter {
  MuseRevealPainter(this.image, this.center, this.t, {this.fade = false});

  final ui.Image image;
  final Offset center;
  final double t;
  final bool fade;

  /// 圆要盖住整个画面所需的半径（到最远角的距离）。
  static double maxRadius(Size size, Offset c) => [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ].map((p) => (p - c).distance).reduce(math.max);

  /// 进度 [t] 时圆洞的半径。1.19.1：快起曲线 [MuseMotion.curve]（原 easeInOutCubic 前 ~80ms 几乎看不见圆洞）。
  static double radiusAt(Size size, Offset c, double t) => maxRadius(size, c) * MuseMotion.curve.transform(t.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.low;
    if (fade) {
      paint.color = paint.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.drawImageRect(image, src, rect, paint);
      return;
    }
    final r = radiusAt(size, center, t);
    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.difference, Path()..addRect(rect), Path()..addOval(Rect.fromCircle(center: center, radius: r))),
    );
    canvas.drawImageRect(image, src, rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MuseRevealPainter old) => old.t != t || old.image != image || old.center != center || old.fade != fade;
}
