// 穿云 1.18.0 P3 - 数字 / 名称遮罩滚动（MuseRoll）与等待态扫光（MuseSweep）。
// 都只用 paint 阶段属性；MuseRoll 一次性（510ms），MuseSweep 只在标准档、等待态可见时运行并有超时。
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';

/// Rolls [child] when [value] changes: the old content slides up out of a mask in 260 ms, the new
/// one slides in after 90 ms over 420 ms. 精简 / 关闭 replace at once. For low-frequency values only
/// (延迟, 节点名) — never for per-second numbers such as 实时速率.
class MuseRoll extends StatefulWidget {
  const MuseRoll({super.key, required this.value, required this.child, this.alignment = AlignmentDirectional.centerStart});

  final Object? value;
  final Widget child;
  final AlignmentGeometry alignment;

  /// tests: rolls currently animating
  @visibleForTesting
  static int debugRolling = 0;

  static final _total = MuseMotion.maskInDelay + MuseMotion.maskIn;

  @override
  State<MuseRoll> createState() => _MuseRollState();
}

class _MuseRollState extends State<MuseRoll> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: MuseRoll._total)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        _setRolling(false);
        setState(() => _old = null);
      }
    });
  Widget? _old;
  int _gen = 0;
  bool _rolling = false;

  void _setRolling(bool v) {
    if (_rolling == v) return;
    _rolling = v;
    MuseRoll.debugRolling += v ? 1 : -1;
  }

  late final Animation<Offset> _out = Tween(begin: Offset.zero, end: const Offset(0, -1)).animate(
    CurvedAnimation(
      parent: _c,
      curve: Interval(0, MuseMotion.maskOut.inMicroseconds / MuseRoll._total.inMicroseconds, curve: MuseMotion.exitCurve),
    ),
  );
  late final Animation<Offset> _in = Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
    CurvedAnimation(
      parent: _c,
      curve: Interval(MuseMotion.maskInDelay.inMicroseconds / MuseRoll._total.inMicroseconds, 1, curve: MuseMotion.curve),
    ),
  );

  @override
  void didUpdateWidget(MuseRoll old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    if (museMotionLevel(context) != MuseMotionLevel.standard || old.value == null) {
      _c.stop();
      _setRolling(false);
      _old = null;
      return;
    }
    _old = old.child;
    _gen++;
    _setRolling(true);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _setRolling(false);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    final rolling = old != null;
    return ClipRect(
      clipBehavior: rolling ? Clip.hardEdge : Clip.none,
      child: Stack(
        alignment: widget.alignment,
        children: [
          if (old != null)
            KeyedSubtree(
              key: ValueKey('roll_old_$_gen'),
              child: ExcludeSemantics(child: SlideTransition(position: _out, child: old)),
            ),
          KeyedSubtree(
            key: const ValueKey('roll_current'),
            child: rolling ? SlideTransition(position: _in, child: widget.child) : widget.child,
          ),
        ],
      ),
    );
  }
}

/// A light band sweeping across [child] while [active] (等待态：切节点、测速、更新订阅、连接中).
/// Runs only on 标准, only while the page is on screen (tickers are muted otherwise), and stops
/// for good after [timeout]; otherwise it is just [child].
class MuseSweep extends StatefulWidget {
  const MuseSweep({super.key, required this.child, this.active = true, this.timeout = MuseMotion.sweepTimeout});

  final Widget child;
  final bool active;
  final Duration timeout;

  /// tests: sweeps currently running
  @visibleForTesting
  static int debugRunning = 0;

  @override
  State<MuseSweep> createState() => _MuseSweepState();
}

class _MuseSweepState extends State<MuseSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: MuseMotion.sweep);
  Timer? _timeout;
  bool _timedOut = false;
  bool _running = false;

  bool _shouldRun(BuildContext context) => widget.active && !_timedOut && museMotionRich(context);

  void _sync(bool run) {
    if (run == _running) return;
    _running = run;
    if (run) {
      MuseSweep.debugRunning++;
      _c.repeat();
      _timeout = Timer(widget.timeout, () {
        if (!mounted) return;
        setState(() => _timedOut = true);
      });
    } else {
      MuseSweep.debugRunning--;
      _c.stop();
      _timeout?.cancel();
      _timeout = null;
    }
  }

  @override
  void didUpdateWidget(MuseSweep old) {
    super.didUpdateWidget(old);
    // a new waiting period starts afresh
    if (widget.active && !old.active) _timedOut = false;
  }

  @override
  void dispose() {
    _sync(false);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = _shouldRun(context);
    _sync(run);
    if (!run) return widget.child;
    final band = Theme.of(context).colorScheme.surface.withValues(alpha: 0.75);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          key: const ValueKey('muse_sweep_mask'),
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            colors: [band.withValues(alpha: 0), band, band.withValues(alpha: 0)],
            stops: const [0.35, 0.5, 0.65],
            transform: _SweepTransform(_c.value),
          ).createShader(rect),
          child: child,
        ),
      ),
    );
  }
}

/// moves the gradient from fully left of the box to fully right of it
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}
