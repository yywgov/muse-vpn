// 穿云 1.19.1 动效审查 10 条（docs/motion-audit-1.19.md 第三节）：按压反馈、返回快起、页面 300ms、
// 主题揭开快起、MuseRoll 300ms、终点滑动 450ms、分类线与终点尾段淡入、光点 1 趟、精简档骨架静态、
// Tab 切换减弱。每条都检查：走 MuseMotion 令牌、尊重档位、一次性（结束后不再出帧）。
// Part of 穿云 (GPLv3).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/go_router/helper/custom_transition.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart' show MuseStartButton, MuseStartButtonState;
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart' show MuseTabTransition;
import 'package:hiddify/features/muse/widget/muse_motion.dart';
import 'package:hiddify/features/muse/widget/muse_motion_widgets.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
import 'package:hiddify/features/muse/widget/muse_theme_reveal.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_theme.dart' show museThemeRevealMs;

String _src(String p) => File(p).readAsStringSync();

bool _framePending(WidgetTester t) =>
    SchedulerBinding.instance.hasScheduledFrame || t.binding.transientCallbackCount > 0;

Widget _app(Widget child, {MuseMotionLevel level = MuseMotionLevel.standard, bool systemOff = false}) => MaterialApp(
  builder: (ctx, c) => MediaQuery(
    data: MediaQuery.of(ctx).copyWith(disableAnimations: systemOff),
    child: Builder(builder: (ctx) => museWrapMotion(ctx, level, c!)),
  ),
  home: Scaffold(body: Center(child: child)),
);

final _dots = MuseWorldDots.parse(File('assets/map/world_dots.bin').readAsBytesSync())!;
final _tokyo = museResolveExitPlace(nodeName: '日本 东京 01');
final _la = museResolveExitPlace(nodeName: '🇺🇸 Los Angeles');
final _tokyo2 = museResolveExitPlace(nodeName: '日本 东京 02'); // 1.21.0：同城另一个节点

Widget _map(MuseMotionLevel level, {required bool connected, required MuseExitPlace exit}) => MaterialApp(
  home: MuseMotionScope(
    level: level,
    child: Scaffold(
      body: SizedBox(width: 400, child: MuseRouteMap(connected: connected, exit: exit, dots: _dots)),
    ),
  ),
);

void main() {
  group('1 连接按钮按压反馈', () {
    double scale(WidgetTester t) => t.widget<AnimatedScale>(find.byKey(const ValueKey('home_connect_press'))).scale;
    double rendered(WidgetTester t) => t
        .widget<ScaleTransition>(
          find.descendant(of: find.byKey(const ValueKey('home_connect_press')), matching: find.byType(ScaleTransition)).first,
        )
        .scale
        .value;

    test('令牌', () {
      expect(MuseMotion.pressScale, 0.96);
      expect(MuseMotion.pressIn.inMilliseconds, 100);
      expect(MuseMotion.pressOut.inMilliseconds, 160);
    });

    testWidgets('标准档：按下 100ms 缩到 0.96，松开 160ms 回 1，结束后无帧', (t) async {
      // 1.20.0: MuseStartButton no longer takes onBrand (the card is neutral in every state)
      var taps = 0;
      await t.pumpWidget(_app(MuseStartButton(on: false, onTap: () => taps++, semanticLabel: '连接')));
      final g = await t.startGesture(t.getCenter(find.byType(MuseStartButton)));
      await t.pump();
      expect(scale(t), MuseMotion.pressScale);
      await t.pump(); // 第一帧：Ticker 从这里开始计时
      await t.pump(const Duration(milliseconds: 50));
      expect(rendered(t), lessThan(1.0));
      expect(rendered(t), greaterThan(MuseMotion.pressScale));
      await t.pump(const Duration(milliseconds: 60));
      expect(rendered(t), closeTo(MuseMotion.pressScale, 1e-6));
      expect(_framePending(t), isFalse);
      await g.up();
      await t.pump();
      expect(taps, 1);
      expect(scale(t), 1.0);
      await t.pump();
      await t.pump(const Duration(milliseconds: 170));
      expect(rendered(t), closeTo(1.0, 1e-6));
      expect(_framePending(t), isFalse);
    });

    testWidgets('取消（拖走）也回到 1', (t) async {
      await t.pumpWidget(_app(MuseStartButton(on: false, onTap: () {}, semanticLabel: '连接')));
      final g = await t.startGesture(t.getCenter(find.byType(MuseStartButton)));
      await t.pump();
      expect(t.state<MuseStartButtonState>(find.byType(MuseStartButton)).pressed, isTrue);
      await g.moveBy(const Offset(0, 300));
      await g.cancel();
      await t.pump();
      expect(scale(t), 1.0);
      await t.pumpAndSettle();
    });

    testWidgets('禁用与关闭档（含系统移除动画）不缩', (t) async {
      Future<void> check(Widget w) async {
        await t.pumpWidget(w);
        final g = await t.startGesture(t.getCenter(find.byType(MuseStartButton)));
        await t.pump(const Duration(milliseconds: 120));
        expect(scale(t), 1.0);
        expect(rendered(t), 1.0);
        await g.up();
        await t.pumpAndSettle();
      }

      await check(_app(const MuseStartButton(on: false, onTap: null, semanticLabel: '连接')));
      await check(
        _app(MuseStartButton(on: false, onTap: () {}, semanticLabel: '连接'), level: MuseMotionLevel.off),
      );
      await check(_app(MuseStartButton(on: false, onTap: () {}, semanticLabel: '连接'), systemOff: true));
    });

    testWidgets('精简档：保留 4% 缩放，时长 ×0.6、平稳曲线', (t) async {
      await t.pumpWidget(
        _app(MuseStartButton(on: false, onTap: () {}, semanticLabel: '连接'), level: MuseMotionLevel.reduced),
      );
      final g = await t.startGesture(t.getCenter(find.byType(MuseStartButton)));
      await t.pump();
      final w = t.widget<AnimatedScale>(find.byKey(const ValueKey('home_connect_press')));
      expect(w.scale, MuseMotion.pressScale);
      expect(w.duration, const Duration(milliseconds: 60));
      expect(w.curve, MuseMotion.plainCurve);
      await g.up();
      await t.pumpAndSettle();
    });
  });

  group('2 返回快起', () {
    test('反向曲线是翻转的主曲线，10% 时间已走过 > 20%', () {
      expect(MuseMotion.pageBackCurve.transform(0.9), lessThan(0.8));
      // 旧的 exitCurve.flipped 在同一时刻几乎没动
      expect(MuseMotion.exitCurve.flipped.transform(0.9), greaterThan(0.95));
      expect(_src('lib/core/router/go_router/helper/custom_transition.dart'), contains('reverseCurve: MuseMotion.pageBackCurve'));
    });

    testWidgets('返回动画 20ms（10%）后页面已明显移开', (t) async {
      final a = AnimationController(vsync: const TestVSync(), duration: MuseMotion.page, reverseDuration: MuseMotion.exit);
      addTearDown(a.dispose);
      final c = museTransitionCurve(a);
      a.value = 1;
      a.reverse();
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(c.value, lessThan(0.8));
      await t.pump(const Duration(milliseconds: 200));
      expect(c.value, 0);
    });
  });

  group('3 页面进场 300ms', () {
    test('页面令牌', () {
      expect(MuseMotion.page.inMilliseconds, 300);
      expect(MuseMotion.enter.inMilliseconds, 380, reason: '其他用途（弧线精简档淡入等）不变');
      final s = _src('lib/core/router/go_router/helper/custom_transition.dart');
      expect(s, contains('transitionDuration: MuseMotion.page'));
      expect(s, contains('reverseTransitionDuration: MuseMotion.exit'));
    });
  });

  group('4 主题揭开快起', () {
    test('t = 0.2 时半径已超过最大半径的 40%，400ms 不变', () {
      const size = Size(400, 800);
      const c = Offset(200, 400);
      final max = MuseRevealPainter.maxRadius(size, c);
      expect(MuseRevealPainter.radiusAt(size, c, 0.2), greaterThan(0.4 * max));
      expect(MuseRevealPainter.radiusAt(size, c, 0), 0);
      expect(MuseRevealPainter.radiusAt(size, c, 1), closeTo(max, 1e-9));
      final s = _src('lib/features/muse/widget/muse_theme_reveal.dart');
      expect(s, isNot(contains('Curves.easeInOutCubic.transform')));
      expect(s, contains('MuseMotion.curve.transform'));
      expect(museThemeRevealMs, 400);
    });
  });

  group('5 MuseRoll 300ms', () {
    test('出 180 / 延迟 40 / 入 260，退场短于进场', () {
      expect(MuseMotion.maskOut.inMilliseconds, 180);
      expect(MuseMotion.maskInDelay.inMilliseconds, 40);
      expect(MuseMotion.maskIn.inMilliseconds, 260);
      expect((MuseMotion.maskInDelay + MuseMotion.maskIn).inMilliseconds, 300);
      expect(MuseMotion.maskOut, lessThan(MuseMotion.maskIn));
    });

    testWidgets('300ms 后滚动结束、不再出帧', (t) async {
      final v = ValueNotifier(1);
      await t.pumpWidget(
        _app(ValueListenableBuilder<int>(valueListenable: v, builder: (_, n, _) => MuseRoll(value: n, child: Text('$n ms')))),
      );
      v.value = 2;
      await t.pump();
      expect(MuseRoll.debugRolling, 1);
      await t.pump(); // 第一帧：Ticker 从这里开始计时
      await t.pump(const Duration(milliseconds: 250));
      expect(MuseRoll.debugRolling, 1);
      await t.pump(const Duration(milliseconds: 100)); // 旧的 510ms 此时还在滚
      await t.pump();
      expect(MuseRoll.debugRolling, 0);
      expect(find.text('1 ms'), findsNothing);
      expect(_framePending(t), isFalse);
    });
  });

  group('6 / 7 / 8 弧线图', () {
    // 1.20.1：终点滑动与取景、高亮同步，450 → 300ms（v1201_map_test 断言三者同一时长）
    // 1.21.0 方向 B：光点去掉（彗星头随线头），弧线 900ms + 到达涟漪 480ms；换节点旧弧 150ms 淡出、新弧 450ms 重画
    test('令牌：取景同步 300ms、弧线 900 + 涟漪 480（约 1.4s）、换节点 150 + 450、尾段 15%', () {
      expect(MuseRouteMotion.slide.inMilliseconds, 300);
      expect(MuseRouteMotion.draw.inMilliseconds, 900);
      expect(MuseRouteMotion.land.inMilliseconds, 480);
      expect((MuseRouteMotion.draw + MuseRouteMotion.land).inMilliseconds, inInclusiveRange(1300, 1500));
      expect(MuseRouteMotion.swapOut.inMilliseconds, 150);
      expect(MuseRouteMotion.redraw.inMilliseconds, 450);
      expect(MuseRouteMotion.tailFade, 0.15);
    });

    test('7 分类线与终点：弧线最后 15% 线性淡入', () {
      expect(museRouteTailAlpha(0), 0);
      expect(museRouteTailAlpha(0.85), 0);
      expect(museRouteTailAlpha(0.9), closeTo(1 / 3, 1e-9));
      expect(museRouteTailAlpha(0.9), lessThan(1));
      expect(museRouteTailAlpha(1), 1);
      final s = _src('lib/features/muse/home/route_map/muse_route_map.dart');
      expect(s, contains('museRouteTailAlpha(arcV)'));
      expect(s, isNot(contains('if (progress >= 1')));
    });

    testWidgets('8 连接（1.21.0）：弧线 900ms + 到达涟漪 480ms 后停（约 1.4s），之后无帧', (t) async {
      await t.pumpWidget(_map(MuseMotionLevel.standard, connected: false, exit: _tokyo));
      await t.pump();
      await t.pumpWidget(_map(MuseMotionLevel.standard, connected: true, exit: _tokyo));
      await t.pump(); // 第一帧：Ticker 从这里开始计时
      final st = t.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      var ms = 0;
      while (st.animating && ms < 4000) {
        await t.pump(const Duration(milliseconds: 50));
        ms += 50;
      }
      // 弧线 900 + 涟漪 480 = 1380ms（两段之间各有一帧起步）；1.20 是 2000ms
      expect(ms, inInclusiveRange(1350, 1500));
      await t.pump();
      expect(_framePending(t), isFalse);
    });

    // 1.21.0：换节点不再滑动终点——旧弧 150ms 淡出、新弧 450ms 重画、再落地 480ms；精简档直接终态
    testWidgets('6 切节点（1.21.0）：旧弧淡出 → 新弧重画 → 落地，约 1.1s 后停；精简档直接到位', (t) async {
      await t.pumpWidget(_map(MuseMotionLevel.standard, connected: true, exit: _tokyo));
      await t.pumpAndSettle();
      await t.pumpWidget(_map(MuseMotionLevel.standard, connected: true, exit: _la));
      await t.pump(); // 第一帧：Ticker 从这里开始计时
      final st = t.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      await t.pump(const Duration(milliseconds: 100));
      expect(st.swapping, isTrue);
      expect(st.endPoint, _la.city!.point);
      await t.pump(const Duration(milliseconds: 100));
      expect(st.swapping, isFalse);
      var ms = 200;
      while (st.animating && ms < 3000) {
        await t.pump(const Duration(milliseconds: 50));
        ms += 50;
      }
      expect(ms, inInclusiveRange(1050, 1250));
      expect(_framePending(t), isFalse);
      await t.pumpWidget(const SizedBox());

      await t.pumpWidget(_map(MuseMotionLevel.reduced, connected: true, exit: _tokyo));
      await t.pumpAndSettle();
      await t.pumpWidget(_map(MuseMotionLevel.reduced, connected: true, exit: _la));
      await t.pump();
      final r = t.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      expect(r.swapping, isFalse);
      expect(r.landing, isFalse);
      expect(r.arcOpacity, 1);
      await t.pumpAndSettle();
      expect(_framePending(t), isFalse);
    });

    testWidgets('6b 同一城市换节点：只换文字，不重画弧线', (t) async {
      await t.pumpWidget(_map(MuseMotionLevel.standard, connected: true, exit: _tokyo));
      await t.pumpAndSettle();
      await t.pumpWidget(_map(MuseMotionLevel.standard, connected: true, exit: _tokyo2));
      await t.pump();
      final st = t.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      expect(st.animating, isFalse);
      expect(_framePending(t), isFalse);
    });

    test('弧高按距离 3 档', () {
      expect(museArcLiftTier(museGeoDistanceKm(museHomeCity.point, const MuseGeoPoint(37.57, 126.98))), 0); // 首尔
      expect(museArcLiftTier(museGeoDistanceKm(museHomeCity.point, const MuseGeoPoint(1.35, 103.82))), 1); // 新加坡
      expect(museArcLiftTier(museGeoDistanceKm(museHomeCity.point, const MuseGeoPoint(52.37, 4.90))), 2); // 阿姆斯特丹
      expect(museArcLiftShares, [0.10, 0.16, 0.22]);
    });
  });

  group('9 精简档骨架静态', () {
    for (final level in MuseMotionLevel.values) {
      testWidgets('${level.name}：${level == MuseMotionLevel.standard ? '循环光带' : '静态'}', (t) async {
        await t.pumpWidget(_app(SizedBox(width: 300, child: MuseSkeleton.rows(rows: 2)), level: level));
        await t.pump(const Duration(milliseconds: 100));
        expect(_framePending(t), level == MuseMotionLevel.standard);
        await t.pumpWidget(const SizedBox());
      });
    }
  });

  group('10 Tab 切换减弱', () {
    test('令牌', () {
      expect(MuseMotion.tab.inMilliseconds, 160);
      expect(MuseMotion.tabShift, 0.03);
      expect(_src('lib/features/muse/shell/muse_shell.dart'), isNot(contains('0.06')));
    });

    testWidgets('起点横移 3%，160ms 后结束、不再出帧；关闭档不动', (t) async {
      Widget tab(int i, {MuseMotionLevel level = MuseMotionLevel.standard}) =>
          _app(MuseTabTransition(index: i, slide: true, child: Text('p$i')), level: level);
      await t.pumpWidget(tab(0));
      await t.pumpWidget(tab(1));
      final slide = t.widget<SlideTransition>(
        find.ancestor(of: find.text('p1'), matching: find.byType(SlideTransition)).first,
      );
      expect(slide.position.value.dx, closeTo(MuseMotion.tabShift, 1e-9));
      await t.pump(const Duration(milliseconds: 170));
      expect(slide.position.value.dx, 0);
      expect(_framePending(t), isFalse);
      await t.pumpWidget(tab(2, level: MuseMotionLevel.off));
      expect(_framePending(t), isFalse);
      expect(t.widget<FadeTransition>(find.byKey(const ValueKey('muse_tab_fade'))).opacity.value, 1);
    });
  });

  test('新改动不含循环与轮询', () {
    // 首页已有的「已连接时长」每秒刷新不是动画，不在此列；只查本次改动的动效文件
    for (final p in [
      'lib/features/muse/widget/muse_theme_reveal.dart',
      'lib/features/muse/home/route_map/muse_route_map.dart',
      'lib/features/muse/shell/muse_shell.dart',
    ]) {
      expect(_src(p), isNot(contains('.repeat(')), reason: p);
      expect(_src(p), isNot(contains('Timer.periodic')), reason: p);
    }
  });
}
