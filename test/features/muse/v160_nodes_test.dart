// 穿云 1.6.0 (batch 2, nodes A): #28 按协议筛选, #29 延迟迷你折线, #32 手动指定地区,
// #33 本地标签 + 按标签筛选, #37 最近使用快速切回, #39 非常用地区默认折叠.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

OutboundInfo _n(String tag, String type) => OutboundInfo(tag: tag, tagDisplay: tag, type: type);

final _group = OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '🇯🇵 东京 02',
  selectable: true,
  items: [
    _n('🇯🇵 东京 02', 'vless'),
    _n('🇭🇰 香港 01', 'hysteria2'),
    _n('🇸🇬 新加坡 03', 'trojan'),
    _n('🇺🇸 洛杉矶 01', 'vless'),
    _n('🇩🇪 法兰克福 01', 'shadowsocks'),
    _n('🇬🇧 伦敦 01', 'trojan'),
    _n('Relay A', 'vless'),
  ],
);

Future<ProviderContainer> _pump(WidgetTester tester, {Map<String, Object> prefs = const {}, Size size = const Size(412, 900), double scale = 1}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      museRunningProvider.overrideWithValue(true),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('机场'),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
      museActiveConfigProvider.overrideWith((ref) async => ''),
      museConnectedSinceProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(c.dispose);
  await tester.runAsync(() => c.read(sharedPreferencesProvider.future));
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: const Scaffold(body: MuseNodeList()),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return c;
}

void main() {
  group('logic', () {
    test('#32 / #33 meta: region and tags survive a round trip, old metas still read', () {
      final m = const MuseNodeMeta().copyWith(region: 'jp', tags: [' 家宽 ', '游戏', '家宽', '']);
      expect(m.region, 'JP');
      expect(m.tags, ['家宽', '游戏']);
      final metas = MuseNodeMetas.empty.set('a', m);
      final back = MuseNodeMetas.parse(metas.toRaw());
      expect(back.of('a'), m);
      expect(MuseNodeMetas.parse('{"b":{"n":"x"}}').of('b').tags, isEmpty);
      expect(back.regionOf('a', 'HK'), 'JP');
      expect(back.regionOf('zz', 'HK'), 'HK');
      expect(back.set('a', const MuseNodeMeta()).byTag, isEmpty);
      final more = back.set('c', const MuseNodeMeta(tags: ['低倍率', '流媒体']));
      expect(more.allTags, ['家宽', '流媒体', '游戏', '低倍率']);
      expect(museCleanNodeTags(['一二三四五六七八九十一二三四']).single.length, 12);
      expect(museCleanNodeTags([for (var i = 0; i < 20; i++) 't$i']).length, 8);
    });

    test('#28 / #33 filter', () {
      final p = MuseNodeFilter.parse('p:VLESS');
      expect(p.passes(protocolShort: 'VLESS', tags: const []), isTrue);
      expect(p.passes(protocolShort: 'HY2', tags: const []), isFalse);
      final t = MuseNodeFilter.parse(MuseNodeFilter.tag('家宽').toRaw());
      expect(t.passes(protocolShort: 'HY2', tags: const ['家宽']), isTrue);
      expect(t.passes(protocolShort: 'HY2', tags: const []), isFalse);
      expect(MuseNodeFilter.parse('').isNone, isTrue);
      expect(MuseNodeFilter.parse('vless'), MuseNodeFilter.protocol('VLESS'));
      // a protocol / tag that is gone filters nothing
      expect(p.within(protocols: ['HY2'], tags: const []).isNone, isTrue);
      expect(t.within(protocols: ['HY2'], tags: const ['家宽']), t);
      expect(museProtocolsPresent(['VLESS', 'HY2', '', 'VLESS', 'SS']), ['VLESS', 'HY2', 'SS']);
    });

    test('#29 sparkline', () {
      expect(museSparkline([100, 200]), [0.15, 1.0]);
      expect(museSparkline([100, 0, 100]), [0.5, null, 0.5]);
      expect(museSparkline([0, 65535]), [null, null]);
      expect(museSparkline([for (var i = 1; i <= 20; i++) i * 10]).length, 10);
    });

    test('#37 recent', () {
      final raw = museRecentToRaw(museAddRecent(museRecentFromRaw(''), 'a,b'));
      expect(museRecentFromRaw(raw), ['a,b']);
      expect(museRecentFromRaw('x, y'), ['x', 'y']);
      expect(museRecentFromRaw('[broken'), isEmpty);
      expect(museRecentToOffer(['a', 'b', 'gone', 'c'], present: ['a', 'b', 'c'], selected: 'a'), ['b', 'c']);
      expect(museRecentToOffer([for (var i = 0; i < 9; i++) '$i'], present: [for (var i = 0; i < 9; i++) '$i'], selected: '').length, 5);
    });

    test('#39 folding', () {
      const none = <String>{};
      expect(museRegionFolded('DE', none, regionCount: 6), isTrue);
      expect(museRegionFolded('JP', none, regionCount: 6), isFalse);
      expect(museRegionFolded('DE', none, regionCount: 3), isFalse);
      expect(museRegionFolded('DE', none, regionCount: 6, selectedRegion: 'DE'), isFalse);
      expect(museRegionFolded('other', none, regionCount: 6), isTrue);
      final opened = museToggleRegionFold(none, 'DE', folded: true);
      expect(opened, {'+DE'});
      expect(museRegionFolded('DE', opened, regionCount: 6), isFalse);
      final closed = museToggleRegionFold(opened, 'DE', folded: false);
      expect(closed, {'DE'});
      expect(museRegionFolded('JP', museToggleRegionFold(none, 'JP', folded: false), regionCount: 6), isTrue);
    });
  });

  group('node list', () {
    testWidgets('#28 protocol filter narrows the list and says so', (tester) async {
      final c = await _pump(tester);
      expect(find.byKey(const ValueKey('node_filter_button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('node_filter_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('node_filter_p_VLESS')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('node_filter_p_Trojan')));
      await tester.pumpAndSettle();
      expect(c.read(MusePrefs.protocolFilter), 'p:Trojan');
      expect(find.textContaining('仅Trojan'), findsOneWidget);
      expect(find.byKey(const ValueKey('🇸🇬 新加坡 03')), findsOneWidget);
      expect(find.byKey(const ValueKey('🇭🇰 香港 01')), findsNothing);
      // the node in use always stays
      expect(find.byKey(const ValueKey('🇯🇵 东京 02')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('#33 tag filter, #32 region set by hand moves the node into that region', (tester) async {
      final metas = MuseNodeMetas.empty
          .set('Relay A', const MuseNodeMeta(region: 'SG', tags: ['家宽']))
          .set('🇺🇸 洛杉矶 01', const MuseNodeMeta(tags: ['流媒体']));
      final c = await _pump(tester, prefs: {'muse_node_meta': metas.toRaw(), 'muse_protocol_filter': 't:家宽'});
      expect(find.byKey(const ValueKey('Relay A')), findsOneWidget);
      expect(find.byKey(const ValueKey('🇺🇸 洛杉矶 01')), findsNothing);
      expect(find.text('🇸🇬'), findsWidgets);
      await c.read(MusePrefs.protocolFilter.notifier).update('');
      await c.read(Preferences.museNodeSort.notifier).update('region');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('region_header_SG')), findsOneWidget);
      expect(find.textContaining('新加坡 · 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('#39 uncommon regions start folded, a tap opens and is remembered', (tester) async {
      final c = await _pump(tester, prefs: {'muse_node_sort': 'region'});
      // JP (in use) / HK / SG / US open; DE / GB / 其他 folded (6+ regions)
      expect(find.byKey(const ValueKey('🇭🇰 香港 01')), findsOneWidget);
      expect(find.byKey(const ValueKey('🇩🇪 法兰克福 01')), findsNothing);
      expect(find.byKey(const ValueKey('Relay A')), findsNothing);
      await tester.tap(find.textContaining('德国'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(MusePrefs.collapsedRegions), '+DE');
      expect(find.byKey(const ValueKey('🇩🇪 法兰克福 01')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('#37 recent row (${scale}x)', (tester) async {
        await _pump(
          tester,
          prefs: {'muse_recent_nodes': museRecentToRaw(['🇯🇵 东京 02', '🇭🇰 香港 01', 'gone', 'Relay A'])},
          size: scale == 1 ? const Size(412, 900) : const Size(320, 900),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('node_recent_row')), findsOneWidget);
        expect(find.byKey(const ValueKey('node_recent_🇭🇰 香港 01')), findsOneWidget);
        expect(find.byKey(const ValueKey('node_recent_Relay A')), findsOneWidget);
        // the node in use and nodes no longer in the list are not offered
        expect(find.byKey(const ValueKey('node_recent_🇯🇵 东京 02')), findsNothing);
        expect(find.byKey(const ValueKey('node_recent_gone')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('widgets', () {
    for (final dark in [false, true]) {
      testWidgets('#29 sparkline paints (dark=$dark)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
            home: Scaffold(body: MuseSparkline(points: museSparkline([120, 0, 90, 300, 85]))),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('node_sparkline')), findsOneWidget);
      });
    }

    testWidgets('#32 row flag follows the region set by hand', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MuseNodeRow(proxy: _n('Relay A', 'vless'), since: null, nodeCount: 3, selected: false, onTap: () {}, region: 'JP'),
          ),
        ),
      );
      expect(find.text('🇯🇵'), findsOneWidget);
      expect(find.byKey(const ValueKey('flag_box_neutral')), findsNothing);
    });

    testWidgets('#32 region dialog / #33 tag dialog return the choice', (tester) async {
      String? region;
      List<String>? tags;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Column(
              children: [
                TextButton(onPressed: () async => region = await museAskRegion(context, current: 'HK'), child: const Text('r')),
                TextButton(onPressed: () async => tags = await museAskNodeTags(context, current: const ['游戏'], known: const ['低倍率']), child: const Text('t')),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('r'));
      await tester.pumpAndSettle();
      expect(find.textContaining('（当前）'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('node_region_auto')));
      await tester.pumpAndSettle();
      expect(region, '');

      await tester.tap(find.text('t'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('node_tag_家宽')), findsOneWidget);
      expect(find.byKey(const ValueKey('node_tag_低倍率')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('node_tag_家宽')));
      await tester.enterText(find.byKey(const ValueKey('node_tag_new')), '晚高峰稳');
      await tester.tap(find.byKey(const ValueKey('node_tag_add')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('node_tags_save')));
      await tester.pumpAndSettle();
      expect(tags, ['家宽', '游戏', '晚高峰稳']);
    });
  });
}
