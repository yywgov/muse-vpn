// 穿云 1.9.0 #14 - the rule-sets 兼容内核's default 分流 uses (国内直连 + 去广告), shipped with the
// app so the first connect on 兼容内核 does not wait for downloads. 兼容内核 keeps each list as
// <workingDir>/data/mihomo/ruleset/<provider>.mrs and loads that file before anything else; when it
// is older than the update interval (5 days) it is refreshed in the background, as usual.
//
// Only the lists the default rules use and that exist in the .mrs data are shipped (about 0.6 MB):
// geosite-cn / geoip-cn (内置「国内直连」, region cn) and geosite-category-ads-all (内置「去广告」).
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Bundled lists (assets/rule-sets-compat/<name>.mrs).
const museCompatBundledRuleSets = ['geosite-cn', 'geoip-cn', 'geosite-category-ads-all'];

/// When the bundled copies were taken. A copy is written with this time so 兼容内核 sees its real
/// age (and refreshes it in the background once it is older than the interval), and an app update
/// with newer copies replaces older files — never a list 兼容内核 downloaded since (written later).
final museCompatRuleSetsSnapshot = DateTime.utc(2026, 11, 1);

/// Where 兼容内核 keeps a list: its home is <workingDir>/data/mihomo, providers are "muse-<name>".
String museCompatRuleSetPath(String workingDir, String name) =>
    p.join(workingDir, 'data', 'mihomo', 'ruleset', 'muse-$name.mrs');

/// Puts the bundled lists where 兼容内核 looks, when missing or older than the bundle. Never
/// throws; returns how many were written.
Future<int> museInstallBundledCompatRuleSets(String workingDir, {AssetBundle? bundle}) async {
  final b = bundle ?? rootBundle;
  var copied = 0;
  for (final name in museCompatBundledRuleSets) {
    try {
      final file = File(museCompatRuleSetPath(workingDir, name));
      if (file.existsSync() && !file.lastModifiedSync().isBefore(museCompatRuleSetsSnapshot)) continue;
      final data = await b.load('assets/rule-sets-compat/$name.mrs');
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.saving');
      await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await tmp.setLastModified(museCompatRuleSetsSnapshot);
      if (file.existsSync()) file.deleteSync();
      await tmp.rename(file.path);
      copied++;
    } catch (_) {
      // a missing asset or a read-only folder just means that list is downloaded as before
    }
  }
  return copied;
}
