// 穿云 1.6.4: domestic sites were slow with the app on. The fix is in the config the core builds
// (core 5.0.0-muse.18, v2/config/muse_dns.go + muse_dns_test.go: domestic-only direct DNS group,
// real TTLs with an expiring / optimistic cache, resolve before the geoip-cn direct rule). These
// tests pin the client side of it: the settings the app sends keep domestic traffic and DNS
// direct, and the app ships the core that has the fix.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Dirs extends AppDirectories {
  _Dirs(this.dir);
  final Directory dir;
  @override
  Future<Directories> build() async => (baseDir: dir, workingDir: dir, tempDir: dir);
}

/// The settings JSON the app sends to the core, built from [prefs].
Future<Map<String, dynamic>> _settings(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final shared = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('muse164');
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => Future.value(shared)),
      appDirectoriesProvider.overrideWith(() => _Dirs(dir)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(sharedPreferencesProvider.future);
  await c.read(appDirectoriesProvider.future);
  // keep the providers alive until their start-up microtasks (rules list) are done
  final sub = c.listen(ConfigOptions.singboxConfigOptions, (_, _) {});
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final json = jsonDecode(jsonEncode(sub.read().toJson())) as Map<String, dynamic>;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return json;
}

List<Map<String, dynamic>> _rules(Map<String, dynamic> settings) =>
    [for (final r in (settings['route-rule'] as Map<String, dynamic>)['rules'] as List) r as Map<String, dynamic>];

void main() {
  group('1.6.4 domestic sites go direct with domestic DNS', () {
    test('default settings: region CN, domestic direct DNS, rule mode keeps 国内直连 on', () async {
      final s = await _settings({});
      expect(s['region'], 'cn');
      expect(s['direct-dns-address'], 'udp://223.5.5.5');
      expect(s['enable-fake-dns'], isFalse, reason: 'Fake-IP would skip the direct DNS check of unlisted domestic sites');
      final rules = _rules(s);
      // 局域网 first, then 国内直连 (geosite-{region} + geoip-{region}) switched on and sent direct
      expect(rules.first['name'], museLanRuleName);
      expect(rules.first['outbound'], 'direct');
      expect(rules.first['ip_cidr'], containsAll(['10.0.0.0/8', '192.168.0.0/16', '172.16.0.0/12']));
      final region = rules.firstWhere((r) => r['name'] == 'builtin:bypassRegion');
      expect(region['enabled'], isTrue);
      expect(region['outbound'], 'direct');
      final sets = (region['rule_set'] as List).cast<String>();
      expect(sets.any((u) => u.endsWith('/geosite-{region}.srs')), isTrue);
      expect(sets.any((u) => u.endsWith('/geoip-{region}.srs')), isTrue);
      // nothing blocks domestic QUIC by default (屏蔽 QUIC is off; the core only refuses proxied QUIC)
      expect(rules.where((r) => r['name'] == museBlockQuicRuleName), isEmpty);
    });

    test('a stored foreign direct DNS never reaches the core (fixed to 223.5.5.5)', () async {
      final s = await _settings({'direct-dns-address': 'udp://8.8.8.8'});
      expect(s['direct-dns-address'], 'udp://223.5.5.5');
    });

    test('a stored region other than CN is overridden', () async {
      final s = await _settings({'region': 'other'});
      expect(s['region'], 'cn');
      expect(_rules(s).where((r) => r['name'] == 'builtin:bypassRegion'), isNotEmpty);
    });

    test('the app ships core 5.0.0-muse.18 (the DNS / direct-routing fix)', () {
      final props = File('dependencies.properties').readAsStringSync();
      expect(RegExp(r'muse\.core\.version=(\S+)').firstMatch(props)?.group(1), '5.0.0-muse.18');
      expect(museCoreRelease, '5.0.0-muse.18');
    });

    test('version 1.7.0+170 carries the 1.6.4 fixes in its 更新说明', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'^version: (\S+)', multiLine: true).firstMatch(pubspec)?.group(1), '1.7.0+170');
      expect(museChangelog.keys.first, '1.7.0');
      expect(museChangelog['1.7.0'], hasLength(6));
      final md = File('CHANGELOG.md').readAsStringSync();
      expect(md.indexOf('### 1.7.0'), lessThan(md.indexOf('### 1.6.3')));
    });
  });
}
