// 穿云 1.6.0 C10 - 从备份恢复 with a preview: what a backup would change here, for a chosen
// 恢复范围 (全部 / 仅订阅 / 仅设置) and 恢复策略 (合并 / 覆盖). Pure logic, unit-tested.
//   * 合并 (default, the only behaviour before 1.6.0): only the settings in the backup are written;
//     everything else stays as it is.
//   * 覆盖: in addition, a synced setting this device has but the backup does not is reset to its
//     default (removed), so the result is exactly the backup's settings.
//   * Subscriptions are only ever added, under both strategies: one already here is skipped, and
//     nothing in a backup can remove a subscription.
// Part of 穿云 (GPLv3).

import 'dart:convert';

enum MuseRestoreScope {
  all('全部'),
  subscriptions('仅订阅'),
  settings('仅设置');

  const MuseRestoreScope(this.title);

  final String title;

  bool get includesSettings => this != subscriptions;
  bool get includesSubscriptions => this != settings;
}

enum MuseRestoreStrategy {
  merge('合并'),
  overwrite('覆盖');

  const MuseRestoreStrategy(this.title);

  final String title;
}

/// A subscription a restore would add.
typedef MuseRestoreSub = ({String url, String name});

class MuseRestorePlan {
  const MuseRestorePlan({
    required this.scope,
    required this.strategy,
    this.settings = const {},
    this.subsToAdd = const [],
    this.subsAlreadyHere = 0,
  });

  final MuseRestoreScope scope;
  final MuseRestoreStrategy strategy;

  /// setting key → the backup's value, or null = reset to default (覆盖 only)
  final Map<String, Object?> settings;

  final List<MuseRestoreSub> subsToAdd;

  /// subscriptions in the backup this device already has (left untouched)
  final int subsAlreadyHere;

  int get settingsChanged => settings.values.where((v) => v != null).length;
  int get settingsReset => settings.values.where((v) => v == null).length;

  bool get isEmpty => settings.isEmpty && subsToAdd.isEmpty;

  /// What to hand to the sync service's apply (subscriptions as `sub:<url>` → name).
  Map<String, Object?> get changes => {
    ...settings,
    for (final s in subsToAdd) 'sub:${s.url}': s.name,
  };

  /// 「3 项设置更新，2 项恢复默认，新增 1 个订阅」
  String get summary {
    if (isEmpty) return '与当前一致，无需恢复';
    return [
      if (settingsChanged > 0) '$settingsChanged 项设置更新',
      if (settingsReset > 0) '$settingsReset 项恢复默认',
      if (subsToAdd.isNotEmpty) '新增 ${subsToAdd.length} 个订阅',
    ].join('，');
  }
}

bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// What restoring [backup] (values, `sub:<url>` → name for subscriptions) would do to [current].
/// Only keys in [settingKeys] count as settings; anything else in the file is ignored.
MuseRestorePlan museRestorePlan({
  required Map<String, Object?> current,
  required Map<String, Object?> backup,
  required Set<String> settingKeys,
  MuseRestoreScope scope = MuseRestoreScope.all,
  MuseRestoreStrategy strategy = MuseRestoreStrategy.merge,
}) {
  final settings = <String, Object?>{};
  final subs = <MuseRestoreSub>[];
  var already = 0;
  if (scope.includesSettings) {
    backup.forEach((k, v) {
      if (k.startsWith('sub:') || !settingKeys.contains(k) || v == null) return;
      if (!_same(current[k], v)) settings[k] = v;
    });
    if (strategy == MuseRestoreStrategy.overwrite) {
      for (final k in current.keys) {
        if (k.startsWith('sub:') || !settingKeys.contains(k)) continue;
        if (backup[k] == null && current[k] != null) settings[k] = null;
      }
    }
  }
  if (scope.includesSubscriptions) {
    final seen = <String>{};
    backup.forEach((k, v) {
      if (!k.startsWith('sub:') || v == null) return;
      final url = k.substring(4);
      if (url.trim().isEmpty || !seen.add(url)) return;
      if (current.containsKey(k)) {
        already++;
      } else {
        subs.add((url: url, name: '$v'.trim()));
      }
    });
  }
  return MuseRestorePlan(scope: scope, strategy: strategy, settings: settings, subsToAdd: subs, subsAlreadyHere: already);
}

/// A subscription's name for the preview list (its host when it has none).
String museRestoreSubTitle(MuseRestoreSub s) {
  if (s.name.isNotEmpty) return s.name;
  return Uri.tryParse(s.url)?.host ?? s.url;
}
