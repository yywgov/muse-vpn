// 穿云 1.20.3 发布：版本号、更新说明、CHANGELOG；已无入口的旧「按需运行」页与「按 Wi‑Fi 切换模式」页已删除，
// 功能都在 设置 › 启动与断线 › Wi‑Fi 规则。
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';

String _src(String p) => File(p).readAsStringSync();

Iterable<File> _dart(String dir) => Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  group('版本 1.20.3', () {
    test('pubspec、更新说明、CHANGELOG.md', () {
      expect(_src('pubspec.yaml'), contains('version: 1.20.3+216'));
      expect(museChangelog.keys.first, '1.20.3');
      final lines = museChangelog['1.20.3']!;
      expect(lines, hasLength(3));
      final all = lines.join();
      for (final w in ['首页风格', '配色六选一', '隐私与通知', '分流规则', '生效顺序', '诊断合成一个入口', 'Wi‑Fi 规则', '开源许可', '只显示版本号']) {
        expect(all, contains(w), reason: w);
      }
      expect(_src('CHANGELOG.md'), contains('### 1.20.3'));
    });
  });

  group('删除已无入口的旧页面', () {
    test('lib、test_driver 里不再有 MuseOnDemandPage / MuseWifiModePage / museWifiModeSummary', () {
      for (final dir in ['lib', 'test_driver']) {
        for (final f in _dart(dir)) {
          final s = f.readAsStringSync();
          for (final w in ['MuseOnDemandPage', 'MuseWifiModePage', 'museWifiModeSummary']) {
            expect(s.contains(w), isFalse, reason: '${f.path} 还引用 $w');
          }
        }
      }
    });

    test('功能仍有入口：设置首页与启动与断线页都能打开 Wi‑Fi 规则页，按需运行开关在那一页', () {
      expect(_src('lib/features/settings/overview/settings_page.dart'), contains('MuseWifiRulesPage()'));
      expect(_src('lib/features/muse/settings/auto_connect_page.dart'), contains('MuseWifiRulesPage()'));
      final page = _src('lib/features/muse/settings/wifi_mode_page.dart');
      expect(page, contains("ValueKey('on_demand_switch')"));
      expect(page, contains('MuseWifiAct'));
      // 切换逻辑与存储键都还在（只删页面，不删功能）
      expect(File('lib/features/muse/desktop/on_demand.dart').existsSync(), isTrue);
      expect(File('lib/features/muse/desktop/wifi_mode.dart').existsSync(), isTrue);
      expect(_src('lib/features/muse/data/muse_prefs.dart'), allOf(contains('muse_wifi_rules'), contains('muse_wifi_modes')));
    });
  });
}
