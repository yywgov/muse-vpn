// 穿云 1.9.0 (batch 2, chunk 1): glossary / privacy text, stats CSV, weekly snapshot, update size,
// clipboard clearing, 帮助与隐私 page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/help_content.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart';
import 'package:hiddify/features/muse/settings/help_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('#234 glossary', () {
    test('every card has a word and a meaning, words are unique', () {
      expect(museGlossary.length, greaterThanOrEqualTo(10));
      expect(museGlossary.map((e) => e.term).toSet().length, museGlossary.length);
      for (final t in museGlossary) {
        expect(t.term, isNotEmpty);
        expect(t.meaning.length, greaterThan(10));
      }
    });
    test('the app words are all explained (one word everywhere)', () {
      final terms = museGlossary.map((e) => e.term).join(' ');
      for (final w in ['节点', '订阅', '规则模式', '全局模式', '分流', 'TUN', '系统代理']) {
        expect(terms, contains(w));
      }
    });
    test('search by word, meaning and other names', () {
      expect(museGlossarySearch('').length, museGlossary.length);
      expect(museGlossarySearch('tun').single.term, 'TUN 模式');
      expect(museGlossarySearch('虚拟网卡').map((e) => e.term), contains('TUN 模式'));
      expect(museGlossarySearch('机场').single.term, '订阅');
      expect(museGlossarySearch('zzzz'), isEmpty);
    });
    test('no upstream project names in the help text', () {
      final all = [for (final t in museGlossary) '${t.term}${t.meaning}', for (final p in musePrivacyStored) '${p.$1}${p.$2}', ...musePrivacyNever].join();
      for (final n in ['Hiddify', 'sing-box', 'Clash', 'Xray', 'Mihomo']) {
        expect(all.toLowerCase(), isNot(contains(n.toLowerCase())));
      }
    });
  });

  group('#179 CSV', () {
    test('header, order and totals', () {
      const log = MuseTrafficLog({'2026-10-02': (5, 7), '2026-10-01': (1, 2)});
      final lines = museTrafficCsv(log).trim().split('\r\n');
      expect(lines.first, '日期,上传(字节),下载(字节),合计(字节)');
      expect(lines[1], '2026-10-01,1,2,3');
      expect(lines[2], '2026-10-02,5,7,12');
      expect(lines.length, 3);
    });
    test('empty log is only the header', () {
      expect(museTrafficCsv(MuseTrafficLog.empty).trim().split('\r\n').length, 1);
    });
  });

  group('#200 weekly snapshot', () {
    final now = DateTime(2026, 11, 8, 12);
    test('due when none, or the newest is a week old', () {
      expect(museWeeklySnapshotDue(const [], now), isTrue);
      expect(museWeeklySnapshotDue([DateTime(2026, 11, 1, 12)], now), isTrue);
      expect(museWeeklySnapshotDue([DateTime(2026, 11, 1, 12, 1)], now), isFalse);
      expect(museWeeklySnapshotDue([DateTime(2026, 10, 1), DateTime(2026, 11, 7)], now), isFalse);
    });
    test('a clock that went back does not take one at every start', () {
      expect(museWeeklySnapshotDue([DateTime(2026, 12, 1)], now), isFalse);
    });
    test('weekly files have their own five and never push out the others', () {
      String n(String r, int day) => museAutoBackupName(r, DateTime(2026, 10, day, 9));
      final names = [
        for (var d = 1; d <= 7; d++) n('weekly', d),
        n('restore', 1), n('update', 2), n('restore', 3),
        'notes.txt',
      ];
      final prune = museAutoBackupsToPrune(names);
      expect(prune, [n('weekly', 1), n('weekly', 2)]);
      expect(museAutoBackupReasonTitle('weekly'), '每周快照');
      // the old behaviour for the others is unchanged
      final many = [for (var d = 1; d <= 8; d++) n('restore', d)];
      expect(museAutoBackupsToPrune(many), [n('restore', 1), n('restore', 2), n('restore', 3)]);
    });
  });

  test('#209 download size in words', () {
    expect(museFileSizeText(0), '');
    expect(museFileSizeText(512 * 1024), '512 KB');
    expect(museFileSizeText(44 * 1024 * 1024 + 300 * 1024), '44.3 MB');
    expect(museFileSizeText(3 * 1024 * 1024 * 1024), '3.00 GB');
  });

  test('1.9.0 settings are searchable', () {
    final titles = museSettingEntries.map((e) => e.title).toList();
    for (final t in ['帮助与隐私', '导入后清空剪贴板', '每周本地快照', '导出 CSV']) {
      expect(titles, contains(t));
    }
    expect(MuseSettingPage.help.path, contains('帮助'));
  });

  group('help page', () {
    Future<ProviderContainer> pump(WidgetTester tester, {double width = 360, double scale = 1}) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
              child: const MuseHelpPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('shows cards, filters, and survives large text on a narrow screen', (tester) async {
      await pump(tester, scale: 2);
      expect(find.byKey(const ValueKey('term_节点')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byKey(const ValueKey('help_search')), 'TUN');
      await tester.pump();
      expect(find.byKey(const ValueKey('term_TUN 模式')), findsOneWidget);
      expect(find.byKey(const ValueKey('term_节点')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('help_search')), 'qqqq');
      await tester.pump();
      expect(find.byKey(const ValueKey('help_empty')), findsOneWidget);
    });

    testWidgets('the clipboard switch is off by default and saves', (tester) async {
      final c = await pump(tester);
      final sw = find.byKey(const ValueKey('clear_clipboard_switch'));
      await tester.dragUntilVisible(sw, find.byType(Scrollable).first, const Offset(0, -300));
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      expect(c.read(MusePrefs.clearClipboardAfterImport), isFalse);
      await tester.tap(sw);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(c.read(MusePrefs.clearClipboardAfterImport), isTrue);
    });
  });
}
