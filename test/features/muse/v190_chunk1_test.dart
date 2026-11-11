// 穿云 1.9.0 (batch 2, chunk 1): glossary / privacy text, stats CSV, weekly snapshot, update size,
// clipboard clearing. 1.10.0: the 帮助与隐私 page (glossary / privacy text) was removed; its clipboard
// switch lives on 设置 › 外观 and search sends the old names there.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/help_content.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

  test('1.9.0 settings are searchable (1.10.0: 帮助与隐私 is gone, the clipboard switch is on 外观)', () {
    final titles = museSettingEntries.map((e) => e.title).toList();
    expect(titles, contains('导入后清空剪贴板'));
    // 1.11.0: 每周本地快照 and 统计导出 CSV removed
    for (final t in ['每周本地快照', '导出 CSV']) {
      expect(titles, isNot(contains(t)));
    }
    expect(titles, isNot(contains('帮助与隐私')));
    expect(MuseSettingPage.values.map((e) => e.name), isNot(contains('help')));
    // 1.20.3: the switch moved from 外观 to 设置 › 隐私
    expect(museSettingEntries.singleWhere((e) => e.title == '导入后清空剪贴板').page, MuseSettingPage.privacy);
    // the old words lead to the switch's new place
    final hits = museSearchSettings('剪贴板', android: true, windows: false);
    expect(hits.map((e) => e.page), contains(MuseSettingPage.privacy)); // 1.20.3
  });

  group('clipboard switch on 设置 › 外观 (moved from 帮助与隐私)', () {
    Future<ProviderContainer> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
      await tester.runAsync(() => container.read(translationsProvider.future));
      await tester.binding.setSurfaceSize(const Size(400, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MusePrivacyPage(android: false)), // 1.20.3: moved from 外观 to 设置 › 隐私
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('off by default, same preference key, saves', (tester) async {
      final c = await pump(tester);
      final sw = find.byKey(const ValueKey('clear_clipboard_switch'));
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      expect(c.read(MusePrefs.clearClipboardAfterImport), isFalse);
      await tester.tap(sw);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(c.read(MusePrefs.clearClipboardAfterImport), isTrue);
      final sp = await tester.runAsync(() => c.read(sharedPreferencesProvider.future));
      expect(sp!.getBool('muse_clear_clipboard'), isTrue); // storage key unchanged
    });
  });
}
