// 穿云 1.20.0 首页方向 A（连接卡 + 地图融合）：中性连接卡、地图做卡底（未连接整幅世界全灰无弧线；已连接按本机 +
// 节点所在国家取景、只有该国点阵变已连接色）、换节点取景一次性过渡 ≤ 300ms、关闭动效直接到位、无常驻动画、
// 国家查表（1.20.1 起 Natural Earth 1:50m）与香港 / 新加坡回退、数字与单位分开、系统大字号不溢出、电脑版同一张卡。
// Part of 穿云 (GPLv3).
import 'dart:io';
import 'dart:math' as math;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart';
import 'package:hiddify/features/muse/home/route_map/route_countries.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_motion_widgets.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

class _Exit extends MuseExitNotifier {
  _Exit(MuseExitResult? r) : super(() => 0) {
    state = r;
  }
}

class _Reach extends MuseReachNotifier {
  _Reach() : super(() => 0) {
    state = MuseReach.ok;
  }
}

OutboundInfo _node(String tag, String type, int delay) =>
    OutboundInfo(tag: tag, tagDisplay: tag, type: type, urlTestDelay: delay);

OutboundGroup _group(String selected) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: selected,
  selectable: true,
  items: [
    _node('🇯🇵 东京 02', 'vless', 86),
    _node('🇺🇸 洛杉矶 01', 'hysteria2', 173),
    _node('🇩🇪 法兰克福 01', 'shadowsocks', 238),
    _node('🇭🇰 香港 01 · 一个很长很长的节点名字用来测试大字号下的省略', 'vless', 42),
  ],
);

MuseWorldDots? _dots;

MuseWorldDots _loadDots() =>
    _dots ??= MuseWorldDots.parse(File('assets/map/world_dots.bin').readAsBytesSync())!;

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  bool connected = true,
  String node = '🇯🇵 东京 02',
  String exit = 'JP',
  Size size = const Size(400, 1400),
  double textScale = 1,
  bool dark = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => sp),
      museConnectionProvider.overrideWithValue(AsyncData(connected ? const Connected() : const Disconnected())),
      museConnectPreparingProvider.overrideWith((ref) => false),
      museRunningProvider.overrideWithValue(connected),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('一个名字很长很长的机场订阅（备用线路）'),
      museAppVersionProvider.overrideWithValue(null),
      museSubInfoProvider.overrideWithValue(
        SubscriptionInfo(upload: 1, download: 2, total: 120 << 30, expire: DateTime(2027)),
      ),
      museStatsProvider.overrideWithValue(
        SystemInfo(uplink: Int64(1024), downlink: Int64(2048), uplinkTotal: Int64(1), downlinkTotal: Int64(2)),
      ),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group(node))),
      museConnectedSinceProvider.overrideWith((ref) => connected ? DateTime.now() : null),
      museExitProvider.overrideWith(
        (ref) => _Exit(MuseExitResult(info: MuseExitInfo(ip: '45.76.112.9', country: exit))),
      ),
      museReachProvider.overrideWith((ref) => _Reach()),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const MuseHomePage(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 3));
  return container;
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// A map on its own (the card's settings), [connected] to [exit].
Widget _map({required bool connected, required MuseExitPlace exit, String? region, bool reduce = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: const Size(380, 800), disableAnimations: reduce),
    child: Scaffold(
      body: SizedBox(
        width: 380,
        child: MuseRouteMap(
          connected: connected,
          exit: exit,
          dots: _loadDots(),
          height: museHeroMapHeight(380),
          showCaption: false,
          centerLon: MuseHomeA.centerLon,
          fit: true,
          highlightRegion: region,
          look: MuseMapLook.card,
        ),
      ),
    ),
  ),
);

MuseExitPlace _place(String node, String region) =>
    museResolveExitPlace(nodeName: node, measuredRegion: region);

bool _inView(MuseMapView v, MuseGeoPoint p) {
  final lon = museWrapLon(p.lon, center: v.center);
  return p.lat <= v.north && p.lat >= v.south && (lon - v.center).abs() <= v.span / 2;
}

void main() {
  group('国家查表（Natural Earth 1:50m，公有领域；1.20.0 为 1:110m）', () {
    test('美国、日本、德国都有点；美国最多；中国保持中性不进高亮', () {
      final dots = _loadDots();
      final us = museRegionCells(dots, 'US');
      final jp = museRegionCells(dots, 'jp');
      final de = museRegionCells(dots, 'DE');
      expect(us.length, greaterThan(200));
      expect(jp, isNotEmpty);
      expect(de, isNotEmpty);
      // every cell is a land cell of the grid
      for (final i in [...us, ...jp, ...de]) {
        expect(dots.isLand(i ~/ dots.width, i % dots.width), isTrue);
      }
      // the cells of 日本 lie around Japan
      for (final i in jp) {
        final p = dots.cellCenter(i ~/ dots.width, i % dots.width);
        expect(p.lat, inInclusiveRange(24, 46));
        expect(p.lon, inInclusiveRange(122, 150));
      }
      expect(museDotCountryCells.length, greaterThan(150));
    });

    // 1.20.1：数据换成 1:50m，香港、新加坡有了自己的底图格（原断言「表里没有 HK / SG」删去）；表里没有的地区仍回退到
    // 出口城市附近的陆地点
    test('香港、新加坡在 1:50m 表里有格；表里没有的地区回退到出口城市附近的陆地点', () {
      final dots = _loadDots();
      expect(museDotCountryCells['HK'], isNotEmpty);
      expect(museDotCountryCells['SG'], isNotEmpty);
      const city = MuseCity('测试', 'ZZ', 22.32, 114.17);
      final cells = museRegionCells(dots, 'ZZ', near: city.point);
      expect(cells, isNotEmpty);
      for (final i in cells) {
        final p = dots.cellCenter(i ~/ dots.width, i % dots.width);
        expect((p.lat - city.lat).abs(), lessThanOrEqualTo(MuseHomeA.nearCityDeg));
      }
      expect(identical(museRegionCells(dots, 'ZZ', near: city.point), cells), isTrue);
      expect(museRegionCells(dots, 'ZZ'), isEmpty);
    });

    // 1.20.3: 关于 › 开源许可 no longer has the 致谢 group; the data source stays written in the table and the script
    test('生成脚本与数据来源写明公有领域（1.20.3：关于页不再致谢）', () {
      expect(_src('tool/world_dots/gen_dot_countries.py'), contains('Public Domain'));
      final table = _src('lib/features/muse/home/route_map/route_countries.dart');
      expect(table, contains('Natural Earth'));
      expect(table, contains('公有领域'));
      final about = _src('lib/features/about/widget/open_source_page.dart');
      expect(about, isNot(contains("ValueKey('about_credit_map')")));
    });
  });

  group('取景', () {
    test('已连接取景把本机、节点所在国家和整条弧都框进来，跨度不小于下限', () {
      final dots = _loadDots();
      const size = Size(380, 148);
      for (final (node, region) in [('🇯🇵 东京 02', 'JP'), ('🇺🇸 洛杉矶 01', 'US'), ('🇩🇪 法兰克福 01', 'DE')]) {
        final city = _place(node, region).city!;
        final cells = museRegionCells(dots, region);
        final pts = [
          for (final i in cells) dots.cellCenter(i ~/ dots.width, i % dots.width),
          ...museGreatCircle(museHomeCity.point, city.point, n: 24),
        ];
        final v = museFitView(
          size,
          museHomeCity.point,
          pts,
          topShare: MuseHomeA.fitTop,
          fill: MuseHomeA.fitFill,
          minSpan: MuseHomeA.fitMinSpan,
        );
        expect(v.span, inInclusiveRange(MuseHomeA.fitMinSpan, 360), reason: region);
        expect(_inView(v, museHomeCity.point), isTrue, reason: region);
        expect(_inView(v, city.point), isTrue, reason: region);
        // the aspect is kept: latitude span / longitude span = height / width
        expect((v.north - v.south) / v.span, closeTo(size.height / size.width, 1e-9));
      }
    });

    test('取景插值：两端就是两个取景，中途跨度在两者之间', () {
      const a = MuseMapView(80, -40, 150, 360);
      const b = MuseMapView(50, 20, 130, 80);
      expect(museViewLerp(a, b, 0), a);
      expect(museViewLerp(a, b, 1), b);
      final m = museViewLerp(a, b, 0.5);
      expect(m.span, inExclusiveRange(80, 360));
      expect(m.center, inExclusiveRange(130, 150));
      // the centre goes the short way round (170° → -170° passes 180°, not 0°)
      final w = museViewLerp(const MuseMapView(50, 20, 170, 80), const MuseMapView(50, 20, -170, 80), 0.5);
      expect(museWrapLon(w.center), closeTo(180, 1e-6));
    });

    test('地图高度随卡宽，夹在 148–220', () {
      expect(museHeroMapHeight(320), MuseHomeA.mapMin);
      expect(museHeroMapHeight(380), MuseHomeA.mapMin);
      expect(museHeroMapHeight(520), closeTo(200, 0.01));
      expect(museHeroMapHeight(1200), MuseHomeA.mapMax);
    });
  });

  group('地图动效', () {
    testWidgets('未连接：整幅世界、无高亮、不出帧；连上后取景过渡 ≤ 300ms，结束后无帧', (tester) async {
      final jp = _place('🇯🇵 东京 02', 'JP');
      await tester.pumpWidget(_map(connected: false, exit: jp, region: 'JP'));
      await tester.pump();
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      expect(s.view!.span, 360);
      expect(s.view!.center, MuseHomeA.centerLon);
      expect(s.animating, isFalse);
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);

      await tester.pumpWidget(_map(connected: true, exit: jp, region: 'JP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.view!.span, inExclusiveRange(MuseHomeA.fitMinSpan - 1, 360));
      // the reframe itself is done within 300 ms (the arc draws on its own, longer)
      expect(MuseRouteMotion.view.inMilliseconds, lessThanOrEqualTo(300));
      await tester.pump(const Duration(milliseconds: 200));
      final framed = s.view!;
      await tester.pumpAndSettle();
      expect(s.view, framed);
      expect(s.animating, isFalse);
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    });

    testWidgets('换节点（日本 → 美国）：取景平移缩放过渡，不跳；中途是两者之间', (tester) async {
      final jp = _place('🇯🇵 东京 02', 'JP');
      final us = _place('🇺🇸 洛杉矶 01', 'US');
      await tester.pumpWidget(_map(connected: true, exit: jp, region: 'JP'));
      await tester.pumpAndSettle();
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      final a = s.view!;
      await tester.pumpWidget(_map(connected: true, exit: us, region: 'US'));
      // the first frame after the switch still shows where it was (no jump)
      expect(s.view, a);
      await tester.pump(const Duration(milliseconds: 120));
      final mid = s.view!;
      expect(s.animating, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      final b = s.view!;
      expect(mid.span, inExclusiveRange(math.min(a.span, b.span) - 1e-6, math.max(a.span, b.span) + 1e-6));
      expect(mid == a || mid == b, isFalse);
      // during the move the dots are drawn straight; at rest the pre-rendered image is back
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('muse_route_base')), findsOneWidget);
      expect(find.byKey(const ValueKey('muse_route_base_moving')), findsNothing);
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    });

    testWidgets('减少动效（系统移除动画）：取景与高亮直接到位，没有一帧动画', (tester) async {
      final jp = _place('🇯🇵 东京 02', 'JP');
      final us = _place('🇺🇸 洛杉矶 01', 'US');
      await tester.pumpWidget(_map(connected: true, exit: jp, region: 'JP', reduce: true));
      await tester.pump();
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      await tester.pumpWidget(_map(connected: true, exit: us, region: 'US', reduce: true));
      await tester.pump();
      expect(s.animating, isFalse);
      final b = s.view!;
      expect(_inView(b, us.city!.point), isTrue);
      await tester.pumpWidget(_map(connected: false, exit: us, region: 'US', reduce: true));
      await tester.pump();
      expect(s.animating, isFalse);
      expect(s.view!.span, 360);
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    });

    test('没有循环动画、没有计时器', () {
      for (final p in [
        'lib/features/muse/home/route_card.dart',
        'lib/features/muse/home/route_map/muse_route_map.dart',
        'lib/features/muse/widget/muse_tokens_home.dart',
      ]) {
        final s = _src(p);
        expect(s, isNot(contains('repeat(')), reason: p);
        expect(s, isNot(contains('Timer.periodic')), reason: p);
        expect(s, isNot(contains('Timer(')), reason: p);
      }
    });
  });

  group('连接卡', () {
    testWidgets('新首页：地图在连接卡里（状态之下、节点行之上），没有单独的路由卡', (tester) async {
      await _pumpHome(tester);
      final card = find.byKey(const ValueKey('home_connect_section'));
      expect(find.descendant(of: card, matching: find.byType(MuseRouteMap)), findsOneWidget);
      expect(find.byKey(const ValueKey('home_route_card')), findsNothing);
      final map = tester.getRect(find.byKey(const ValueKey('home_hero_map')));
      expect(map.top, greaterThan(tester.getRect(find.byKey(const ValueKey('home_status_block'))).bottom - 1));
      expect(map.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('home_current_node'))).top + 1));
      // the 1.19 caption 「上海 → 东京 · 实测 · 86 ms」 repeated the node row: gone
      expect(find.byKey(const ValueKey('muse_route_caption')), findsNothing);
      // the node's country is lit, the view framed on it
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      expect(s.widget.highlightRegion, 'JP');
      expect(s.view!.span, lessThan(360));
      await _done(tester);
    });

    testWidgets('未连接：整幅世界、无弧线、▶；经典首页：连接卡没有地图', (tester) async {
      await _pumpHome(tester, connected: false);
      final s = tester.state<MuseRouteMapState>(find.byType(MuseRouteMap));
      expect(s.view!.span, 360);
      expect(find.widgetWithText(MuseSweep, '未连接'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
      await _done(tester);
      await _pumpHome(tester, prefs: {'muse_home_style': 'classic'});
      expect(find.byType(MuseRouteMap), findsNothing);
      expect(find.byKey(const ValueKey('home_connect_switch')), findsOneWidget);
      await _done(tester);
    });

    testWidgets('卡片中性：已连接时连接卡与下方卡片同一底色；连接钮 56 圆形', (tester) async {
      await _pumpHome(tester);
      final ctx = tester.element(find.byKey(const ValueKey('home_connect_section')));
      final mt = MuseTheme.of(ctx);
      final hero = tester.widget<DecoratedBox>(find.byKey(const ValueKey('home_hero_card')));
      expect((hero.decoration as BoxDecoration).color, mt.card);
      expect((hero.decoration as BoxDecoration).borderRadius, MuseHomeA.cardAll);
      expect(tester.getSize(find.byKey(const ValueKey('home_connect_shape'))), const Size.square(MuseHomeA.button));
      final shape = tester.widget<DecoratedBox>(find.byKey(const ValueKey('home_connect_shape')));
      // 1.21.0 M3：已连接是圆角方形（未连接是圆）
      expect((shape.decoration as ShapeDecoration).shape, isA<RoundedSuperellipseBorder>());
      expect(find.byIcon(Icons.pause_outlined), findsOneWidget);
      await _done(tester);
    });

    for (final scale in [1.3, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('系统大字号 ${scale}x${dark ? '（深色）' : ''}：360 宽不溢出，连接卡与下方卡片随内容长高', (tester) async {
          await _pumpHome(tester, textScale: scale, dark: dark, size: const Size(360, 2400));
          expect(tester.takeException(), isNull);
          final status = tester.getRect(find.byKey(const ValueKey('home_status_block')));
          final card = tester.getRect(find.byKey(const ValueKey('home_connect_section')));
          expect(status.bottom, lessThanOrEqualTo(card.bottom));
          // the tile row grows with the text instead of a fixed 124
          final tile = tester.getSize(find.byKey(const ValueKey('tile_traffic')));
          expect(tile.height, greaterThanOrEqualTo(museTileHeightFor(TextScaler.linear(scale)) - 0.5));
          await _done(tester);
          await _pumpHome(tester, textScale: scale, dark: dark, connected: false, size: const Size(360, 2400));
          expect(tester.takeException(), isNull);
          await _done(tester);
        });
      }
    }

    testWidgets('电脑版：800 / 880 / 1280 宽都是同一张融合连接卡（左栏），没有单独路由卡', (tester) async {
      for (final w in [800.0, 880.0, 1280.0]) {
        await _pumpHome(tester, size: Size(w, 900));
        expect(tester.takeException(), isNull, reason: '$w');
        final card = find.byKey(const ValueKey('home_connect_section'));
        expect(find.descendant(of: card, matching: find.byType(MuseRouteMap)), findsOneWidget, reason: '$w');
        expect(find.byKey(const ValueKey('home_route_card')), findsNothing);
        if (w >= MuseDesk.twoColumn) {
          expect(find.descendant(of: find.byKey(const ValueKey('home_desk_left')), matching: card), findsOneWidget);
        }
        await _done(tester);
      }
    });
  });

  group('数字与单位', () {
    test('拆出箭头、数字、单位；没有数字的值整段是值', () {
      expect(museSplitValue('↓ 2.0 KB/s'), ('↓', '2.0', 'KB/s'));
      expect(museSplitValue('87.0 GB'), (null, '87.0', 'GB'));
      expect(museSplitValue('28 天'), (null, '28', '天'));
      expect(museSplitValue('0 B'), (null, '0', 'B'));
      expect(museSplitValue('已用完'), (null, '已用完', null));
      expect(museSplitValue('检测中'), (null, '检测中', null));
      expect(museSplitValue('45.76.*.*'), (null, '45.76.*.*', null));
      expect(museSplitValue('—'), (null, '—', null));
      expect(museSplitValue('🇯🇵 东京 02'), (null, '🇯🇵 东京 02', null));
      expect(museSplitValue('192.168.1.23'), (null, '192.168.1.23', null));
      expect(museSplitValue('64.0 MB'), (null, '64.0', 'MB'));
      expect(museSplitValue('1,284 个'), (null, '1,284', '个'));
    });

    testWidgets('卡片数值：数字等宽，单位小一号、次要色，中间是不换行空格', (tester) async {
      await _pumpHome(tester);
      // 剩余流量 ≈ 120 GB
      final rich = find.byWidgetPredicate(
        (w) => w is RichText && RegExp(r'^\d+(\.\d+)?\u00A0GB$').hasMatch(w.text.toPlainText()),
      );
      expect(rich, findsWidgets);
      final parts = <TextSpan>[];
      tester.widget<RichText>(rich.first).text.visitChildren((sp) {
        if (sp is TextSpan && sp.text != null) parts.add(sp);
        return true;
      });
      final number = parts.firstWhere((p) => RegExp(r'^\d').hasMatch(p.text ?? '')).style!;
      final unit = parts.firstWhere((p) => p.text == '\u00A0GB').style!;
      expect(number.fontFeatures, MuseType.tabular);
      expect(number.fontSize, MuseHomeA.value);
      expect(unit.fontSize, MuseHomeA.unit);
      expect(unit.color, isNot(number.color));
      await _done(tester);
    });
  });

  group('令牌', () {
    test('圆角 20 / 12 / 8、4 / 8 间距、56 圆钮；数值都在令牌文件里', () {
      expect(MuseHomeA.radiusCard, 20);
      expect(MuseHomeA.radiusPanel, 12);
      expect(MuseHomeA.radiusControl, 8);
      expect(MuseHomeA.button, 56);
      for (final v in [MuseHomeA.pad, MuseHomeA.padDesk, MuseHomeA.gap, MuseHomeA.nodeRowTop, MuseHomeA.nodeRowBottom]) {
        expect(v % 4, 0, reason: '$v');
      }
      expect(MuseRouteMotion.view.inMilliseconds, lessThanOrEqualTo(300));
      expect(MuseRouteMotion.highlight.inMilliseconds, lessThanOrEqualTo(300));
    });

    test('原型开关都已去掉', () {
      for (final p in [
        'lib/features/muse/home/muse_home_page.dart',
        'lib/features/muse/home/route_card.dart',
        'lib/features/muse/home/route_map/muse_route_map.dart',
        'lib/features/muse/home/route_map/route_geo.dart',
      ]) {
        final s = _src(p);
        for (final w in ['museProto', 'PROTO_', 'MuseProtoMap', '原型']) {
          expect(s, isNot(contains(w)), reason: '$p $w');
        }
      }
      expect(File('lib/features/muse/home/proto_v3.dart').existsSync(), isFalse);
    });
  });
}
