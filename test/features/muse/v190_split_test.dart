// 穿云 1.9.0 #11: nodes/node_list.dart and settings/more_settings.dart split into part files of the
// same libraries (no public API change, row reuse kept). Behaviour is covered by the existing
// node-list and settings tests, which keep passing unchanged.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/library_source.dart';

void main() {
  const nodes = 'lib/features/muse/nodes';
  const settings = 'lib/features/muse/settings';

  test('both libraries are split into parts, none over 1000 lines', () {
    final libs = {
      '$nodes/node_list.dart': ['node_rows.dart', 'node_details.dart', 'node_actions.dart', 'node_dialogs.dart'],
      '$settings/more_settings.dart': [
        'appearance_page.dart',
        'node_settings_page.dart',
        'developer_page.dart',
        'routing_pages.dart',
        'network_page.dart',
        'sync_pages.dart',
        'stats_page.dart',
      ],
    };
    libs.forEach((lib, parts) {
      final main = File(lib).readAsStringSync();
      for (final part in parts) {
        expect(main, contains("part '$part';"), reason: lib);
        final f = File('${File(lib).parent.path}/$part');
        final src = f.readAsStringSync();
        expect(src, contains("part of '${lib.split('/').last}';"), reason: part);
        expect(src.contains(RegExp(r'^import ', multiLine: true)), isFalse, reason: part);
        expect(src.split('\n').length, lessThan(1000), reason: part);
      }
      expect(main.split('\n').length, lessThan(1000), reason: lib);
    });
  });

  test('node rows are still reused by their inputs (1.6.0 C11)', () {
    final src = museLibrarySource('$nodes/node_list.dart');
    expect(src, contains('class _NodeRowMemo'));
    expect(src, contains('class _NodeSlotKey extends LocalKey'));
    expect(src, contains('findChildIndexCallback'));
  });

  test('every page class is defined exactly once across the parts', () {
    final src = museLibrarySource('$settings/more_settings.dart');
    for (final c in ['MuseAppearancePage', 'MuseNodeSettingsPage', 'MuseDeveloperPage', 'MuseRoutingPage', 'MuseNetworkPage', 'MuseSyncPage', 'MuseStatsPage', 'MuseWebdavPage']) {
      expect(RegExp('class $c ').allMatches(src).length, 1, reason: c);
    }
  });
}
