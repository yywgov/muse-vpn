// 穿云 1.18.0 P0 / P6 - 统一动效令牌与三档动效（标准 / 精简 / 关闭）。
// 主曲线 cubic(.32,.86,.22,1)；进场 350–400ms、退场约 200ms、反馈约 150ms；无回弹弹簧与「到达」
// 轻回弹弹簧。所有动画一次性；唯一允许的持续动画是有期限的等待态（扫光），只在标准档、页面可见时运行。
// 只借思路与参数（公开设计规范），不含任何第三方代码或素材。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 动效档位（实际生效的）。
enum MuseMotionLevel {
  /// 标准：完整动效
  standard,

  /// 精简：时长 ×0.6、无回弹、去掉扫光与循环光带，只保留淡入淡出与颜色变化
  reduced,

  /// 关闭：直接显示终态，等待态用静态文字
  off,
}

/// 外观 › 动效 里的选择。
enum MuseMotionChoice {
  auto('auto', '跟随系统'),
  standard('standard', '标准'),
  reduced('reduced', '精简'),
  off('off', '关闭');

  const MuseMotionChoice(this.key, this.title);

  final String key;
  final String title;

  static MuseMotionChoice fromKey(String k) => values.firstWhere((c) => c.key == k, orElse: () => auto);
}

/// 档位规则：系统「移除动画」永远优先（无障碍）；跟随系统时省电模式降为精简；手动选择不看省电模式。
MuseMotionLevel museResolveMotionLevel({
  required MuseMotionChoice choice,
  required bool systemDisable,
  required bool powerSave,
}) {
  if (systemDisable) return MuseMotionLevel.off;
  return switch (choice) {
    MuseMotionChoice.auto => powerSave ? MuseMotionLevel.reduced : MuseMotionLevel.standard,
    MuseMotionChoice.standard => MuseMotionLevel.standard,
    MuseMotionChoice.reduced => MuseMotionLevel.reduced,
    MuseMotionChoice.off => MuseMotionLevel.off,
  };
}

/// A spring as a [Curve] for implicit animations (AnimatedContainer…): the curve runs the spring
/// from 0 to 1 over its settle time; [settleDuration] is how long the animation should be.
class MuseSpringCurve extends Curve {
  MuseSpringCurve(this.spring) : _sim = SpringSimulation(spring, 0, 1, 0), _settle = _settleSeconds(spring);

  final SpringDescription spring;
  final SpringSimulation _sim;
  final double _settle;

  static double _settleSeconds(SpringDescription s) {
    final sim = SpringSimulation(s, 0, 1, 0, tolerance: const Tolerance(distance: 0.002, velocity: 0.02));
    var t = 0.0;
    while (t < 3 && !sim.isDone(t)) {
      t += 1 / 240;
    }
    return t <= 0 ? 0.001 : t;
  }

  Duration get settleDuration => Duration(microseconds: (_settle * 1e6).round());

  /// the largest value the curve reaches (1 = no overshoot)
  double get peak {
    var m = 0.0;
    for (var i = 0; i <= 200; i++) {
      final v = _sim.x(_settle * i / 200);
      if (v > m) m = v;
    }
    return m;
  }

  @override
  double transformInternal(double t) => _sim.x(t * _settle);
}

/// 动效令牌。原有名称保留（fast/mid/common/tab/pressFeedback/skeletonPulse/sheetDetents）。
abstract final class MuseMotion {
  /// 主曲线：快速起步、长而柔和的收尾（1.18.0 起所有缓动默认用它）
  static const curve = Cubic(0.32, 0.86, 0.22, 1.0);

  /// 退场：先慢后快（Material 3 emphasized accelerate）
  static const exitCurve = Cubic(0.3, 0.0, 0.8, 0.15);

  /// 精简档用的平稳缓动（无过冲）
  static const plainCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  /// 进场（页面、弹层）
  static const enter = Duration(milliseconds: 380);

  /// 退场（返回）
  static const exit = Duration(milliseconds: 200);

  /// 操作反馈（按压、颜色）
  static const feedback = Duration(milliseconds: 150);

  /// 「到达」时刻（连接成功）
  static const arrive = Duration(milliseconds: 450);

  static const fast = Duration(milliseconds: 200);

  /// 1.6.0 C1
  static const mid = Duration(milliseconds: 200);
  static const common = Duration(milliseconds: 300);
  static const tab = Duration(milliseconds: 220);
  static const pressFeedback = feedback;
  static const tabCurve = curve;
  static const sheetDetents = [9 / 16, 0.9];

  /// 1.5.0: one half of a skeleton's pulse
  static const skeletonPulse = Duration(milliseconds: 900);

  /// 无回弹弹簧（形状、位置）
  static final springSmooth = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 350));

  /// 「到达」轻回弹（只用于到达时刻的形状变化）
  static final springArrive = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 400), bounce: 0.15);

  static final smoothCurve = MuseSpringCurve(springSmooth);
  static final arriveCurve = MuseSpringCurve(springArrive);

  /// P3 数字遮罩滚动：旧字上滑出 260ms；新字延迟 90ms、420ms 滑入
  static const maskOut = Duration(milliseconds: 260);
  static const maskIn = Duration(milliseconds: 420);
  static const maskInDelay = Duration(milliseconds: 90);

  /// 等待态文字扫光：一趟 1100ms；最长持续时间（超时后停在静态文字）
  static const sweep = Duration(milliseconds: 1100);
  static const sweepTimeout = Duration(seconds: 30);

  /// 精简档的时长倍数
  static const reducedFactor = 0.6;
}

/// The app-wide 动效 level (外观 › 动效 + Android 省电模式), put above the pages by the app.
class MuseMotionScope extends InheritedWidget {
  const MuseMotionScope({super.key, required this.level, required super.child});

  final MuseMotionLevel level;

  static MuseMotionLevel? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MuseMotionScope>()?.level;

  @override
  bool updateShouldNotify(MuseMotionScope oldWidget) => level != oldWidget.level;
}

/// 实际生效的档位：系统「移除动画」（或外观里选「关闭」，见 app.dart）→ 关闭；否则看 [MuseMotionScope]。
MuseMotionLevel museMotionLevel(BuildContext context) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return MuseMotionLevel.off;
  return MuseMotionScope.maybeOf(context) ?? MuseMotionLevel.standard;
}

/// 1.5.0: whether animations are off (Android 「移除动画」, Windows 「动画效果」 off; 1.18.0: or 动效「关闭」).
bool museReduceMotion(BuildContext context) => museMotionLevel(context) == MuseMotionLevel.off;

/// 1.18.0: whether waiting effects (扫光, 光带) may run — 标准档 only.
bool museMotionRich(BuildContext context) => museMotionLevel(context) == MuseMotionLevel.standard;

/// [d] for the current level: 0 when off, ×0.6 when reduced.
Duration museDuration(BuildContext context, Duration d) => museScaleDuration(museMotionLevel(context), d);

Duration museScaleDuration(MuseMotionLevel level, Duration d) => switch (level) {
  MuseMotionLevel.off => Duration.zero,
  MuseMotionLevel.reduced => d * MuseMotion.reducedFactor,
  MuseMotionLevel.standard => d,
};

/// [c] for the current level: springs and the main curve become [MuseMotion.plainCurve] when reduced.
Curve museCurve(BuildContext context, [Curve c = MuseMotion.curve]) =>
    museMotionLevel(context) == MuseMotionLevel.standard ? c : MuseMotion.plainCurve;

/// 1.5.0: [MuseMotion.fast] for the current level.
Duration museMotion(BuildContext context) => museDuration(context, MuseMotion.fast);

/// 1.18.0 P6: puts [level] above [child]; 「关闭」 also sets MediaQuery.disableAnimations so
/// Flutter's own widgets (switches, sheets, ink) stop animating too.
Widget museWrapMotion(BuildContext context, MuseMotionLevel level, Widget child) {
  Widget c = MuseMotionScope(level: level, child: child);
  if (level == MuseMotionLevel.off) {
    final mq = MediaQuery.maybeOf(context);
    if (mq != null && !mq.disableAnimations) c = MediaQuery(data: mq.copyWith(disableAnimations: true), child: c);
  }
  return c;
}
