// 穿云 1.19.0 P1 首页「路由弧线图」：坐标映射、出口位置来源、点阵底图、动效档位与「动画结束后不再出帧」。
// Part of 穿云 (GPLv3).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';

final _dotsOnce = MuseWorldDots.parse(File('assets/map/world_dots.bin').readAsBytesSync())!;
MuseWorldDots _dots() => _dotsOnce;

final _tokyo = museResolveExitPlace(nodeName: '日本 东京 01');
final _la = museResolveExitPlace(nodeName: '🇺🇸 Los Angeles');

Widget _app(MuseMotionLevel level, {required bool connected, required MuseExitPlace exit, MuseWorldDots? dots}) =>
    MaterialApp(
      home: MuseMotionScope(
        level: level,
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: MuseRouteMap(connected: connected, exit: exit, dots: dots ?? _dots()),
          ),
        ),
      ),
    );

MuseRouteMapState _state(WidgetTester t) => t.state<MuseRouteMapState>(find.byType(MuseRouteMap));

bool _framePending(WidgetTester t) =>
    SchedulerBinding.instance.hasScheduledFrame || t.binding.transientCallbackCount > 0;

void main() {
  group('坐标映射', () {
    test('中央经线 110° 在画布正中，北 84° 在顶、南 60° 在底', () {
      const s = Size(360, 144);
      expect(museProject(0, 110, s).dx, closeTo(180, 1e-9));
      expect(museProject(84, 110, s).dy, closeTo(0, 1e-9));
      expect(museProject(-60, 110, s).dy, closeTo(144, 1e-9));
      // 西经 118°（洛杉矶）展开到 242°，在中国右边
      expect(museWrapLon(-118), closeTo(242, 1e-9));
      expect(museProject(34, -118, s).dx, greaterThan(museProject(31, 121, s).dx));
      // 伦敦在中国左边
      expect(museProject(51.5, -0.1, s).dx, lessThan(museProject(31, 121, s).dx));
    });

    test('大圆弧：端点准确、经度连续、跨太平洋不断开', () {
      final pts = museGreatCircle(museHomeCity.point, _la.city!.point);
      expect(pts.first.lat, closeTo(museHomeCity.lat, 1e-6));
      expect(pts.first.lon, closeTo(museHomeCity.lon, 1e-6));
      expect(pts.last.lat, closeTo(34.05, 1e-6));
      expect(museWrapLon(pts.last.lon), closeTo(242 - 0.24, 1e-6));
      for (var i = 1; i < pts.length; i++) {
        expect((pts[i].lon - pts[i - 1].lon).abs(), lessThan(10));
      }
      // 大圆弧往北鼓起
      expect(pts.map((p) => p.lat).reduce((a, b) => a > b ? a : b), greaterThan(45));
      expect(museGeoLerp(museHomeCity.point, _la.city!.point, 0), museHomeCity.point);
      expect(museGeoLerp(museHomeCity.point, _la.city!.point, 1), _la.city!.point);
    });
  });

  group('出口位置', () {
    test('实测优先；同地区时用节点名里更准的城市', () {
      final a = museResolveExitPlace(nodeName: '美国 西雅图', measuredRegion: 'us');
      expect(a.source, MuseExitSource.measured);
      expect(a.city!.name, '西雅图');
      final b = museResolveExitPlace(nodeName: '美国 西雅图', measuredRegion: 'JP');
      expect(b.source, MuseExitSource.measured);
      expect(b.city!.name, '东京');
      expect(_tokyo.source, MuseExitSource.byName);
      expect(_tokyo.city!.name, '东京');
      expect(museResolveExitPlace(nodeName: '香港 01').city!.name, '香港');
    });

    test('认不出的返回未知（城市为 null），标签「实测/按名称/未知」', () {
      expect(museCityForRegion('ZZ'), isNull);
      expect(museCityForNodeName('高速专线 A'), isNull);
      final u = museResolveExitPlace(nodeName: '高速专线 A', measuredRegion: 'ZZ');
      expect(u.known, isFalse);
      expect(u.source, MuseExitSource.unknown);
      expect(MuseExitSource.values.map((e) => e.label), ['实测', '按名称', '未知']);
    });
  });

  test('点阵底图：体积 <100KB、格式正确、陆地/海洋大致对', () {
    final f = File('assets/map/world_dots.bin');
    expect(f.lengthSync(), lessThan(100 * 1024));
    final d = _dots();
    expect(d.width, 240);
    expect(d.height, 96);
    expect(d.landCount, greaterThan(5000));
    int row(double lat) => ((d.north - lat) / d.step).floor();
    int col(double lon) => ((lon + 180) / d.step).floor();
    expect(d.isLand(row(39.9), col(116.4)), isTrue, reason: '北京');
    expect(d.isLand(row(48.9), col(2.35)), isTrue, reason: '巴黎');
    expect(d.isLand(row(0), col(-150)), isFalse, reason: '太平洋');
    expect(MuseWorldDots.parse(File('pubspec.yaml').readAsBytesSync()), isNull);
  });

  group('MuseRouteMap', () {
    testWidgets('标准档：弧线画出 + 光点跑完后停，之后不再调度帧', (t) async {
      await t.pumpWidget(_app(MuseMotionLevel.standard, connected: false, exit: _tokyo));
      await t.pump(); // 首帧后的收尾帧
      expect(find.text('未连接'), findsOneWidget);
      expect(_framePending(t), isFalse);
      await t.pumpWidget(_app(MuseMotionLevel.standard, connected: true, exit: _tokyo));
      await t.pump(const Duration(milliseconds: 500));
      expect(_state(t).animating, isTrue);
      await t.pump(const Duration(milliseconds: 700)); // 弧线已画完，光点在跑
      expect(_state(t).animating, isTrue);
      await t.pumpAndSettle();
      expect(_state(t).animating, isFalse);
      expect(_framePending(t), isFalse);
      expect(find.text('上海 → 东京 · 按名称'), findsOneWidget);
      // 动画结束后再等也没有帧
      await t.pump(const Duration(seconds: 5));
      expect(_framePending(t), isFalse);
    });

    testWidgets('切节点：终点 700ms 滑到新城市，结束后不再出帧', (t) async {
      await t.pumpWidget(_app(MuseMotionLevel.standard, connected: true, exit: _tokyo));
      await t.pumpAndSettle();
      await t.pumpWidget(_app(MuseMotionLevel.standard, connected: true, exit: _la));
      await t.pump(const Duration(milliseconds: 350));
      expect(_state(t).animating, isTrue);
      await t.pump(const Duration(milliseconds: 400));
      expect(_state(t).animating, isFalse);
      expect(_framePending(t), isFalse);
      expect(find.text('上海 → 洛杉矶 · 按名称'), findsOneWidget);
    });

    testWidgets('关闭档：连接、切节点都没有动画', (t) async {
      await t.pumpWidget(_app(MuseMotionLevel.off, connected: false, exit: _tokyo));
      await t.pumpWidget(_app(MuseMotionLevel.off, connected: true, exit: _tokyo));
      expect(_state(t).animating, isFalse);
      expect(_framePending(t), isFalse);
      await t.pumpWidget(_app(MuseMotionLevel.off, connected: true, exit: _la));
      expect(_state(t).animating, isFalse);
      expect(_framePending(t), isFalse);
    });

    testWidgets('精简档：只淡入，没有光点', (t) async {
      await t.pumpWidget(_app(MuseMotionLevel.reduced, connected: true, exit: _tokyo));
      await t.pump(const Duration(milliseconds: 230));
      expect(_state(t).animating, isFalse, reason: '淡入 380×0.6≈228ms 后即停，不跑光点');
      expect(_framePending(t), isFalse);
    });

    testWidgets('未知城市：不画弧线、显示「出口位置未知」、无动画', (t) async {
      await t.pumpWidget(_app(MuseMotionLevel.standard, connected: true, exit: MuseExitPlace.unknown));
      await t.pump(); // 首帧后的收尾帧
      expect(find.text('出口位置未知'), findsOneWidget);
      expect(_state(t).animating, isFalse);
      expect(_framePending(t), isFalse);
    });

    testWidgets('页面不可见（TickerMode 关）时不出帧；底图同尺寸只渲染一次', (t) async {
      final before = museDotImageRenders;
      await t.pumpWidget(_app(MuseMotionLevel.standard, connected: false, exit: _tokyo));
      await t.pumpWidget(
        TickerMode(enabled: false, child: _app(MuseMotionLevel.standard, connected: true, exit: _tokyo)),
      );
      await t.pump(const Duration(milliseconds: 16));
      expect(_framePending(t), isFalse);
      expect(museDotImageRenders - before, lessThanOrEqualTo(1));
    });
  });
}
