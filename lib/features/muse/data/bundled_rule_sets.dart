// 穿云 1.2.4 - rule-sets shipped with the app (国内直连 + 去广告). The core loads them from
// <baseDir>/rule-sets/<name>.srs when it has no cached copy (sing-box initial_path) and updates
// them in the background, so connecting never waits for a download (that wait was up to
// 2 × 15 s on every connect while the downloads kept failing).
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const museBundledRuleSets = [
  'geosite-cn',
  'geoip-cn',
  'geosite-category-ads-all',
  'geosite-malware',
  'geosite-phishing',
  'geosite-cryptominers',
  'geoip-malware',
  'geoip-phishing',
];

/// Copies the bundled rule-sets into [baseDir]/rule-sets (only files that are missing or differ
/// in size, so an app update brings newer lists). Never throws.
Future<int> museInstallBundledRuleSets(String baseDir, {AssetBundle? bundle}) async {
  final b = bundle ?? rootBundle;
  var copied = 0;
  try {
    final dir = Directory(p.join(baseDir, 'rule-sets'));
    await dir.create(recursive: true);
    for (final name in museBundledRuleSets) {
      try {
        final data = await b.load('assets/rule-sets/$name.srs');
        final file = File(p.join(dir.path, '$name.srs'));
        if (file.existsSync() && file.lengthSync() == data.lengthInBytes) continue;
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
        copied++;
      } catch (_) {
        // a missing asset just means that list is downloaded as before
      }
    }
  } catch (_) {}
  return copied;
}
