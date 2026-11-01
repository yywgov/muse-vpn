// 穿云 1.9.0: source-contract tests read a library together with its `part` files (node_list.dart
// and more_settings.dart were split into parts; what a test looks for may now live in a part).
import 'dart:io';

import 'package:path/path.dart' as p;

String museLibrarySource(String path) {
  final main = File(path).readAsStringSync();
  final parts = RegExp(r"^part '([^']+)';", multiLine: true).allMatches(main).map((m) => m.group(1)!);
  return [main, for (final part in parts) File(p.join(p.dirname(path), part)).readAsStringSync()].join('\n');
}
