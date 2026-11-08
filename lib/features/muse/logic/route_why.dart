// 穿云 1.15.0 R24 - 连接详情「为什么走这条」：把内核报告的规则、出站链路翻成一句中文。
// 标准内核（sing-box）报告 `rule_set=[geosite-cn] => route(direct)`，兼容内核（mihomo）报告
// `RuleSet` + rulePayload `geosite-cn`；没有规则命中时是 `final` / `Match`。只读，不改任何行为。
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/local_api/local_api_client.dart';

/// 一条连接走向的说明。
class MuseRouteWhy {
  const MuseRouteWhy({required this.rule, required this.outbound, required this.node, required this.summary});

  /// 命中的规则（中文）；没有规则命中时是「未命中规则（默认出站）」
  final String rule;

  /// 规则交给的出站（链路最外层，通常是代理组或「直连」）
  final String outbound;

  /// 实际经过的节点（链路最内层）；与出站相同时为空
  final String node;

  /// 一句话
  final String summary;
}

const _singKeys = <String, String>{
  'domain': '域名',
  'domain_suffix': '域名后缀',
  'domain_keyword': '域名关键词',
  'domain_regex': '域名正则',
  'rule_set': '规则集',
  'geosite': '域名库',
  'geoip': 'IP 库',
  'ip_cidr': 'IP 段',
  'source_ip_cidr': '来源 IP 段',
  'ip_is_private': '局域网地址',
  'port': '端口',
  'port_range': '端口范围',
  'source_port': '来源端口',
  'network': '网络类型',
  'protocol': '协议',
  'inbound': '入站',
  'package_name': '应用',
  'process_name': '进程',
  'process_path': '进程路径',
  'user': '用户',
  'clash_mode': '代理模式',
  'wifi_ssid': 'Wi-Fi 名称',
  'ip_version': 'IP 版本',
  'query_type': '查询类型',
};

const _mihomoKeys = <String, String>{
  'domain': '域名',
  'domainsuffix': '域名后缀',
  'domainkeyword': '域名关键词',
  'domainregex': '域名正则',
  'ruleset': '规则集',
  'geosite': '域名库',
  'geoip': 'IP 库',
  'ipcidr': 'IP 段',
  'ipcidr6': 'IP 段',
  'srcipcidr': '来源 IP 段',
  'dstport': '端口',
  'srcport': '来源端口',
  'network': '网络类型',
  'processname': '进程',
  'processpath': '进程路径',
  'inbound': '入站',
};

const _outboundNames = <String, String>{
  'direct': '直连',
  'block': '拦截',
  'reject': '拦截',
  'dns-out': '内置 DNS',
  'select': '节点选择',
  'proxy': '代理',
  'auto': '自动选择',
  'global': '全局',
};

/// 出站标签的中文名（未知的原样返回）。
String museOutboundName(String tag) => _outboundNames[tag.toLowerCase()] ?? tag;

String _items(String v) {
  var s = v.trim();
  if (s.startsWith('[') && s.endsWith(']')) s = s.substring(1, s.length - 1).trim();
  final parts = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.length > 3) return '${parts.take(3).join('、')} 等 ${parts.length} 项';
  return parts.join('、');
}

/// 规则部分（不含动作）翻成中文。
String museRuleText(String rule) {
  var r = rule.trim();
  final arrow = r.indexOf(' => ');
  if (arrow >= 0) r = r.substring(0, arrow).trim();
  if (r.isEmpty || r == 'final' || r.toLowerCase() == 'match') return '未命中规则（默认出站）';
  // 兼容内核：RuleSet(geosite-cn)
  final mh = RegExp(r'^([A-Za-z0-9-]+)\((.*)\)$').firstMatch(r);
  if (mh != null && !r.contains('=')) {
    final k = mh.group(1)!.toLowerCase().replaceAll('-', '');
    final v = mh.group(2)!;
    if (k == 'match') return '未命中规则（默认出站）';
    final name = _mihomoKeys[k];
    return name == null ? r : (v.isEmpty ? name : '$name $v');
  }
  if (_mihomoKeys.containsKey(r.toLowerCase())) return _mihomoKeys[r.toLowerCase()]!;
  var invert = false;
  if (r.startsWith('!(') && r.endsWith(')')) {
    invert = true;
    r = r.substring(2, r.length - 1);
  }
  final out = <String>[];
  for (final m in RegExp(r'([a-z_]+)=(\[[^\]]*\]|\S+)').allMatches(r)) {
    final k = m.group(1)!;
    final v = m.group(2)!;
    final name = _singKeys[k] ?? k;
    if (k == 'ip_is_private') {
      out.add(v == 'true' ? '局域网地址' : '非局域网地址');
    } else {
      out.add('$name ${_items(v)}');
    }
  }
  if (out.isEmpty) return r;
  final s = out.join(' 且 ');
  return invert ? '不符合（$s）' : s;
}

/// 动作部分：`route(direct)` → 出站 tag；`reject` → 拦截；没有动作时为空。
String museRuleActionTarget(String rule) {
  final arrow = rule.indexOf(' => ');
  if (arrow < 0) return '';
  final a = rule.substring(arrow + 4).trim();
  final m = RegExp(r'^route\(([^)]*)\)').firstMatch(a);
  if (m != null) return m.group(1)!.trim();
  if (a.startsWith('reject')) return 'reject';
  if (a.startsWith('hijack-dns')) return 'dns-out';
  return a;
}

/// [c] 为什么走这条。链路 chains 由内核给出，第一个是实际节点，最后一个是规则选中的出站。
MuseRouteWhy museRouteWhy(MuseConn c) {
  final raw = c.rule;
  final rule = museRuleText(raw);
  final target = museRuleActionTarget(raw);
  final outboundTag = c.chains.isNotEmpty ? c.chains.last : target;
  final nodeTag = c.chains.isNotEmpty ? c.chains.first : '';
  final outbound = outboundTag.isEmpty ? '' : museOutboundName(outboundTag);
  final node = nodeTag.isEmpty || nodeTag == outboundTag ? '' : museOutboundName(nodeTag);
  final via = c.chains.length > 2 ? '（经 ${c.chains.reversed.skip(1).take(c.chains.length - 2).map(museOutboundName).join(' → ')}）' : '';
  final String summary;
  if (target == 'reject' || outboundTag.toLowerCase() == 'block' || outboundTag.toLowerCase() == 'reject') {
    summary = '$rule → 已拦截';
  } else if (outbound.isEmpty) {
    summary = rule;
  } else if (node.isEmpty) {
    summary = '$rule → 交给「$outbound」';
  } else {
    summary = '$rule → 交给「$outbound」$via → 实际经节点「$node」';
  }
  return MuseRouteWhy(rule: rule, outbound: outbound, node: node, summary: summary);
}
