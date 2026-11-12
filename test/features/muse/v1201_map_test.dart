// 穿云 1.20.1 首页连接卡地图修复：小国高亮看得见（新加坡、荷兰、瑞士、以色列、比利时、香港、卡塔尔、日本、美国，
// 手机 372×148 与电脑版连接卡两种尺寸）、终点底色圈在高亮下层、1:50m 小国细网格与屏幕最小高亮面积、代表城市补齐；
// 过渡逐帧无点阵密度跳变 / 半径跳变、取景 / 高亮 / 终点 300ms 同步且终点不滑出地图、绕不动点缩放、断开时弧线淡出、
// 首页不在前台时换节点直接到位、地图只采用当前节点的出口实测。
// Part of 穿云 (GPLv3).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart';
import 'package:hiddify/features/muse/home/route_map/route_countries.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

MuseWorldDots? _dotsCache;
MuseWorldDots _dots() => _dotsCache ??= MuseWorldDots.parse(File('assets/map/world_dots.bin').readAsBytesSync())!;

const _phone = Size(372, 148);
const _desk = Size(560, 215);

const _names = {
  'SG': '🇸🇬 新加坡 CF官方优选4',
  'NL': '🇳🇱 荷兰 CF官方优选7',
  'CH': '🇨🇭 瑞士 01',
  'IL': '🇮🇱 以色列 01',
  'BE': '🇧🇪 比利时 01',
  'HK': '🇭🇰 香港 01',
  'QA': '🇶🇦 卡塔尔 01',
  'JP': '🇯🇵 东京 02',
  'US': '🇺🇸 洛杉矶 01',
};

MuseExitPlace _place(String region) => museResolveExitPlace(nodeName: _names[region]);

Widget _map(
  Size size, {
  required bool connected,
  required String region,
  bool reduce = false,
  bool ticker = true,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: Size(size.width + 40, 800), disableAnimations: reduce),
    child: Scaffold(
      body: TickerMode(
        enabled: ticker,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            child: MuseRouteMap(
              connected: connected,
              exit: _place(region),
              dots: _dots(),
              height: size.height,
              showCaption: false,
              centerLon: MuseHomeA.centerLon,
              fit: true,
              highlightRegion: connected ? region : null,
              look: MuseMapLook.card,
            ),
          ),
        ),
      ),
    ),
  ),
);

/// 高亮点里看得见的：在地图内，且圆心不在实心终点 / 本机点下面。
int _visible(List<MuseHighlightLayer> layers, Size size, MuseMapView v, MuseGeoPoint end) {
  final e = museProject(end.lat, end.lon, size, view: v);
  final h = museProject(museHomeCity.lat, museHomeCity.lon, size, view: v);
  var n = 0;
  for (final l in layers) {
    for (final o in l.points) {
      if (o.dx < 0 || o.dy < 0 || o.dx > size.width || o.dy > size.height) continue;
      if ((o - e).distance <= MuseHomeA.endDot || (o - h).distance <= MuseHomeA.endDot) continue;
      n++;
    }
  }
  return n;
}

/// 点阵「有效抽稀」：视窗内全部陆地格数 / 按透明度加权后画出的点数，开平方（k=1 时为 1、k=2 时约 2）。
double _kEff(MuseRouteMapState s, Size size) {
  final layers = s.dotLayersNow();
  var w = 0.0;
  for (final l in layers) {
    w += l.count * l.alpha;
  }
  final all = museDotLayers(_dots(), s.view!, size, MuseHomeA.dotShare, kFrom: 1, kTo: 1).fold<int>(0, (a, l) => a + l.count);
  return w <= 0 ? 0 : math.sqrt(all / w);
}

/// 按透明度加权的平均点半径。
double _rMax(MuseRouteMapState s) {
  var w = 0.0;
  var r = 0.0;
  for (final l in s.dotLayersNow()) {
    w += l.count * l.alpha;
    r += l.count * l.alpha * l.radius;
  }
  return w <= 0 ? 0 : r / w;
}

void main() {
  group('国家高亮看得见（1:50m 小国 + 永不抽稀 + 屏幕最小面积）', () {
    for (final size in [_phone, _desk]) {
      for (final region in _names.keys) {
        testWidgets('$region @ ${size.width.toInt()}×${size.height.toInt()}：已连接取景下看得见的高亮点 ≥ 5', (tester) async {
          await tester.pumpWidget(_map(size, connected: true, region: region));
          await tester.pumpAndSettle();
          final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
          final v = s.view!;
          final city = museCityForRegion(region)!;
          final layers = museHighlightLayers(_dots(), region, v, size, look: MuseMapLook.card, city: city.point);
          final n = _visible(layers, size, v, s.endPoint!);
          expect(n, greaterThanOrEqualTo(MuseHomeA.hlMinDots), reason: '$region visible=$n');
          // 高亮点阵的屏幕外接框不小于最小面积（新加坡、香港这类以出口城市周围的一小片光斑显示）
          final all = [for (final l in layers) ...l.points];
          final w = all.map((o) => o.dx).reduce(math.max) - all.map((o) => o.dx).reduce(math.min);
          final h = all.map((o) => o.dy).reduce(math.max) - all.map((o) => o.dy).reduce(math.min);
          expect(math.max(w, h), greaterThanOrEqualTo(MuseHomeA.hlMinPx * 0.7), reason: '$region box ${w}x$h');
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    test('高亮永不抽稀：荷兰在新加坡级取景里每个底图格都画', () {
      final v = museFitView(_phone, museHomeCity.point, museRegionPoints(_dots(), 'NL'), minSpan: 150);
      final layers = museHighlightLayers(_dots(), 'NL', v, _phone, look: MuseMapLook.card, city: museCityForRegion('NL')!.point);
      final cells = museDotCountryCells['NL']!;
      expect(layers.first.points.length, cells.length);
      expect(cells.length, greaterThanOrEqualTo(7)); // 1:110m 时只有 4 个
    });

    test('数据：节点常见地区都有点阵与代表城市（卡塔尔、巴林、希腊、保加利亚……）', () {
      final src = File('lib/features/muse/home/node_label.dart').readAsStringSync();
      final codes = RegExp(r"\), '([A-Z]{2})'\)").allMatches(src).map((m) => m.group(1)!).toSet()
        ..addAll(['QA', 'BH', 'KW', 'GR', 'BG', 'LU', 'MO']);
      for (final c in codes) {
        final city = museCityForRegion(c);
        expect(city, isNotNull, reason: '$c 没有代表城市');
        expect(museRegionPoints(_dots(), c), isNotEmpty, reason: '$c 没有点');
      }
      for (final c in ['HK', 'SG', 'MO', 'QA', 'BH', 'LU']) {
        expect(museDotCountryCells[c], isNotEmpty, reason: '$c 1:50m 底图格');
        expect(museDotCountryFine[c], isNotNull, reason: '$c 细网格');
      }
      // 细网格打包可逆
      final p = museUnpackFine(museDotCountryFine['SG']!.last.first);
      expect(p.lat, closeTo(1.3, 0.5));
      expect(p.lon, closeTo(103.8, 0.5));
    });

    testWidgets('终点底色圈画在高亮下层（不再擦掉小国仅有的点）', (tester) async {
      await tester.pumpWidget(_map(_phone, connected: true, region: 'NL'));
      await tester.pumpAndSettle();
      final ring = find.byKey(const ValueKey('muse_route_end_ring'));
      final hl = find.byKey(const ValueKey('muse_route_highlight'));
      expect(ring, findsOneWidget);
      expect(hl, findsOneWidget);
      final stack = tester.widget<Stack>(find.ancestor(of: hl, matching: find.byType(Stack)).first);
      final keys = stack.children.map((w) => w.key).toList();
      expect(keys.indexOf(const ValueKey('muse_route_end_ring')), lessThan(keys.indexOf(const ValueKey('muse_route_highlight'))));
      expect(keys.indexOf(const ValueKey('muse_route_highlight')), lessThan(keys.indexOf(const ValueKey('muse_route_arc'))));
    });

    test('细点下限 0.7：新加坡 / 荷兰级取景（格距约 3.5 px）回到全密度', () {
      expect(MuseHomeA.dotMinRadius, 0.7);
      expect(museDotStride(3.47, MuseHomeA.dotShare), 1);
      expect(museDotStride(3.0, MuseHomeA.dotShare), 1);
    });
  });

  group('过渡（逐帧）', () {
    Future<void> run(WidgetTester tester, List<(bool, String)> steps, {Size size = _phone}) async {
      await tester.pumpWidget(_map(size, connected: steps.first.$1, region: steps.first.$2));
      await tester.pumpAndSettle();
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      for (final (connected, region) in steps.skip(1)) {
        var k = _kEff(s, size);
        var r = _rMax(s);
        var span = s.view!.span;
        await tester.pumpWidget(_map(size, connected: connected, region: region));
        for (var f = 0; f < 30; f++) {
          await tester.pump(const Duration(milliseconds: 16));
          final k2 = _kEff(s, size);
          final r2 = _rMax(s);
          expect((k2 - k).abs() / k, lessThan(0.15), reason: '$region 第 $f 帧 有效抽稀 $k → $k2');
          // 缩放本身让点半径随格距按比例变化（这一帧的缩放倍数）；抽稀跳档是取景不动、半径却成倍变，超出这个界
          final span2 = s.view!.span;
          final zoom = (math.log(span2 / span)).abs();
          expect((r2 - r).abs(), lessThan(0.25 + r * zoom * 1.1), reason: '$region 第 $f 帧 点半径 $r → $r2（缩放 $zoom）');
          span = span2;
          // 1.21.0：终点不再滑动——新终点在新弧画到尾段（取景早已到位）时才出现，只查那时
          if (connected && s.endPoint != null && s.endShown) {
            final e = museProject(s.endPoint!.lat, s.endPoint!.lon, size, view: s.view!);
            expect(e.dy, inInclusiveRange(-1.0, size.height + 1), reason: '$region 第 $f 帧 终点 y=${e.dy}');
          }
          k = k2;
          r = r2;
        }
        await tester.pumpAndSettle();
        expect(s.animating, isFalse);
      }
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    }

    testWidgets('连上新加坡 → 换荷兰 → 换日本 → 断开：相邻帧点阵密度变化 < 15%、半径除缩放本身外变化 < 0.25 px、终点不出地图', (tester) async {
      await run(tester, [(false, 'SG'), (true, 'SG'), (true, 'NL'), (true, 'JP'), (false, 'JP')]);
    });

    testWidgets('电脑版尺寸：美国 → 香港 → 卡塔尔，同样无跳变', (tester) async {
      await run(tester, [(true, 'US'), (true, 'HK'), (true, 'QA')], size: _desk);
    });

    test('取景、高亮、终点滑动同一时长 300ms、同一条对称缓动', () {
      expect(MuseRouteMotion.view, MuseRouteMotion.sync);
      expect(MuseRouteMotion.highlight, MuseRouteMotion.sync);
      expect(MuseRouteMotion.slide, MuseRouteMotion.sync);
      expect(MuseRouteMotion.sync.inMilliseconds, 300);
      final c = MuseRouteMotion.curve;
      expect(c.transform(0.5), closeTo(0.5, 1e-9));
      expect(c.transform(0.2), lessThan(0.2));
    });

    test('绕不动点缩放：目标城市在屏幕上单调靠近它的终点位置', () {
      final nl = museFitView(_phone, museHomeCity.point, museRegionPoints(_dots(), 'NL'));
      final jp = museFitView(_phone, museHomeCity.point, museRegionPoints(_dots(), 'JP'), minSpan: 64);
      for (final (a, b) in [(nl, jp), (jp, nl), (museMapView(_phone).centered(150), jp)]) {
        final city = museCityForRegion(b == jp ? 'JP' : 'NL')!;
        final goal = museProject(city.lat, city.lon, _phone, view: b);
        var last = double.infinity;
        for (var i = 0; i <= 20; i++) {
          final v = museViewLerp(a, b, i / 20);
          final d = (museProject(city.lat, city.lon, _phone, view: v) - goal).distance;
          expect(d, lessThanOrEqualTo(last + 0.5), reason: 'step $i');
          last = d;
        }
        expect(last, lessThan(0.01));
      }
    });

    test('终点滑动走经纬度直线（不经西伯利亚）', () {
      final a = museCityForRegion('NL')!.point;
      final b = museCityForRegion('JP')!.point;
      for (var i = 0; i <= 10; i++) {
        final p = museSlideLerp(a, b, i / 10);
        expect(p.lat, inInclusiveRange(math.min(a.lat, b.lat) - 1e-9, math.max(a.lat, b.lat) + 1e-9));
      }
    });

    testWidgets('断开：弧线随取景淡出（不是一下子消失），淡完不再出帧', (tester) async {
      await tester.pumpWidget(_map(_phone, connected: true, region: 'JP'));
      await tester.pumpAndSettle();
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      expect(s.arcOpacity, 1);
      await tester.pumpWidget(_map(_phone, connected: false, region: 'JP'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.arcOpacity, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(s.arcOpacity, 0);
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    });

    testWidgets('首页不在前台（TickerMode 关）时换节点：直接到位，回到首页第一帧就是新取景', (tester) async {
      await tester.pumpWidget(_map(_phone, connected: true, region: 'SG'));
      await tester.pumpAndSettle();
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      await tester.pumpWidget(_map(_phone, connected: true, region: 'SG', ticker: false));
      await tester.pump();
      await tester.pumpWidget(_map(_phone, connected: true, region: 'NL', ticker: false));
      await tester.pump();
      final target = s.view!;
      expect(s.animating, isFalse);
      await tester.pumpWidget(_map(_phone, connected: true, region: 'NL'));
      await tester.pump();
      expect(s.view, target);
      await tester.pump(const Duration(milliseconds: 16));
      expect(s.view, target);
      expect(s.animating, isFalse);
    });

    testWidgets('减少动效：直接到位、无帧', (tester) async {
      await tester.pumpWidget(_map(_phone, connected: true, region: 'SG', reduce: true));
      await tester.pump();
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      await tester.pumpWidget(_map(_phone, connected: true, region: 'NL', reduce: true));
      await tester.pump();
      expect(s.animating, isFalse);
      await tester.pumpWidget(_map(_phone, connected: false, region: 'NL', reduce: true));
      await tester.pump();
      expect(s.animating, isFalse);
      expect(s.arcOpacity, 0);
    });
  });

  group('换节点后立即按节点取景（不等出口检测）', () {
    test('旧节点的实测不用：按新节点名；当前节点的实测照用；未记节点的旧数据照用', () {
      const old = MuseExitResult(info: MuseExitInfo(ip: '1.1.1.1', country: 'SG'), node: '🇸🇬 新加坡');
      expect(museExitRegionFor(old, '🇳🇱 荷兰'), isNull);
      expect(museExitRegionFor(old, '🇸🇬 新加坡'), 'SG');
      expect(museExitRegionFor(const MuseExitResult(info: MuseExitInfo(ip: '1.1.1.1', country: 'SG')), '🇳🇱 荷兰'), 'SG');
      expect(museExitRegionFor(null, 'x'), isNull);
      // 检测失败（旧结果仍在、标着旧节点）：地图也不停在旧国家
      final failed = old.copyWith(infoFailed: true);
      final place = museResolveExitPlace(nodeName: '🇳🇱 荷兰', measuredRegion: museExitRegionFor(failed, '🇳🇱 荷兰'));
      expect(place.city!.region, 'NL');
      expect(place.source, MuseExitSource.byName);
      // 测出来与节点名不同：以实测校正
      const got = MuseExitResult(info: MuseExitInfo(ip: '1.1.1.1', country: 'DE'), node: '🇳🇱 荷兰');
      expect(museResolveExitPlace(nodeName: '🇳🇱 荷兰', measuredRegion: museExitRegionFor(got, '🇳🇱 荷兰')).city!.region, 'DE');
    });

    test('检测结果记下测的是哪个节点', () async {
      var node = 'A';
      final n = MuseExitNotifier(
        () => 0,
        nodeOf: () => node,
        network: () async => '',
        fetch: (start, set) async => const MuseExitResult(info: MuseExitInfo(ip: '1.1.1.1', country: 'JP')),
      );
      await n.check();
      expect(n.state!.node, 'A');
      node = 'B';
      expect(museExitRegionFor(n.state, node), isNull);
      n.dispose();
    });

    test('首页地图读出口结果时带上当前节点', () {
      final src = File('lib/features/muse/home/route_card.dart').readAsStringSync();
      expect('museExitRegionFor(r, group?.selected)'.allMatches(src).length, 2);
      expect(museHeroMapHeight(372), MuseHomeA.mapMin);
    });
  });
}
