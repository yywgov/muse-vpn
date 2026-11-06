// 穿云 1.12.0 - 自动最快可限定地区：选一个地区后，内核的「自动最快」只在名字属于这个地区的节点
// 里挑（国旗或地区名，和节点页的地区判断一致）。空 = 全部（默认，和以前一样）。内核拿到的是
// 一个匹配规则；匹配不到任何节点时内核仍用全部节点，不会出现空分组。
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/home/node_label.dart';

/// [code]'s flag emoji (HK -> 🇭🇰), or null.
String? _flagOf(String code) {
  if (code.length != 2) return null;
  final a = code.codeUnitAt(0), b = code.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return null;
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

/// The pattern sent to the core for region [code] ('' = every node). Both cores read it as a
/// Go regular expression; Dart's [RegExp] reads it the same way (tests use that).
String museAutoRegionFilter(String code) {
  final c = code.trim().toUpperCase() == 'UK' ? 'GB' : code.trim().toUpperCase();
  if (c.isEmpty) return '';
  final parts = <String>[];
  final flag = _flagOf(c);
  if (flag != null) parts.add(flag);
  if (c == 'GB') parts.add('🇬🇧');
  final words = museRegionKeywordPattern(c);
  if (words != null) parts.add(words);
  if (parts.isEmpty) return '';
  return '(?i)(${parts.toSet().join('|')})';
}

/// Whether node [name] is in region [code] by the same pattern the core uses (for the list).
bool museInAutoRegion(String name, String code) {
  final f = museAutoRegionFilter(code);
  if (f.isEmpty) return true;
  return RegExp(f.replaceFirst('(?i)', ''), caseSensitive: false).hasMatch(name);
}

/// The extra core option (nothing when every node).
Map<String, dynamic> museAutoFilterExtras(String filter) => filter.isEmpty ? const {} : {'muse-auto-filter': filter};
