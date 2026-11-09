// 穿云 1.19.0 第 2 段：新首页（顶部路由弧线图）/ 经典首页开关、分类线（线宽随流量占比，无数据只画主弧线）、
// 不新增轮询或计时器。
// Part of 穿云 (GPLv3).
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/home/route_map/route_share.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';
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

class _History extends MuseSpeedHistory {
  _History(this.values);

  final List<int> values;

  @override
  List<int> build() => values;
}

OutboundInfo _node(String tag, String type, int delay) =>
    OutboundInfo(tag: tag, tagDisplay: tag, type: type, urlTestDelay: delay);

final _group = OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '🇯🇵 东京 02',
  selectable: true,
  items: [_node('🇯🇵 东京 02', 'vless', 86), _node('🇭🇰 香港 01', 'hysteria2', 42)],
);

MuseConn _conn(String id, String host, int bytes, {List<String> chains = const ['🇯🇵 东京 02'], String process = ''}) =>
    MuseConn(
      id: id,
      host: host,
      destination: '1.2.3.4:443',
      network: 'tcp',
      inbound: 'tun',
      chains: chains,
      rule: '',
      process: process,
      upload: 0,
      download: bytes,
      start: DateTime(2026, 11, 9),
    );

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  bool connected = true,
  List<int>? history,
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
      museActiveProfileNameProvider.overrideWithValue('机场订阅'),
      museAppVersionProvider.overrideWithValue(null),
      museSubInfoProvider.overrideWithValue(
        SubscriptionInfo(upload: 1, download: 2, total: 1024 * 1024 * 1024, expire: DateTime(2027)),
      ),
      museStatsProvider.overrideWithValue(
        SystemInfo(uplink: Int64(1024), downlink: Int64(2048), uplinkTotal: Int64(1), downlinkTotal: Int64(2)),
      ),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
      museConnectedSinceProvider.overrideWith((ref) => connected ? DateTime.now() : null),
      museExitProvider.overrideWith(
        (ref) => _Exit(
          const MuseExitResult(
            info: MuseExitInfo(ip: '45.76.112.9', country: 'JP'),
          ),
        ),
      ),
      museReachProvider.overrideWith((ref) => _Reach()),
      if (history != null) museSpeedHistoryProvider.overrideWith(() => _History(history)),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  tester.view.physicalSize = const Size(400, 1600) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MuseHomePage()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  // 底图从资源读入
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 3));
  return container;
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// 经典首页（1.18）的关键元素
void _expectClassicCore() {
  expect(find.byKey(const ValueKey('home_connect_section')), findsOneWidget);
  expect(find.byKey(const ValueKey('home_connect_switch')), findsOneWidget);
  expect(find.byKey(const ValueKey('home_mode_pill')), findsOneWidget);
  expect(find.byKey(const ValueKey('home_timer')), findsOneWidget);
  expect(find.byType(MuseTileGrid), findsOneWidget);
  expect(find.byKey(const ValueKey('home_edit_tiles')), findsOneWidget);
  expect(find.textContaining('东京'), findsWidgets);
}

void main() {
  group('首页样式开关', () {
    testWidgets('默认新首页：顶部路由图 + 经典首页的全部功能', (tester) async {
      final c = await _pumpHome(tester);
      expect(c.read(MusePrefs.homeStyle), 'new');
      expect(find.byKey(const ValueKey('home_route_card')), findsOneWidget);
      expect(find.byType(MuseRouteMap), findsOneWidget);
      // 路由图在连接卡上方
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('home_route_card'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('home_connect_section'))).dy),
      );
      // 出口 IP 检测实测 JP + 节点名东京 → 东京（实测）
      // 1.19.1 A3：图注末尾加当前节点延迟（「 · 86 ms」），前半句不变
      expect(find.textContaining(RegExp(r'^上海 → 东京 · 实测( · \d+ ms)?$')), findsOneWidget);
      _expectClassicCore();
      await _done(tester);
    });

    testWidgets('经典首页：没有路由图，1.18 首页的关键元素都在', (tester) async {
      await _pumpHome(tester, prefs: {'muse_home_style': 'classic'});
      expect(find.byKey(const ValueKey('home_route_card')), findsNothing);
      expect(find.byType(MuseRouteMap), findsNothing);
      _expectClassicCore();
      await _done(tester);
    });

    testWidgets('切换后两种首页都能渲染', (tester) async {
      final c = await _pumpHome(tester);
      expect(find.byKey(const ValueKey('home_route_card')), findsOneWidget);
      await c.read(MusePrefs.homeStyle.notifier).update('classic');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('home_route_card')), findsNothing);
      _expectClassicCore();
      await c.read(MusePrefs.homeStyle.notifier).update('new');
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('home_route_card')), findsOneWidget);
      _expectClassicCore();
      await _done(tester);
    });

    testWidgets('未连接：路由图显示「未连接」，不画弧线', (tester) async {
      await _pumpHome(tester, connected: false);
      expect(find.byKey(const ValueKey('home_route_card')), findsOneWidget);
      expect(find.text('未连接'), findsWidgets);
      expect(find.byKey(const ValueKey('home_route_legend')), findsNothing);
      await _done(tester);
    });

    test('外观里有「首页样式」，默认新首页，可在设置搜索里找到', () {
      final page = _src('lib/features/muse/settings/appearance_page.dart');
      expect(page, contains("ValueKey('appearance_home_style')"));
      expect(page, contains("('new', '新首页'), ('classic', '经典首页')"));
      expect(_src('lib/features/muse/data/muse_prefs.dart'), contains('"muse_home_style", "new"'));
      final e = museSettingEntries.where((e) => e.title == '首页样式').single;
      expect(e.page, MuseSettingPage.appearance);
      expect(e.keywords, containsAll(['新首页', '经典首页']));
    });
  });

  group('分类线', () {
    test('按出站与域名/进程名里的通用词分类', () {
      expect(museRouteKindOf(_conn('1', 'api.example.ai', 1)), MuseRouteKind.ai);
      expect(museRouteKindOf(_conn('2', 'chat.example.com', 1)), MuseRouteKind.ai);
      expect(museRouteKindOf(_conn('3', 'video.example.com', 1)), MuseRouteKind.video);
      expect(museRouteKindOf(_conn('4', 'git.example.org', 1)), MuseRouteKind.dev);
      expect(museRouteKindOf(_conn('5', 'www.example.cn', 1, chains: const ['direct'])), MuseRouteKind.direct);
      expect(museRouteKindOf(_conn('6', 'www.example.com', 1)), isNull);
      expect(museRouteKindOf(_conn('7', '1.2.3.4', 1, process: '/usr/bin/terminal')), MuseRouteKind.dev);
    });

    test('占比按本次连接累计；只在整数百分比变化时更新；断开清零', () {
      final n = MuseRouteShareNotifier();
      expect(n.state.shares(), isEmpty);
      var updates = 0;
      n.addListener((_) => updates++, fireImmediately: false);
      n.frame([_conn('a', 'api.x.ai', 600), _conn('b', 'video.x.com', 300), _conn('c', 'www.x.com', 100)]);
      final s = n.state.shares();
      expect(s.first.$1, MuseRouteKind.ai);
      expect(s.first.$2, closeTo(0.6, 1e-9));
      expect(s[1].$2, closeTo(0.3, 1e-9));
      expect(updates, 1);
      // 同样的帧（字节没变）不更新
      n.frame([_conn('a', 'api.x.ai', 600), _conn('b', 'video.x.com', 300), _conn('c', 'www.x.com', 100)]);
      expect(updates, 1);
      n.reset();
      expect(n.state.total, 0);
      expect(n.state.shares(), isEmpty);
    });

    test('线宽随占比：0 → 1，1 → 6', () {
      expect(museRouteShareWidth(0), 1);
      expect(museRouteShareWidth(1), 6);
      expect(museRouteShareWidth(0.5), greaterThan(museRouteShareWidth(0.1)));
    });

    final dots = MuseWorldDots.parse(File('assets/map/world_dots.bin').readAsBytesSync())!;
    Widget map(List<(MuseRouteKind, double)> shares) => MaterialApp(
      home: MuseMotionScope(
        level: MuseMotionLevel.standard,
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: MuseRouteMap(
              connected: true,
              exit: museResolveExitPlace(nodeName: '日本 东京 01'),
              dots: dots,
              shares: shares,
            ),
          ),
        ),
      ),
    );

    testWidgets('无数据只画主弧线；有数据画分类线；动画结束后都不再出帧', (tester) async {
      await tester.pumpWidget(map(const []));
      await tester.pumpAndSettle();
      expect(tester.state<MuseRouteMapState>(find.byType(MuseRouteMap)).animating, isFalse);
      await tester.pumpWidget(map(const [(MuseRouteKind.ai, 0.5), (MuseRouteKind.direct, 0.2)]));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(SchedulerBinding.instance.hasScheduledFrame || tester.binding.transientCallbackCount > 0, isFalse);
    });

    testWidgets('首页分类线：连接列表喂过数据后显示图例，无数据时不显示', (tester) async {
      final c = await _pumpHome(tester);
      expect(find.byKey(const ValueKey('home_route_legend')), findsNothing);
      c.read(museRouteShareProvider.notifier).frame([_conn('a', 'api.x.ai', 700), _conn('b', 'www.x.com', 300)]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('home_route_legend')), findsOneWidget);
      expect(find.text('AI 70%'), findsOneWidget);
      await _done(tester);
    });
  });

  group('不新增轮询与计时器', () {
    test('新文件里没有 Timer.periodic、没有自己读接口', () {
      for (final p in [
        'lib/features/muse/home/route_card.dart',
        'lib/features/muse/home/route_map/route_share.dart',
        'lib/features/muse/home/route_map/muse_route_map.dart',
      ]) {
        final s = _src(p);
        expect(s, isNot(contains('Timer.periodic')), reason: p);
        expect(s, isNot(contains('Timer(')), reason: p);
        expect(s, isNot(contains('getJson(')), reason: p);
        expect(s, isNot(contains('.stream(')), reason: p);
        expect(s, isNot(contains('repeat(')), reason: p);
      }
    });

    test('分类数据只从已有的连接帧与统计读取处喂入', () {
      expect(
        _src('lib/features/muse/local_api/local_api_providers.dart'),
        contains('ref.read(museRouteShareProvider.notifier).frame(frame.connections);'),
      );
      expect(
        _src('lib/features/muse/data/app_traffic_recorder.dart'),
        contains('ref.read(museRouteShareProvider.notifier).frame(conns);'),
      );
      expect(
        _src('lib/features/muse/home/muse_home_page.dart').split('Timer.periodic').length,
        2,
        reason: '首页仍只有 1.6.1 已连接时长那一个计时器',
      );
    });
  });

  group('1.19.0 P4 一句话路由与按路由颜色的速度柱', () {
    test('一句话：各类取流量最多的出站，节点名换成城市名；有直连时说「其余直连」；无数据为 null', () {
      final n = MuseRouteShareNotifier();
      expect(museRouteSentence(n.state), isNull);
      n.frame([
        _conn('a', 'api.x.ai', 500, chains: const ['🇯🇵 东京 02', 'select']),
        _conn('b', 'video.x.com', 300, chains: const ['🇭🇰 香港 01', 'select']),
        _conn('c', 'video.y.com', 50, chains: const ['🇯🇵 东京 02', 'select']),
        _conn('d', 'www.x.cn', 150, chains: const ['direct']),
      ]);
      expect(n.state.nodes[MuseRouteKind.ai], '🇯🇵 东京 02');
      expect(n.state.nodes[MuseRouteKind.video], '🇭🇰 香港 01');
      expect(n.state.nodes.containsKey(MuseRouteKind.direct), isFalse);
      final s = museRouteSentence(n.state, place: (node) => museCityForNodeName(node)?.name);
      expect(s, 'AI 走 东京 · 视频 走 香港 · 其余直连');
      // 认不出城市时用节点名本身
      expect(museRouteSentence(n.state, place: (_) => null), startsWith('AI 走 🇯🇵 东京 02'));
      // 只有直连
      final d = MuseRouteShareNotifier()..frame([_conn('x', 'www.x.cn', 100, chains: const ['direct'])]);
      expect(museRouteSentence(d.state), '全部直连');
      // 主出站换了，签名跟着变（首页会重画）
      final before = n.state.signature;
      n.frame([_conn('e', 'api.y.ai', 5000, chains: const ['🇺🇸 洛杉矶 01'])]);
      expect(n.state.signature, isNot(before));
      expect(n.state.nodes[MuseRouteKind.ai], '🇺🇸 洛杉矶 01');
    });

    testWidgets('首页路由卡：无数据显示简短提示；有数据显示一句话', (tester) async {
      final c = await _pumpHome(tester);
      expect(find.text('有流量后显示各类流量走哪里'), findsOneWidget);
      c.read(museRouteShareProvider.notifier).frame([
        _conn('a', 'api.x.ai', 600),
        _conn('b', 'video.x.com', 300, chains: const ['🇭🇰 香港 01']),
        _conn('c', 'www.x.cn', 100, chains: const ['direct']),
      ]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('AI 走 东京 · 视频 走 香港 · 其余直连'), findsOneWidget);
      await _done(tester);
    });

    testWidgets('未连接时不显示一句话', (tester) async {
      await _pumpHome(tester, connected: false);
      expect(find.byKey(const ValueKey('home_route_sentence')), findsNothing);
      await _done(tester);
    });

    test('堆叠柱：各段按占比，剩余给主色，总高不变', () {
      final parts = MuseStackedBarsPainter.split(100, [0.5, 0.3]);
      expect(parts, [50, 30, 20]);
      expect(MuseStackedBarsPainter.split(10, [0.8, 0.8]).fold<double>(0, (a, b) => a + b), 10);
      expect(MuseStackedBarsPainter.split(10, const []), [10]);
    });

    testWidgets('新首页有分类数据时网速按路由颜色堆叠；无数据退回单色折线；经典首页不变', (tester) async {
      final h = [for (var i = 0; i < 12; i++) 2048 + i * 100];
      final c = await _pumpHome(tester, history: h);
      expect(find.byKey(const ValueKey('tile_speed')), findsOneWidget);
      expect(find.byKey(const ValueKey('speed_stacked_bars')), findsNothing);
      c.read(museRouteShareProvider.notifier).frame([_conn('a', 'api.x.ai', 700), _conn('b', 'www.x.com', 300)]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('speed_stacked_bars')), findsOneWidget);
      await c.read(MusePrefs.homeStyle.notifier).update('classic');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('speed_stacked_bars')), findsNothing);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });
  });
}
