// 穿云 1.12.0 - 从连接一键加规则：在「活动 › 连接」详情里把一个网站设为 直连 / 走代理 /
// 走指定节点。「仅本次」的规则只放在内存里，断开连接即失效。规则排在 局域网 与 屏蔽 之后、
// 用户其他规则之前，热重载生效，提示里可撤销。纯逻辑（有测试）。
// Part of 穿云 (GPLv3).

import 'dart:convert';

import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// 规则名（规则页据此标注「来自连接」）
const museQuickRuleName = 'muse:quick';

enum MuseQuickWay {
  direct('直连'),
  proxy('走代理');

  const MuseQuickWay(this.title);

  final String title;
}

/// 一条从连接加的规则：[host]（含子域名）走 [way]。
class MuseQuickRule {
  const MuseQuickRule(this.host, this.way);

  final String host;
  final MuseQuickWay way;

  Map<String, String> toJson() => {'host': host, 'way': way.name};

  static MuseQuickRule? fromJson(Object? j) {
    if (j is! Map) return null;
    final host = '${j['host'] ?? ''}'.trim().toLowerCase();
    final way = MuseQuickWay.values.where((w) => w.name == j['way']).firstOrNull;
    if (host.isEmpty || way == null) return null;
    return MuseQuickRule(host, way);
  }

  @override
  bool operator ==(Object other) => other is MuseQuickRule && other.host == host && other.way == way;

  @override
  int get hashCode => Object.hash(host, way);
}

List<MuseQuickRule> museParseQuickRules(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! List) return const [];
    return [for (final e in j) ?MuseQuickRule.fromJson(e)];
  } catch (_) {
    return const [];
  }
}

String museQuickRulesToRaw(List<MuseQuickRule> rules) => jsonEncode([for (final r in rules) r.toJson()]);

/// [rules] with [host] set to [way]: one rule per host (a new choice replaces the old one).
List<MuseQuickRule> museSetQuickRule(List<MuseQuickRule> rules, String host, MuseQuickWay way) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return rules;
  return [for (final r in rules) if (r.host != h) r, MuseQuickRule(h, way)];
}

List<MuseQuickRule> museRemoveQuickRule(List<MuseQuickRule> rules, String host) {
  final h = host.trim().toLowerCase();
  return [for (final r in rules) if (r.host != h) r];
}

bool _isIp(String s) => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s) || (s.contains(':') && RegExp(r'^[0-9a-fA-F:]+$').hasMatch(s));

/// The route rules for [quick] (saved + 仅本次; 仅本次 wins for the same host), placed right after
/// 局域网 and 屏蔽 so they win over the user's other rules.
List<Rule> museApplyQuickRules(List<Rule> rules, List<MuseQuickRule> quick) {
  if (quick.isEmpty) return rules;
  final byHost = <String, MuseQuickRule>{for (final q in quick) q.host: q};
  final add = <Rule>[];
  for (final way in MuseQuickWay.values) {
    final hosts = [for (final q in byHost.values) if (q.way == way) q.host];
    if (hosts.isEmpty) continue;
    final out = way == MuseQuickWay.direct ? Outbound.direct : Outbound.proxy;
    final domains = [for (final h in hosts) if (!_isIp(h)) h];
    final ips = [for (final h in hosts) if (_isIp(h)) h.contains(':') ? '$h/128' : '$h/32'];
    if (domains.isNotEmpty) add.add(Rule(name: '$museQuickRuleName:${way.name}', enabled: true, outbound: out, domainSuffixes: domains));
    if (ips.isNotEmpty) add.add(Rule(name: '$museQuickRuleName:${way.name}:ip', enabled: true, outbound: out, ipCidrs: ips));
  }
  var head = 0;
  while (head < rules.length && (rules[head].name == museLanRuleName || rules[head].name.startsWith(museBlockedHostsRuleName))) {
    head++;
  }
  final list = [...rules.take(head), ...add, ...rules.skip(head)];
  return [for (var k = 0; k < list.length; k++) list[k].deepCopy()..listOrder = k];
}

/// 走指定节点：[rules] with [host] added to [node]'s 指定节点 rule (a new rule when there is none);
/// the host is taken out of every other node's rule first.
List<MuseNodeRule> museAddHostToNodeRule(List<MuseNodeRule> rules, String node, String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty || node.isEmpty) return rules;
  var found = false;
  final out = <MuseNodeRule>[];
  for (final r in rules) {
    final domains = [for (final d in r.domains) if (d != h) d];
    if (r.node == node) {
      found = true;
      domains.add(h);
    }
    final next = MuseNodeRule(node: r.node, domains: domains, processes: r.processes, packages: r.packages);
    if (!next.isEmpty) out.add(next);
  }
  if (!found) out.add(MuseNodeRule(node: node, domains: [h]));
  return out;
}

/// 仅本次的指定节点规则叠加在已保存的之上（同一网站以仅本次为准）。
List<MuseNodeRule> museMergeNodeRules(List<MuseNodeRule> saved, List<MuseNodeRule> temp) {
  var out = saved;
  for (final t in temp) {
    for (final d in t.domains) {
      out = museAddHostToNodeRule(out, t.node, d);
    }
  }
  return out;
}
