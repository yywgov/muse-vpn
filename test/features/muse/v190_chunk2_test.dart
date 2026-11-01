// 穿云 1.9.0 (batch 2, chunk 1b): batch rule test, sing-box rule export, 恢复推荐 DNS,
// CHANGELOG.md in step with the in-app changelog (#213), PR template (#229).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

void main() {
  group('#64 several targets', () {
    test('split on lines, spaces and commas; blanks and repeats dropped', () {
      expect(museSplitTargets('a.com\nb.com, c.com  A.com\n\n'), ['a.com', 'b.com', 'c.com']);
      expect(museSplitTargets('  '), isEmpty);
      expect(museSplitTargets('a.com，b.com；c.com、d.com'), ['a.com', 'b.com', 'c.com', 'd.com']);
    });
    test('capped', () {
      final many = [for (var i = 0; i < 80; i++) 'h$i.com'].join('\n');
      expect(museSplitTargets(many).length, 50);
      expect(museSplitTargets(many, max: 3).length, 3);
    });
    test('each target is tested on its own', () {
      final rules = [
        Rule(name: 'r1', enabled: true, outbound: Outbound.block, domainSuffixes: ['ads.com']),
        Rule(name: 'r2', enabled: true, outbound: Outbound.direct, domainSuffixes: ['cn.com']),
      ];
      final got = [for (final t in museSplitTargets('x.ads.com y.cn.com')) museTestRules(rules, t).outbound];
      expect(got, [Outbound.block, Outbound.direct]);
    });
  });

  group('#67 sing-box export', () {
    final rules = [
      Rule(name: 'builtin:bypassLan', enabled: true, outbound: Outbound.direct, ipCidrs: ['10.0.0.0/8']),
      Rule(name: 'a', enabled: true, outbound: Outbound.proxy, domainSuffixes: ['openai.com'], domainKeywords: ['gpt']),
      Rule(name: 'b', enabled: true, outbound: Outbound.block, domains: ['ads.example.com'], network: Network.udp, portRanges: ['443']),
      Rule(name: 'c', enabled: true, outbound: Outbound.direct, processNames: ['chrome.exe'], portRanges: ['1000-2000']),
      Rule(name: 'off', enabled: false, outbound: Outbound.proxy, domainSuffixes: ['x.com']),
      Rule(name: 'empty', enabled: true, outbound: Outbound.proxy),
    ];
    test('own rules only, mapped to sing-box fields', () {
      final j = jsonDecode(museExportRulesSingBox(rules)) as Map;
      final out = ((j['route'] as Map)['rules'] as List).cast<Map>();
      expect(out.length, 3);
      expect(out[0], {'domain_suffix': ['openai.com'], 'domain_keyword': ['gpt'], 'outbound': 'proxy'});
      expect(out[1]['domain'], ['ads.example.com']);
      expect(out[1]['action'], 'reject');
      expect(out[1].containsKey('outbound'), isFalse);
      expect(out[1]['network'], 'udp');
      expect(out[2]['outbound'], 'direct');
      expect(out[2]['port_range'], ['1000:2000']);
      expect(out[2]['process_name'], ['chrome.exe']);
    });
    test('no rules gives an empty list, still valid json', () {
      final j = jsonDecode(museExportRulesSingBox(const [])) as Map;
      expect((j['route'] as Map)['rules'], isEmpty);
    });
  });

  group('#213 CHANGELOG.md follows the in-app changelog', () {
    test('every in-app version from 1.3.0 has an entry', () {
      final md = File('CHANGELOG.md').readAsStringSync();
      final missing = <String>[];
      for (final v in museChangelog.keys) {
        final parts = v.split('.').map(int.parse).toList();
        if (parts[0] == 1 && parts[1] < 3) continue;
        if (!md.contains('### $v - ')) missing.add(v);
      }
      expect(missing, isEmpty);
    });
  });

  test('#229 pull request template lists the UI self-check', () {
    final t = File('.github/pull_request_template.md').readAsStringSync();
    for (final w in ['深色', '浅色', '窄屏', '2×', 'token']) {
      expect(t, contains(w));
    }
  });
}
