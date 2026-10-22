// 穿云 1.4.0: every screen uses the design tokens — no hand-written paddings, radii, font sizes,
// icon sizes or colour literals outside lib/features/muse/widget/muse_tokens.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dirs = [
  'lib/features/muse',
  'lib/features/settings/overview',
  'lib/features/route_rules',
  'lib/features/app_based_routing/overview',
  'lib/features/about',
  'lib/features/profile',
  'lib/core/router/dialog',
];

final _patterns = <String, RegExp>{
  'raw EdgeInsets number': RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB)\([^()]*?(?<![\w.])(?!0\b)\d+(\.\d+)?(?![\w.])'),
  'raw radius': RegExp(r'BorderRadius\.circular\(\d'),
  'raw font size': RegExp(r'fontSize: \d'),
  'colour literal': RegExp(r'Color\(0x'),
  'raw icon size': RegExp(r'\bsize: \d'),
  'Material colour': RegExp(r'Colors\.(green|red|orange|amber|blue|grey|lightGreen)'),
};

void main() {
  test('no hand-written numbers / colours outside the tokens', () {
    final hits = <String>[];
    for (final d in _dirs) {
      for (final f in Directory(d).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('muse_tokens.dart') || f.path.endsWith('.g.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i].trimLeft();
          if (l.startsWith('//')) continue;
          for (final e in _patterns.entries) {
            if (e.value.hasMatch(l)) hits.add('${f.path}:${i + 1} ${e.key}: ${l.trim()}');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
