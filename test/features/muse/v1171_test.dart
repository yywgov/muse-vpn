// 穿云 1.17.1 tests: the 「最近」 row on the nodes page is removed (recent data kept for the tray).
// Part of 穿云 (GPLv3).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('1.17.1 节点页去掉「最近」行', () {
    test('node list no longer builds the recent chip row, still records recent nodes', () {
      final s = _src('lib/features/muse/nodes/node_list.dart');
      expect(s, isNot(contains("ValueKey('node_recent_row')")));
      expect(s, isNot(contains('node_recent_\$')));
      expect(s, isNot(contains('museRecentToOffer(')));
      // picking a node still goes to the front of 最近使用 (Windows tray R18, 手动选择)
      expect(s, contains('museRememberRecent(ref, tag)'));
    });

    test('tray 最近使用 still reads the saved list', () {
      expect(_src('lib/features/system_tray/notifier/system_tray_notifier.dart'), contains('recentNodes'));
    });
  });

  group('版本 1.17.1', () {
    test('pubspec, changelog, CHANGELOG.md', () {
      // 1.18.0 and later: the 1.17.1 notes stay in the changelog
      expect(_src('pubspec.yaml'), contains('version: 1.1'));
      expect(museChangelog.containsKey('1.17.1'), isTrue);
      expect(museChangelog['1.17.1']!.join(), contains('「最近」'));
      expect(_src('CHANGELOG.md'), contains('### 1.17.1'));
    });
  });
}
