// 穿云 1.6.0 C5 节点页: 列表 / 卡片 layout, 紧凑 / 标准 / 宽松, card columns, 滚动到当前节点.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/home/bad_nodes.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/node_style.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

OutboundInfo _n(String tag) => OutboundInfo(tag: tag, tagDisplay: tag, type: 'vless', host: '$tag.example.com', port: 443);

OutboundGroup _group(int count, {int selected = 0}) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '节点 $selected',
  selectable: true,
  items: [for (var i = 0; i < count; i++) _n('节点 $i')],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required OutboundGroup group,
  Map<String, Object> prefs = const {},
  Size size = const Size(412, 900),
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      museRunningProvider.overrideWithValue(true),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('机场'),
      museNodeGroupProvider.overrideWithValue(AsyncData(group)),
      museActiveConfigProvider.overrideWith((ref) async => ''),
      museConnectedSinceProvider.overrideWith((ref) async => null),
      museHiddenNodesProvider.overrideWith((ref) => const <String>{}),
    ],
  );
  addTearDown(c.dispose);
  await tester.runAsync(() => c.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => c.read(museActiveConfigProvider.future));
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
  group('C5 style logic', () {
    test('layout / density keys, unknown falls back', () {
      expect(MuseNodeLayout.fromKey('grid'), MuseNodeLayout.grid);
      expect(MuseNodeLayout.fromKey('x'), MuseNodeLayout.list);
      expect(MuseNodeDensity.fromKey('compact'), MuseNodeDensity.compact);
      expect(MuseNodeDensity.fromKey(''), MuseNodeDensity.standard);
      expect(MuseNodeDensity.compact.padV, lessThan(MuseNodeDensity.standard.padV));
      expect(MuseNodeDensity.loose.padV, greaterThan(MuseNodeDensity.standard.padV));
    });
    test('columns: one per 250 px (≥ 2), 紧凑 +1, 宽松 −1, never too narrow', () {
      expect(museNodeColumns(380, MuseNodeDensity.standard), 2);
      expect(museNodeColumns(1000, MuseNodeDensity.standard), 4);
      expect(museNodeColumns(1000, MuseNodeDensity.compact), 5);
      expect(museNodeColumns(1000, MuseNodeDensity.loose), 3);
      expect(museNodeColumns(1300, MuseNodeDensity.standard), 6);
      // 320 px phone: 紧凑 would be 3 × ~100 px → back to 2
      expect(museNodeColumns(320, MuseNodeDensity.compact), 2);
      // 2× text: wider cards
      expect(museNodeColumns(380, MuseNodeDensity.standard, textScale: 2), 1);
      expect(museNodeColumns(200, MuseNodeDensity.loose), 1);
    });
    test('card height grows with text and density', () {
      double one(double v) => v;
      double two(double v) => v * 2;
      expect(museNodeCardExtent(MuseNodeDensity.standard, two), greaterThan(museNodeCardExtent(MuseNodeDensity.standard, one)));
      expect(museNodeCardExtent(MuseNodeDensity.loose, one), greaterThan(museNodeCardExtent(MuseNodeDensity.compact, one)));
    });
    test('style settings sync', () {
      expect(museSyncedPrefs.keys, containsAll(['muse_node_layout', 'muse_node_density']));
      expect(MusePrefs.nodeLayout, isNotNull);
    });
  });

  group('C5 node page', () {
    testWidgets('卡片 layout: nodes as cards in a grid, built lazily', (tester) async {
      await _pump(tester, group: _group(1000), prefs: {'muse_node_layout': 'grid'}, size: const Size(1000, 800));
      expect(find.byKey(const ValueKey('node_card')), findsWidgets);
      final cards = find.byKey(const ValueKey('node_card')).evaluate().length;
      expect(cards, lessThan(120)); // not 1000
      // several cards share the first row
      final first = tester.getTopLeft(find.byKey(const ValueKey('节点 0'))).dy;
      expect(tester.getTopLeft(find.byKey(const ValueKey('节点 1'))).dy, first);
      expect(tester.takeException(), isNull);
    });

    testWidgets('列表 layout (default): no cards', (tester) async {
      await _pump(tester, group: _group(20));
      expect(find.byKey(const ValueKey('node_card')), findsNothing);
      final y0 = tester.getTopLeft(find.byKey(const ValueKey('节点 0'))).dy;
      expect(tester.getTopLeft(find.byKey(const ValueKey('节点 1'))).dy, greaterThan(y0));
    });

    testWidgets('样式 menu switches layout and density (saved)', (tester) async {
      final c = await _pump(tester, group: _group(20));
      final h0 = tester.getSize(find.byKey(const ValueKey('节点 0'))).height;
      await tester.tap(find.byKey(const ValueKey('node_style_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('node_density_compact')));
      await tester.pumpAndSettle();
      expect(c.read(MusePrefs.nodeDensity), 'compact');
      expect(tester.getSize(find.byKey(const ValueKey('节点 0'))).height, lessThan(h0));
      await tester.tap(find.byKey(const ValueKey('node_style_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('node_layout_grid')));
      await tester.pumpAndSettle();
      expect(c.read(MusePrefs.nodeLayout), 'grid');
      expect(find.byKey(const ValueKey('node_card')), findsWidgets);
    });

    testWidgets('滚动到当前节点 reaches a node far down a 1000-node list', (tester) async {
      await _pump(tester, group: _group(1000, selected: 870));
      expect(find.byKey(const ValueKey('节点 870')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('node_style_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('node_locate')));
      for (var i = 0; i < 300 && find.byKey(const ValueKey('节点 870')).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('节点 870')), findsOneWidget);
      final y = tester.getTopLeft(find.byKey(const ValueKey('节点 870'))).dy;
      expect(y, inInclusiveRange(0, 900));
    });

    testWidgets('2× text, 320 px, 卡片 紧凑: no overflow', (tester) async {
      await _pump(
        tester,
        group: _group(30),
        prefs: {'muse_node_layout': 'grid', 'muse_node_density': 'compact'},
        size: const Size(320, 700),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
