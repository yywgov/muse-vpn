// 穿云 1.6.0 C6 订阅页: batch links, subscription order (never drops one), card columns, 运行配置
// view redaction, menu entries, 覆写脚本 placeholder.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/config/muse_config_page.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/profile_tools.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProfileEntity _p(String id, String name) =>
    ProfileEntity.remote(id: id, active: false, name: name, url: 'https://sub.example.com/$id?token=abc', lastUpdate: DateTime(2026));

void main() {
  group('C6 batch links', () {
    test('two or more http(s) links = a batch; duplicates dropped', () {
      const raw = 'https://a.example.com/sub?t=1\nhttps://b.example.com/s  https://a.example.com/sub?t=1\n';
      expect(museSplitSubLinks(raw), ['https://a.example.com/sub?t=1', 'https://b.example.com/s']);
      expect(museIsLinkBatch(raw), isTrue);
    });
    test('one link, node links or mixed text are not a batch', () {
      expect(museIsLinkBatch('https://a.example.com/sub'), isFalse);
      expect(museIsLinkBatch('vless://x@h:443#a\nvless://y@h:443#b'), isFalse);
      expect(museIsLinkBatch('https://a.example.com/s\nvless://y@h:443#b\nhttps://c.example.com/s'), isFalse);
      expect(museSplitSubLinks('http:// nothing'), isEmpty);
    });
    test('summary', () {
      expect(museBatchSummary(3, 0), '已导入 3 个订阅');
      expect(museBatchSummary(2, 1), '已导入 2 个订阅，1 个失败');
      expect(museBatchSummary(0, 2), '2 个订阅都导入失败');
    });
  });

  group('C6 order and columns', () {
    test('saved order applied, unknown ids ignored, new ones appended, none dropped', () {
      expect(museOrderIds(['a', 'b', 'c'], ''), ['a', 'b', 'c']);
      expect(museOrderIds(['a', 'b', 'c'], 'c,a'), ['c', 'a', 'b']);
      expect(museOrderIds(['a', 'b'], 'x,b,y'), ['b', 'a']);
      for (final raw in ['', 'b', 'b,a,zz', ',,,']) {
        expect(museOrderIds(['a', 'b', 'c'], raw).toSet(), {'a', 'b', 'c'});
      }
    });
    test('1–3 columns, one per 300 px', () {
      expect(museProfileColumns(390), 1);
      expect(museProfileColumns(620), 2);
      expect(museProfileColumns(1000), 3);
      expect(museProfileColumns(2000), 3);
    });
  });

  group('C6 运行配置', () {
    test('pretty JSON with secrets and servers hidden', () {
      final raw = jsonEncode({
        'outbounds': [
          {'type': 'vless', 'server': 'jp.example.com', 'uuid': '11111111-2222-3333-4444-555555555555', 'password': 'p'},
        ],
      });
      final v = museRuntimeConfigView(raw);
      expect(v, contains('\n  '));
      expect(v, isNot(contains('jp.example.com')));
      expect(v, isNot(contains('11111111-2222')));
      expect(v, isNot(contains('"p"')));
      expect(v, contains('vless'));
    });
    test('not JSON: redacted as text', () {
      expect(museRuntimeConfigView('server=1.2.3.4'), isNot(contains('1.2.3.4')));
    });
  });

  group('C6 page wiring', () {
    test('menu: 复制链接 asks first, 查看运行配置; 覆写脚本 placeholder; batch import', () {
      final tile = File('lib/features/profile/widget/profile_tile.dart').readAsStringSync();
      expect(tile, contains("title: '复制链接'"));
      expect(tile, contains('showConfirmation('));
      expect(tile, contains("title: '查看运行配置'"));
      final page = File('lib/features/muse/config/muse_config_page.dart').readAsStringSync();
      expect(page, contains('profile_override_placeholder'));
      expect(page, contains('_MuseProfileGrid'));
      final add = File('lib/features/profile/add/add_profile_modal.dart').readAsStringSync();
      expect(add, contains('museImportLinkBatch'));
      // the batch goes through the normal add path only (no delete)
      expect(add.contains('deleteProfile'), isFalse);
    });

    testWidgets('订阅排序 dialog saves the dragged order', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
      addTearDown(c.dispose);
      await tester.runAsync(() => c.read(sharedPreferencesProvider.future));
      final profiles = [_p('a', '机场 A'), _p('b', '机场 B'), _p('c', '机场 C')];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  key: const ValueKey('open'),
                  onPressed: () => showMuseProfileOrder(context, ref, profiles),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.text('订阅排序'), findsOneWidget);
      // drag c to the top (the list's own reorder callback, as a drag ends)
      tester.widget<ReorderableListView>(find.byKey(const ValueKey('profile_order_list'))).onReorder(2, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile_order_save')));
      await tester.pumpAndSettle();
      final saved = c.read(MusePrefs.profileOrder).split(',');
      expect(saved.first, 'c');
      expect(saved.toSet(), {'a', 'b', 'c'});
    });
  });
}
