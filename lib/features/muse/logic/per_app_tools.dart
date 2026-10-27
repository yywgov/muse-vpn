// 穿云 1.6.0 C9 - 分应用代理 list tools: sort (已选优先 / 名称 / 安装时间), 只看联网应用 and
// system-app filter, search, 全选 / 反选 of what is shown, and the clipboard list (one package
// name per line; anything that is not a package name is skipped and counted).
// Pure functions, tested in v160_c9_test. Part of 穿云 (GPLv3).

import 'dart:typed_data';

import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';

enum MuseAppSort {
  selected('selected', '已选优先'),
  name('name', '名称'),
  installed('installed', '安装时间');

  const MuseAppSort(this.key, this.label);

  final String key;
  final String label;

  static MuseAppSort fromKey(String key) =>
      MuseAppSort.values.firstWhere((e) => e.key == key, orElse: () => MuseAppSort.selected);
}

/// One installed app as the list needs it.
class MuseAppRow {
  const MuseAppRow({required this.packageName, required this.name, this.installed = 0, this.system = false, this.icon});

  final String packageName;
  final String name;

  /// first install time, epoch ms (0 = unknown)
  final int installed;
  final bool system;
  final Uint8List? icon;
}

/// Whether the app counts as chosen in the list (a check or an automatic pick not removed).
bool museAppActive(int? flag) => flag != null && !PkgFlag.forceDeselection.check(flag);

/// 1 your picks, 2 automatic picks, 3 removed automatic picks, 4 the rest (the old order).
int museAppPriority(int? flag) {
  if (flag == null) return 4;
  if (PkgFlag.userSelection.check(flag)) return 1;
  if (PkgFlag.autoSelection.check(flag) && !PkgFlag.forceDeselection.check(flag)) return 2;
  return 3;
}

/// Filters and sorts what the list shows. [internet] null = not known (the filter then shows all).
List<MuseAppRow> museAppView(
  Iterable<MuseAppRow> apps, {
  required Map<String, int> flags,
  MuseAppSort sort = MuseAppSort.selected,
  String query = '',
  bool hideSystem = false,
  bool internetOnly = false,
  Set<String>? internet,
}) {
  final q = query.trim().toLowerCase();
  final list = [
    for (final a in apps)
      if ((!hideSystem || !a.system) &&
          (!internetOnly || internet == null || internet.contains(a.packageName)) &&
          (q.isEmpty || a.name.toLowerCase().contains(q) || a.packageName.toLowerCase().contains(q)))
        a,
  ];
  int byName(MuseAppRow a, MuseAppRow b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.packageName.compareTo(b.packageName);
  }

  switch (sort) {
    case MuseAppSort.selected:
      list.sort((a, b) {
        final c = museAppPriority(flags[a.packageName]).compareTo(museAppPriority(flags[b.packageName]));
        return c != 0 ? c : byName(a, b);
      });
    case MuseAppSort.name:
      list.sort(byName);
    case MuseAppSort.installed:
      // newest first
      list.sort((a, b) {
        final c = b.installed.compareTo(a.installed);
        return c != 0 ? c : byName(a, b);
      });
  }
  return list;
}

/// 全选: every shown app that is not chosen yet.
List<String> museSelectAllTargets(List<MuseAppRow> shown, Map<String, int> flags) => [
  for (final a in shown)
    if (!museAppActive(flags[a.packageName])) a.packageName,
];

/// 反选: (to choose, to un-choose) among the shown apps.
({List<String> select, List<String> deselect}) museInvertTargets(List<MuseAppRow> shown, Map<String, int> flags) {
  final select = <String>[];
  final deselect = <String>[];
  for (final a in shown) {
    (museAppActive(flags[a.packageName]) ? deselect : select).add(a.packageName);
  }
  return (select: select, deselect: deselect);
}

final _pkgName = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$');

bool museIsPackageName(String s) => s.length <= 255 && _pkgName.hasMatch(s);

/// Package names from pasted text (one per line; commas, spaces and semicolons also split).
/// Duplicates are dropped; [skipped] counts the pieces that are not package names.
({List<String> packages, int skipped}) museParsePackageList(String text) {
  final seen = <String>{};
  final packages = <String>[];
  var skipped = 0;
  for (final raw in text.split(RegExp(r'[\r\n,;，；\s]+'))) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    if (!museIsPackageName(s)) {
      skipped++;
      continue;
    }
    if (seen.add(s)) packages.add(s);
  }
  return (packages: packages, skipped: skipped);
}

/// The chosen apps as clipboard text (one package per line, sorted).
String museExportPackageList(Map<String, int> flags) {
  final l = [
    for (final e in flags.entries)
      if (museAppActive(e.value)) e.key,
  ]..sort();
  return l.join('\n');
}

/// The toast after an import.
String museImportSummary({required int added, required int already, required int skipped}) {
  final parts = <String>['已导入 $added 个'];
  if (already > 0) parts.add('$already 个已在列表');
  if (skipped > 0) parts.add('忽略 $skipped 个无效包名');
  return parts.join('，');
}
