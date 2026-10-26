// 穿云 1.6.0 C6 - 订阅 page helpers: several subscription links pasted at once, the user's own
// order of subscriptions, card columns, the read-only 运行配置 view (redacted).
// Part of 穿云 (GPLv3).

import 'dart:convert';

import 'package:hiddify/features/muse/logic/redact.dart';

/// http(s) subscription links in [raw], one per line (or separated by spaces), duplicates dropped.
/// Fewer than 2 = not a batch (the single-link / node-link import handles it).
List<String> museSplitSubLinks(String raw) {
  final out = <String>[];
  for (final part in raw.split(RegExp(r'[\s,]+'))) {
    final p = part.trim();
    if (!RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(p)) continue;
    if (Uri.tryParse(p)?.host.isEmpty ?? true) continue;
    if (!out.contains(p)) out.add(p);
  }
  return out;
}

/// True when [raw] is only subscription links (2 or more) and nothing else worth importing.
bool museIsLinkBatch(String raw) {
  final links = museSplitSubLinks(raw);
  if (links.length < 2) return false;
  final rest = raw.split(RegExp(r'[\s,]+')).where((e) => e.trim().isNotEmpty && !links.contains(e.trim()));
  return rest.isEmpty;
}

/// Summary of a batch import.
String museBatchSummary(int ok, int failed) =>
    failed == 0 ? '已导入 $ok 个订阅' : (ok == 0 ? '$failed 个订阅都导入失败' : '已导入 $ok 个订阅，$failed 个失败');

/// [ids] in the saved order ([raw] = comma list); ids not in it keep their place after the ordered
/// ones (a new subscription goes to the end). Never drops an id.
List<String> museOrderIds(List<String> ids, String raw) {
  final saved = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final known = [for (final s in saved) if (ids.contains(s)) s];
  return [...known, for (final id in ids) if (!known.contains(id)) id];
}

/// Card columns: one per 300 px, at most 3.
int museProfileColumns(double width) => (width / 300).floor().clamp(1, 3);

/// The saved config as the 运行配置 view shows it: pretty JSON (when it is JSON) with secrets and
/// addresses redacted.
String museRuntimeConfigView(String raw) {
  var text = raw;
  try {
    text = const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {}
  return museRedact(text);
}
