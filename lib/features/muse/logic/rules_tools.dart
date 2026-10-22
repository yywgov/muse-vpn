// 穿云 1.4.0 - 分流 presets, the rule tester, custom hosts, rule import / export, remote rule-set
// links and the 「只代理海外应用」 template (pure logic, unit-tested).
// Presets are plain domain / IP lists shipped with the app (nothing to download, nothing that can
// fail on connect). All presets start off.
// Part of 穿云 (GPLv3).

import 'dart:convert';

import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

class MuseRulePreset {
  const MuseRulePreset({
    required this.key,
    required this.title,
    required this.outbound,
    this.domainSuffixes = const [],
    this.domainKeywords = const [],
    this.ipCidrs = const [],
    this.processNames = const [],
  });

  final String key;
  final String title;

  /// the default way; the user can change it
  final Outbound outbound;
  final List<String> domainSuffixes;
  final List<String> domainKeywords;
  final List<String> ipCidrs;
  final List<String> processNames;

  String get ruleName => 'preset:$key';
}

const museRulePresets = <MuseRulePreset>[
  MuseRulePreset(
    key: 'ai',
    title: 'AI（ChatGPT / Claude / Gemini 等）',
    outbound: Outbound.proxy,
    domainSuffixes: [
      'openai.com', 'chatgpt.com', 'oaistatic.com', 'oaiusercontent.com', 'sora.com',
      'anthropic.com', 'claude.ai', 'claudeusercontent.com',
      'gemini.google.com', 'aistudio.google.com', 'generativelanguage.googleapis.com', 'bard.google.com',
      'perplexity.ai', 'poe.com', 'x.ai', 'grok.com', 'mistral.ai', 'copilot.microsoft.com', 'huggingface.co',
    ],
  ),
  MuseRulePreset(
    key: 'streaming',
    title: '流媒体（Netflix / Disney+ / YouTube 等）',
    outbound: Outbound.proxy,
    domainSuffixes: [
      'netflix.com', 'netflix.net', 'nflxvideo.net', 'nflximg.net', 'nflxext.com', 'nflxso.net',
      'disneyplus.com', 'disney-plus.net', 'dssott.com', 'bamgrid.com',
      'youtube.com', 'googlevideo.com', 'ytimg.com', 'youtu.be', 'youtube-nocookie.com',
      'hbomax.com', 'max.com', 'hulu.com', 'primevideo.com', 'spotify.com', 'scdn.co', 'twitch.tv', 'tiktok.com',
      'tiktokv.com', 'tiktokcdn.com', 'byteoversea.com',
    ],
  ),
  MuseRulePreset(
    key: 'telegram',
    title: 'Telegram',
    outbound: Outbound.proxy,
    domainSuffixes: ['telegram.org', 't.me', 'telegram.me', 'tdesktop.com', 'telegra.ph', 'telesco.pe'],
    ipCidrs: [
      '91.105.192.0/23', '91.108.4.0/22', '91.108.8.0/21', '91.108.16.0/21', '91.108.56.0/22',
      '95.161.64.0/20', '149.154.160.0/20', '185.76.151.0/24',
      '2001:67c:4e8::/48', '2001:b28:f23c::/47', '2001:b28:f23f::/48', '2a0a:f280:203::/48',
    ],
  ),
  MuseRulePreset(
    key: 'games',
    title: '游戏下载直连',
    outbound: Outbound.direct,
    domainSuffixes: [
      'steamcontent.com', 'steamserver.net', 'dl.steam.clngaa.com', 'epicgames-download1.akamaized.net',
      'download.epicgames.com', 'blzddist1-a.akamaihd.net', 'gamecdn.blizzard.com', 'origin-a.akamaihd.net',
      'xboxlive.com', 'playstation.net', 'nintendo.net',
    ],
  ),
  MuseRulePreset(
    key: 'apple',
    title: '苹果服务直连',
    outbound: Outbound.direct,
    domainSuffixes: ['apple.com', 'icloud.com', 'icloud-content.com', 'mzstatic.com', 'cdn-apple.com', 'apple-cloudkit.com', 'aaplimg.com'],
  ),
  MuseRulePreset(
    key: 'microsoft',
    title: '微软服务直连',
    outbound: Outbound.direct,
    domainSuffixes: [
      'microsoft.com', 'windowsupdate.com', 'office.com', 'office.net', 'live.com', 'msftconnecttest.com',
      'msftncsi.com', 'onedrive.com', 'sharepoint.com', 'outlook.com', 'microsoftonline.com',
    ],
  ),
  MuseRulePreset(
    key: 'steam',
    title: 'Steam 商店走代理',
    outbound: Outbound.proxy,
    domainSuffixes: ['steampowered.com', 'steamcommunity.com', 'steamstatic.com', 'steam-chat.com'],
  ),
  MuseRulePreset(
    key: 'academic',
    title: '学术（Google 学术 / 期刊）',
    outbound: Outbound.proxy,
    domainSuffixes: [
      'scholar.google.com', 'scholar.googleusercontent.com', 'sci-hub.se', 'researchgate.net', 'arxiv.org',
      'sciencedirect.com', 'springer.com', 'nature.com', 'ieee.org', 'acm.org', 'jstor.org', 'wiley.com',
    ],
  ),
  MuseRulePreset(
    key: 'banks',
    title: '国内银行与支付直连',
    outbound: Outbound.direct,
    domainSuffixes: [
      'icbc.com.cn', 'ccb.com', 'abchina.com', 'boc.cn', 'bankcomm.com', 'cmbchina.com', 'psbc.com',
      'spdb.com.cn', 'cib.com.cn', 'cebbank.com', 'cmbc.com.cn', 'citicbank.com', 'pingan.com',
      'alipay.com', 'alipayobjects.com', 'tenpay.com', 'unionpay.com', '95516.com',
    ],
  ),
  MuseRulePreset(
    key: 'privacy',
    title: '隐私拦截（追踪与统计）',
    outbound: Outbound.block,
    domainSuffixes: [
      'doubleclick.net', 'google-analytics.com', 'googletagmanager.com', 'app-measurement.com',
      'scorecardresearch.com', 'hotjar.com', 'mixpanel.com', 'segment.io', 'adjust.com', 'appsflyer.com',
      'branch.io', 'umeng.com', 'growingio.com', 'sensorsdata.cn',
    ],
  ),
];

MuseRulePreset? museRulePreset(String key) => museRulePresets.where((p) => p.key == key).firstOrNull;

/// Enabled presets with the way the user chose: `{"ai": "proxy", "banks": "direct"}`.
Map<String, Outbound> museParsePresetChoice(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        if (museRulePreset(e.key) != null) e.key: museOutboundFromKey('${e.value}') ?? museRulePreset(e.key)!.outbound,
    };
  } catch (_) {
    return const {};
  }
}

String musePresetChoiceToRaw(Map<String, Outbound> choice) => jsonEncode({for (final e in choice.entries) e.key: museOutboundKey(e.value)});

String museOutboundKey(Outbound o) => switch (o) {
  Outbound.direct || Outbound.direct_with_fragment => 'direct',
  Outbound.block => 'block',
  _ => 'proxy',
};

Outbound? museOutboundFromKey(String k) => switch (k) {
  'direct' => Outbound.direct,
  'block' => Outbound.block,
  'proxy' => Outbound.proxy,
  _ => null,
};

String museOutboundTitle(Outbound o) => switch (o) {
  Outbound.direct || Outbound.direct_with_fragment => '直连',
  Outbound.block => '拦截',
  _ => '代理',
};

/// One block of custom hosts: `1.2.3.4 example.com` lines (# comments). Returns domain → IP.
Map<String, String> museParseHosts(String text) {
  final out = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final l = line.split('#').first.trim();
    if (l.isEmpty) continue;
    final parts = l.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final ip = parts.first;
    if (!_isIp(ip)) continue;
    for (final d in parts.skip(1)) {
      if (d.contains('.')) out[d.toLowerCase()] = ip;
    }
  }
  return out;
}

bool _isIp(String s) => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s) || (s.contains(':') && RegExp(r'^[0-9a-fA-F:]+$').hasMatch(s));

/// The rule list sent to the core: the user's own rules first, then the enabled presets, then the
/// built-in rules (国内直连 / 局域网 / 去广告); list_order follows this order.
List<Rule> museApplyPresets(List<Rule> rules, Map<String, Outbound> enabled) {
  if (enabled.isEmpty) return rules;
  final own = rules.where((r) => !r.name.startsWith('builtin:')).toList();
  final builtin = rules.where((r) => r.name.startsWith('builtin:')).toList();
  final presets = <Rule>[
    for (final p in museRulePresets)
      if (enabled.containsKey(p.key))
        Rule(
          name: p.ruleName,
          enabled: true,
          outbound: enabled[p.key],
          domainSuffixes: p.domainSuffixes,
          domainKeywords: p.domainKeywords,
          ipCidrs: p.ipCidrs,
          processNames: p.processNames,
        ),
  ];
  final out = <Rule>[];
  for (final r in [...own, ...presets, ...builtin]) {
    out.add(r.deepCopy()..listOrder = out.length);
  }
  return out;
}

// ---------------------------------------------------------------- tester

class MuseRuleMatch {
  const MuseRuleMatch(this.rule, this.outbound, this.reason);

  /// null = no rule matched (the default: through the node)
  final Rule? rule;
  final Outbound outbound;
  final String reason;
}

/// Which rule a destination hits, the way the core walks the list (first enabled match in
/// list order). [target] is a URL, a domain or an IP; [process] / [port] are optional.
/// Rule-sets (geosite / geoip lists) can't be read here: such a rule is reported as 「规则集」
/// only when its name says 国内 and the domain ends in .cn (a hint, not a guarantee).
MuseRuleMatch museTestRules(List<Rule> rules, String target, {String? process, int? port}) {
  var host = target.trim().toLowerCase();
  int? urlPort;
  if (host.contains('://')) {
    try {
      final u = Uri.parse(host);
      host = u.host;
      if (u.hasPort) urlPort = u.port;
      urlPort ??= u.scheme == 'http' ? 80 : 443;
    } catch (_) {}
  }
  host = host.split('/').first;
  final p = port ?? urlPort;
  final sorted = [...rules]..sort((a, b) => a.listOrder.compareTo(b.listOrder));
  for (final r in sorted) {
    if (!r.enabled) continue;
    final why = _matches(r, host, process, p);
    if (why != null) return MuseRuleMatch(r, r.outbound, why);
  }
  return const MuseRuleMatch(null, Outbound.proxy, '没有规则命中，走节点');
}

String? _matches(Rule r, String host, String? process, int? port) {
  final conds = <bool>[];
  String? why;
  final hasDomain = r.domains.isNotEmpty || r.domainSuffixes.isNotEmpty || r.domainKeywords.isNotEmpty || r.domainRegexes.isNotEmpty;
  if (hasDomain || r.ipCidrs.isNotEmpty) {
    String? hit;
    for (final d in r.domains) {
      if (host == d.toLowerCase()) hit = '域名 $d';
    }
    for (final d in r.domainSuffixes) {
      final s = d.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
      if (host == s || host.endsWith('.$s')) hit ??= '域名后缀 $s';
    }
    for (final k in r.domainKeywords) {
      if (host.contains(k.toLowerCase())) hit ??= '关键词 $k';
    }
    for (final re in r.domainRegexes) {
      try {
        if (RegExp(re).hasMatch(host)) hit ??= '正则 $re';
      } catch (_) {}
    }
    for (final c in r.ipCidrs) {
      if (museIpInCidr(host, c)) hit ??= 'IP 段 $c';
    }
    conds.add(hit != null);
    why = hit;
  }
  if (r.processNames.isNotEmpty) {
    final ok = process != null && r.processNames.any((e) => e.toLowerCase() == process.toLowerCase());
    conds.add(ok);
    if (ok) why ??= '进程 $process';
  }
  if (r.portRanges.isNotEmpty) {
    final ok = port != null && r.portRanges.any((e) => _portIn(port, e));
    conds.add(ok);
    if (ok) why ??= '端口 $port';
  }
  if (conds.isEmpty || conds.contains(false)) return null;
  return why;
}

bool _portIn(int port, String range) {
  final parts = range.split(':');
  final a = int.tryParse(parts.first.trim());
  final b = parts.length > 1 ? int.tryParse(parts[1].trim()) : a;
  if (a == null || b == null) return false;
  return port >= a && port <= b;
}

/// IPv4 CIDR membership (IPv6 is never matched here).
bool museIpInCidr(String ip, String cidr) {
  final parts = cidr.split('/');
  final base = _v4(parts.first);
  final addr = _v4(ip);
  if (base == null || addr == null) return false;
  final bits = parts.length > 1 ? int.tryParse(parts[1]) ?? 32 : 32;
  if (bits <= 0) return true;
  final mask = bits >= 32 ? 0xFFFFFFFF : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
  return (base & mask) == (addr & mask);
}

int? _v4(String s) {
  final p = s.split('.');
  if (p.length != 4) return null;
  var v = 0;
  for (final x in p) {
    final n = int.tryParse(x);
    if (n == null || n < 0 || n > 255) return null;
    v = (v << 8) | n;
  }
  return v;
}

// ---------------------------------------------------------------- import / export

/// The user's own rules as JSON (built-in rules are not exported: they come with the app).
String museExportRules(List<Rule> rules) => const JsonEncoder.withIndent('  ').convert({
  'chuanyun_rules': 1,
  'rules': [for (final r in rules) if (!r.name.startsWith('builtin:')) r.toProto3Json()],
});

/// Rules from [museExportRules] output (or a bare list of rule objects); throws FormatException.
List<Rule> museImportRules(String text) {
  final j = jsonDecode(text);
  final list = j is Map ? j['rules'] : j;
  if (list is! List) throw const FormatException('不是规则文件');
  final out = <Rule>[];
  for (final e in list) {
    final r = Rule()..mergeFromProto3Json(e, ignoreUnknownFields: true);
    if (r.name.startsWith('builtin:')) continue;
    out.add(r);
  }
  return out;
}

/// A remote rule-set link the core can load (sing-box `.srs` binary or `.json` source).
bool museIsRuleSetUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return false;
  final path = u.path.toLowerCase();
  return path.endsWith('.srs') || path.endsWith('.json');
}

/// 「只代理海外应用」: the Android per-app mode that sends only the listed apps through the node.
const museOverseasApps = [
  'com.google.android.youtube', 'com.google.android.gm', 'com.android.chrome', 'org.telegram.messenger',
  'com.twitter.android', 'com.instagram.android', 'com.facebook.katana', 'com.whatsapp', 'com.discord',
  'com.netflix.mediaclient', 'com.spotify.music', 'com.openai.chatgpt', 'com.anthropic.claude',
  'com.google.android.apps.bard', 'com.reddit.frontpage', 'com.zhiliaoapp.musically', 'com.github.android',
];
