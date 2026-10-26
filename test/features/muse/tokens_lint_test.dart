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
  'lib/core/router/adaptive_layout',
];

final _patterns = <String, RegExp>{
  'raw EdgeInsets number': RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB)\([^()]*?(?<![\w.])(?!0\b)\d+(\.\d+)?(?![\w.])'),
  'raw radius': RegExp(r'BorderRadius\.circular\(\d'),
  'raw font size': RegExp(r'fontSize: \d'),
  'colour literal': RegExp(r'Color\(0x'),
  'raw icon size': RegExp(r'\bsize: \d'),
  'Material colour': RegExp(r'Colors\.(green|red|orange|amber|blue|grey|lightGreen)'),
  // 1.6.0 C1: every corner is a superellipse (MuseShape / MuseClip)
  'stadium border': RegExp(r'\bStadiumBorder\('),
  'rounded rectangle border': RegExp(r'\bRoundedRectangleBorder\('),
  'ClipRRect': RegExp(r'\bClipRRect\('),
  'raw Radius.circular': RegExp(r'Radius\.circular\(\d'),
};

/// 1.6.0 C1: token files (muse_tokens*.dart) are where the numbers live.
bool _exempt(String path) {
  final name = path.split(Platform.pathSeparator).last;
  return name.startsWith('muse_tokens') || name.endsWith('.g.dart') || !name.endsWith('.dart');
}

/// The lint hits in [source] (one entry per offending line).
List<String> lintSource(String path, List<String> lines) {
  final hits = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trimLeft();
    if (l.startsWith('//')) continue;
    for (final e in _patterns.entries) {
      if (e.value.hasMatch(l)) hits.add('$path:${i + 1} ${e.key}: ${l.trim()}');
    }
  }
  return hits;
}

void main() {
  test('no hand-written numbers / colours outside the tokens', () {
    final hits = <String>[];
    for (final d in _dirs) {
      for (final f in Directory(d).listSync(recursive: true).whereType<File>()) {
        if (_exempt(f.path)) continue;
        hits.addAll(lintSource(f.path, f.readAsLinesSync()));
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('1.6.0 C1: the lint catches square-ish corners', () {
    final bad = lintSource('x.dart', [
      'shape: const StadiumBorder(),',
      'shape: RoundedRectangleBorder(borderRadius: r),',
      'child: ClipRRect(borderRadius: r, child: c),',
      'const radius = Radius.circular(4);',
      '// RoundedRectangleBorder( in a comment is fine',
      'shape: MuseShape.card,',
    ]);
    expect(bad.length, 4);
    expect(_exempt('lib/features/muse/widget/muse_tokens_color.dart'), isTrue);
    expect(_exempt('lib/features/muse/widget/muse_card.dart'), isFalse);
  });
}
