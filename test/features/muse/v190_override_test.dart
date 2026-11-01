// 穿云 1.9.0 #15 - 订阅覆写: composition at connect time, never written into the subscription.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart' show museLanRuleName;
import 'package:hiddify/features/muse/logic/sub_override.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

const _json =
    '{"outbounds":[{"type":"vless","tag":"香港 01","server":"a"},{"type":"vless","tag":"日本 01","server":"b"},{"type":"selector","tag":"select","outbounds":["香港 01","日本 01"]},{"type":"direct","tag":"direct"}]}';

const _yaml = '''
proxies:
  - {name: 香港 01, type: ss, server: a, port: 1, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: 节点选择, type: select, proxies: [香港 01]}
rules:
  - MATCH,节点选择
''';

const _group = MuseOverrideGroup(name: '港', filter: '香港');
const _rule = MuseOverrideRule(match: MuseOverrideMatch.domainSuffix, value: 'example.com', target: MuseOverrideTarget.direct);

Map<String, dynamic> _routeRule() => RouteRule(
  rules: [
    Rule(listOrder: 0, enabled: true, name: museLanRuleName, outbound: Outbound.direct),
    Rule(listOrder: 1, enabled: true, name: 'cn', outbound: Outbound.direct, ruleSets: ['geosite-cn']),
  ],
).toProto3Json()! as Map<String, dynamic>;

void main() {
  group('no override: the core gets exactly what it got before', () {
    test('rules: the same map instance, byte-identical encoding', () {
      final rr = _routeRule();
      final before = jsonEncode(rr);
      for (final o in [null, const MuseSubOverride(), const MuseSubOverride(enabled: false, rules: [_rule])]) {
        final out = museApplyOverrideRules(rr, o);
        expect(identical(out, rr), isTrue);
        expect(jsonEncode(out), before);
      }
    });

    test('body: no runtime copy; the core is started on the profile itself', () async {
      final dir = await Directory.systemTemp.createTemp('ovr');
      addTearDown(() => dir.delete(recursive: true));
      final p = File('${dir.path}/1.json')..writeAsStringSync(_json);
      // a stale copy from an earlier override is removed
      File(museOverrideRunPath(p.path)).writeAsStringSync('old');
      expect(await museComposeRunFile(p.path, null), p.path);
      expect(await museComposeRunFile(p.path, const MuseSubOverride(rules: [_rule])), p.path);
      expect(File(museOverrideRunPath(p.path)).existsSync(), isFalse);
      expect(p.readAsStringSync(), _json);
      expect(museOverrideBody(_json, const MuseSubOverride()), isNull);
    });

    test('the repository passes the options unchanged when nothing is added', () {
      final src = File('lib/features/connection/data/connection_repository.dart').readAsStringSync();
      expect(src, contains('identical(rr, options.routeRule) ? options : options.copyWith(routeRule: rr)'));
      // the snapshot (compared with the settings for hot reload) stays the app's own options
      expect(src, contains('_configOptionsSnapshot = options;'));
      expect(src, contains('runPath(activeProfile).flatMap((path) => singbox.start(path'));
    });
  });

  group('rules', () {
    test('inserted right after 局域网, renumbered, both targets mapped', () {
      final out = museApplyOverrideRules(
        _routeRule(),
        const MuseSubOverride(rules: [_rule, MuseOverrideRule(match: MuseOverrideMatch.ipCidr, value: '1.2.3.0/24', target: MuseOverrideTarget.block)]),
      );
      final rr = RouteRule.create()..mergeFromProto3Json(out);
      expect(rr.rules.map((r) => r.name).toList(), [museLanRuleName, 'override:1', 'override:2', 'cn']);
      expect(rr.rules.map((r) => r.listOrder).toList(), [0, 1, 2, 3]);
      expect(rr.rules[1].domainSuffixes, ['example.com']);
      expect(rr.rules[1].outbound, Outbound.direct);
      expect(rr.rules[2].ipCidrs, ['1.2.3.0/24']);
      expect(rr.rules[2].outbound, Outbound.block);
      // the field names 兼容内核 reads (snake case)
      expect(jsonEncode(out), contains('"domain_suffix":["example.com"]'));
    });
  });

  group('body', () {
    test('JSON: extra nodes and a filtered group appended; nothing of the subscription removed', () {
      final out = museOverrideBody(
        _json,
        const MuseSubOverride(nodes: ['vless://x@h:1#香港 02'], groups: [_group, MuseOverrideGroup(name: 'select')]),
        extraOutbounds: [
          {'type': 'vless', 'tag': '香港 01', 'server': 'c'},
        ],
      )!;
      final obs = (jsonDecode(out) as Map)['outbounds'] as List;
      final tags = obs.map((e) => (e as Map)['tag']).toList();
      expect(tags.take(4), ['香港 01', '日本 01', 'select', 'direct']);
      expect(tags, contains('香港 01 2')); // a clashing name gets a suffix
      final g = obs.firstWhere((e) => (e as Map)['tag'] == '港') as Map;
      expect(g['type'], 'selector');
      expect(g['outbounds'], ['香港 01', '香港 01 2']);
      // a group named like one of the subscription's own is not added again
      expect(tags.where((t) => t == 'select').length, 1);
    });

    test('JSON: a group no node matches is left out (it would stop the core)', () {
      final out = museOverrideBody(_json, const MuseSubOverride(groups: [MuseOverrideGroup(name: '美国', filter: '美国')]))!;
      expect(out, isNot(contains('美国')));
    });

    test('YAML (兼容内核): groups with include-all + filter, extra nodes as a local file provider', () {
      final out = museOverrideBody(_yaml, const MuseSubOverride(nodes: ['ss://a@b:1#x'], groups: [_group]), nodesPath: '/p/1.json.override-nodes')!;
      expect(out, contains('proxy-groups:\n  - {name: "港", type: select, include-all: true, filter: "香港"}\n  - {name: 节点选择'));
      expect(out, contains('proxy-providers:\n  $museOverrideProvider: {type: file, path: "/p/1.json.override-nodes"}'));
      expect(out, startsWith('proxies:'));
      expect(out, contains('MATCH,节点选择'));
    });

    test('YAML list at column 0 keeps its indent', () {
      const y = 'proxies:\n- {name: a, type: ss}\nproxy-groups:\n- {name: g, type: select, proxies: [a]}\n';
      final out = museOverrideBody(y, const MuseSubOverride(groups: [MuseOverrideGroup(name: 'x', urlTest: true)]))!;
      expect(out, contains('proxy-groups:\n- {name: "x", type: url-test, include-all: true}\n- {name: g'));
    });

    test('links: extra links appended', () {
      const links = 'vless://a@b:1#one\n';
      expect(museOverrideBody(links, const MuseSubOverride(nodes: ['ss://x@y:2#two'])), 'vless://a@b:1#one\nss://x@y:2#two\n');
    });
  });

  test('a subscription update keeps the override: it applies to the new body, the profile is only read', () async {
    final dir = await Directory.systemTemp.createTemp('ovr');
    addTearDown(() => dir.delete(recursive: true));
    final p = File('${dir.path}/1.json')..writeAsStringSync(_json);
    const o = MuseSubOverride(groups: [_group]);
    final run = await museComposeRunFile(p.path, o);
    expect(run, museOverrideRunPath(p.path));
    expect(p.readAsStringSync(), _json);
    // the update rewrites the profile only
    final updated = _json.replaceAll('香港 01', '香港 09');
    p.writeAsStringSync(updated);
    await museComposeRunFile(p.path, o);
    expect(File(run).readAsStringSync(), contains('"香港 09"'));
    expect(p.readAsStringSync(), updated);
  });

  test('extra links are converted only for a JSON body', () async {
    final dir = await Directory.systemTemp.createTemp('ovr');
    addTearDown(() => dir.delete(recursive: true));
    final p = File('${dir.path}/1.json')..writeAsStringSync(_yaml);
    var asked = 0;
    await museComposeRunFile(p.path, const MuseSubOverride(nodes: ['ss://a@b:1#x']), convertLinks: (l) async {
      asked++;
      return const [];
    });
    expect(asked, 0);
    expect(File(museOverrideNodesPath(p.path)).readAsStringSync(), 'ss://a@b:1#x\n');
  });

  test('stored by profile id; empty entries dropped; broken value reads as none; synced', () {
    final all = {'a': const MuseSubOverride(rules: [_rule]), 'b': const MuseSubOverride()};
    final enc = museEncodeOverrides(all);
    expect(museParseOverrides(enc).keys, ['a']);
    expect(museParseOverrides(enc)['a']!.rules.single.value, 'example.com');
    expect(museParseOverrides('not json'), isEmpty);
    expect(File('lib/features/muse/data/sync_service.dart').readAsStringSync(), contains("'muse_sub_overrides': MusePrefs.subOverrides"));
  });

  test('no script engine, no polling, no upstream name in the new files', () {
    for (final f in ['lib/features/muse/logic/sub_override.dart', 'lib/features/muse/config/sub_override_page.dart']) {
      // the Dart package name in imports is not text
      final s = File(f).readAsLinesSync().where((l) => !l.startsWith('import ')).join('\n');
      expect(s.toLowerCase(), isNot(contains('hiddify')));
      expect(s, isNot(contains('Timer.periodic')));
      expect(s.toLowerCase(), isNot(contains('flclash')));
      expect(s.toLowerCase(), isNot(contains('javascript')));
    }
  });
}
