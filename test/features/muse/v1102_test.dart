// 穿云 1.10.2: 「在最近任务中隐藏」 back on 设置 › 外观 (same key, MainActivity applies it again), and
// the 自查 fixes that are checked in source / pure logic (the screens are in v1102_sweep_test).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/connections/connections_page.dart' show museConnCompactHeight;
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('在最近任务中隐藏', () {
    test('storage key unchanged on both sides (Dart exclude_from_recents = Kotlin flutter.exclude_from_recents)', () {
      expect(
        _src('lib/core/preferences/general_preferences.dart'),
        contains('static final excludeFromRecents = PreferencesNotifier.create<bool, bool>("exclude_from_recents", false);'),
      );
      expect(_src('android/app/src/main/kotlin/com/hiddify/hiddify/constant/SettingsKey.kt'), contains(r'EXCLUDE_FROM_RECENTS = "${KEY_PREFIX}exclude_from_recents"'));
      expect(_src('android/app/src/main/kotlin/com/hiddify/hiddify/constant/SettingsKey.kt'), contains('KEY_PREFIX = "flutter."'));
    });

    test('MainActivity reads the saved value and applies it on resume (as in 1.9.1)', () {
      final kt = _src('android/app/src/main/kotlin/com/hiddify/hiddify/MainActivity.kt');
      final resume = kt.substring(kt.indexOf('override fun onResume()'), kt.indexOf('override fun onDestroy()'));
      expect(resume, contains('if (Settings.excludeFromRecents) ChuanyunHandler.applyExcludeFromRecents(this, true)'));
      expect(_src('android/app/src/main/kotlin/com/hiddify/hiddify/Settings.kt'), contains('preferences.getBoolean(SettingsKey.EXCLUDE_FROM_RECENTS, false)'));
    });

    test('the switch writes the preference and tells the system right away', () {
      final s = _src('lib/features/muse/settings/android_settings.dart');
      expect(s, contains("ValueKey('settings_exclude_recents')"));
      expect(s, contains('Preferences.excludeFromRecents.notifier).update(value)'));
      expect(s, contains('ChuanyunPlatform.setExcludeFromRecents(value)'));
      // only inside the Android section of 外观
      // 1.20.3：Android 通知一组搬到 设置 › 隐私与通知
      expect(_src('lib/features/muse/settings/privacy_settings_page.dart'), contains('if (isAndroid) const MuseAndroidAppearanceSection()'));
    });

    test('search 「最近任务」 / 「隐藏」 finds it on 外观 (Android only)', () {
      final recents = museSearchSettings('最近任务', android: true, windows: false);
      expect(recents.first.title, '在最近任务中隐藏');
      expect(recents.first.page, MuseSettingPage.privacy); // 1.20.3
      expect(museSearchSettings('隐藏', android: true, windows: false).map((e) => e.title), contains('在最近任务中隐藏'));
      expect(museSearchSettings('最近任务', android: false, windows: true).map((e) => e.title), isNot(contains('在最近任务中隐藏')));
    });

    test('更新说明', () {
      expect(museChangelog['1.10.2'], contains('「在最近任务中隐藏」恢复，开关移到外观页'));
    });
  });

  group('自查修复', () {
    test('诊断 stops when its view is gone (a tab of 活动 can be left mid-run)', () {
      final s = _src('lib/features/muse/settings/diagnose_sheet.dart');
      final run = s.substring(s.indexOf('Future<void> _run() async {'), s.indexOf('static Future<bool> _resolves'));
      // every await that is followed by more work is followed by a mounted check before ref is used again
      final lines = run.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!l.contains('await ') || l.contains('unawaited(')) continue;
        final rest = lines.sublist(i + 1).join('\n');
        final nextRef = rest.indexOf('ref.');
        final nextCheck = rest.indexOf('if (!mounted) return;');
        if (nextRef < 0) continue;
        expect(nextCheck >= 0 && nextCheck < nextRef, isTrue, reason: 'after: ${l.trim()}');
      }
    });

    test('连接 page scrolls its header with the list only on a short screen', () {
      expect(museConnCompactHeight(224), isTrue);
      expect(museConnCompactHeight(399), isTrue);
      expect(museConnCompactHeight(600), isFalse);
    });

    test('节点页 auto-scroll follows the page coming into view, no timer or polling', () {
      final s = _src('lib/features/muse/nodes/node_list.dart');
      expect(s, contains('TickerMode.valuesOf(context).enabled'));
      expect(s, contains('}, [visible, selectedTag.isEmpty]);'));
      expect(s, isNot(contains('Timer.periodic')));
    });
  });
}
