// 穿云 1.9.0 #14: 兼容内核's default lists ship with the app (国内直连 geosite-cn / geoip-cn, 去广告
// geosite-category-ads-all) and are put where 兼容内核 looks before the first connect, so it needs
// no download; it refreshes them in the background as usual once they are older than 5 days. Only
// the lists the default rules use are shipped; a list 兼容内核 downloaded since is never replaced.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/bundled_compat_rule_sets.dart';
import 'package:path/path.dart' as p;

class _DiskBundle extends CachingAssetBundle {
  final loaded = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('v190_14_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('only the default lists are shipped, as zstd .mrs, small', () {
    final files = Directory('assets/rule-sets-compat').listSync().whereType<File>().toList();
    expect(files.map((f) => p.basenameWithoutExtension(f.path)).toSet(), museCompatBundledRuleSets.toSet());
    var total = 0;
    for (final f in files) {
      expect(f.path, endsWith('.mrs'));
      final b = f.readAsBytesSync();
      expect(b.sublist(0, 4), [0x28, 0xb5, 0x2f, 0xfd], reason: '${f.path} is not an .mrs (zstd) file');
      total += b.length;
    }
    expect(total, lessThan(1024 * 1024));
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/rule-sets-compat/'));
  });

  test('the shipped lists are exactly what the default rules map to (provider names)', () {
    final rules = File('lib/features/route_rules/notifier/rules_notifier.dart').readAsStringSync();
    expect(rules, contains('geosite-category-ads-all.srs'));
    expect(rules, contains('geosite-{region}.srs'));
    expect(rules, contains('geoip-{region}.srs'));
    expect(museCompatRuleSetPath('/w', 'geosite-cn'), p.join('/w', 'data', 'mihomo', 'ruleset', 'muse-geosite-cn.mrs'));
  });

  test('installed where 兼容内核 looks, dated by the bundle (refreshed in the background later)', () async {
    final bundle = _DiskBundle();
    expect(await museInstallBundledCompatRuleSets(dir.path, bundle: bundle), 3);
    for (final n in museCompatBundledRuleSets) {
      final f = File(museCompatRuleSetPath(dir.path, n));
      expect(f.readAsBytesSync(), File('assets/rule-sets-compat/$n.mrs').readAsBytesSync());
      expect(f.lastModifiedSync().toUtc(), museCompatRuleSetsSnapshot);
      expect(File('${f.path}.saving').existsSync(), isFalse);
    }
    // again: nothing to do, nothing read
    bundle.loaded.clear();
    expect(await museInstallBundledCompatRuleSets(dir.path, bundle: bundle), 0);
    expect(bundle.loaded, isEmpty);
  });

  test('a list 兼容内核 downloaded since stays; an older copy is replaced', () async {
    final cn = File(museCompatRuleSetPath(dir.path, 'geosite-cn'))
      ..createSync(recursive: true)
      ..writeAsStringSync('downloaded');
    final ip = File(museCompatRuleSetPath(dir.path, 'geoip-cn'))..writeAsStringSync('old');
    ip.setLastModifiedSync(museCompatRuleSetsSnapshot.subtract(const Duration(days: 30)));
    expect(await museInstallBundledCompatRuleSets(dir.path, bundle: _DiskBundle()), 2);
    expect(cn.readAsStringSync(), 'downloaded');
    expect(ip.readAsBytesSync(), File('assets/rule-sets-compat/geoip-cn.mrs').readAsBytesSync());
  });

  test('never throws (missing asset / unwritable folder)', () async {
    final file = File('${dir.path}/not-a-dir')..writeAsStringSync('x');
    expect(await museInstallBundledCompatRuleSets(file.path, bundle: _DiskBundle()), 0);
  });

  test('installed at start-up into the working directory 兼容内核 uses; no timer or polling', () {
    final boot = File('lib/bootstrap.dart').readAsStringSync();
    expect(boot, contains('museInstallBundledCompatRuleSets(dirs.workingDir.absolute.path)'));
    final src = File('lib/features/muse/data/bundled_compat_rule_sets.dart').readAsStringSync();
    expect(src, isNot(contains('Timer')));
    expect(src.toLowerCase(), isNot(contains('mihomo.')));
  });

  // 1.10.0: 4ced7dc (Go 1.26.10) is a descendant of e2ef6a1 and keeps that change;
  // 1.10.3: 0b29e71 (muse.21, child of 4ced7dc) keeps both; 1.10.4: a076442 (muse.22, child of 0b29e71)
  test('兼容内核 pinned to the commit that stops mapping lists the .mrs data lacks', () {
    final ref = RegExp(r'^muse\.compat\.ref=([0-9a-f]{40})$', multiLine: true)
        .firstMatch(File('dependencies.properties').readAsStringSync())
        ?.group(1);
    // 1.11.0–1.20.4: 66d82b1 (muse.23); 1.20.5: c456a83 (muse branch after chuanyun.25, engine 1.19.34) keeps it
    expect(ref, 'c456a830a321c60efcb53ffd18319177fc7f5513');
  });
}
