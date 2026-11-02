// 穿云 1.9.0 #12: APK size. The icon font package shipped its second (unused) font whole — the
// icon tree shaker only subsets fonts the app references — so its handful of icons now come from
// Material icons (already in the app, tree-shaken). 兼容内核 keeps its build tags: every protocol
// a subscription uses stays, and with_gvisor is what the default "mixed" TUN stack needs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no separate icon font package, nothing in lib uses it', () {
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('fluentui_system_icons')));
    expect(File('pubspec.lock').readAsStringSync(), isNot(contains('fluentui_system_icons')));
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      if (s.contains('package:fluentui_system_icons') || RegExp(r'^[^/]*FluentIcons\.', multiLine: true).hasMatch(s)) {
        hits.add(f.path);
      }
    }
    expect(hits, isEmpty);
  });

  test('the icons that replaced it', () {
    final a = File('lib/core/widget/adaptive_icon.dart').readAsStringSync();
    for (final i in ['Icons.more_horiz', 'Icons.more_vert', 'Icons.ios_share', 'Icons.share_outlined']) {
      expect(a, contains(i));
    }
    expect(File('lib/utils/alerts.dart').readAsStringSync(), allOf(contains('Icons.error_outline'), contains('Icons.check')));
    expect(File('lib/utils/placeholders.dart').readAsStringSync(), contains('Icons.error_outline'));
  });

  test('兼容内核 build tags unchanged: no protocol dropped, gvisor kept for the mixed stack', () {
    final ci = File('.github/workflows/muse-android.yml').readAsStringSync();
    // the Android job reads the tags from the core's own workflow at the pinned commit
    expect(ci, contains('MIHOMO_TAGS'));
    expect(ci, contains('-s -w -buildid='));
    expect(ci, contains('-trimpath'));
  });

  test('APK size is still recorded and capped on every Android CI run', () {
    final ci = File('tool/ci/collect_apk.sh').readAsStringSync();
    expect(ci, contains('APK size'));
    expect(ci, contains('83886080'));
  });
}
