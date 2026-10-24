// 穿云 1.4.0 - 分流 presets, the rule tester, custom hosts, rule import / export, remote rule-set
// links and the 「只代理海外应用」 template (pure logic, unit-tested).
// Presets are plain domain / IP lists shipped with the app (nothing to download, nothing that can
// fail on connect). All presets start off.
// Part of 穿云 (GPLv3).

import 'dart:convert';

import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// 1.4.1: where a preset is listed on the 分流 page (the list order, not the rule order).
enum MusePresetGroup {
  ai('AI 与搜索'),
  streaming('流媒体'),
  social('社交'),
  dev('开发与学术'),
  shopping('购物与支付'),
  games('游戏'),
  domestic('国内直连'),
  download('下载'),
  privacy('隐私');

  const MusePresetGroup(this.title);

  final String title;
}

/// Where the bundled rule-sets come from (the core keeps them updated in the background; the
/// copies in assets/rule-sets are used at connect, so nothing is downloaded then).
const museGeositeBase = 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/';

String museGeositeUrl(String name) => '${museGeositeBase}geosite-$name.srs';

class MuseRulePreset {
  const MuseRulePreset({
    required this.key,
    required this.title,
    required this.outbound,
    this.group = MusePresetGroup.ai,
    this.domainSuffixes = const [],
    this.domainKeywords = const [],
    this.ipCidrs = const [],
    this.processNames = const [],
    this.packageNames = const [],
    this.geosites = const [],
  });

  final String key;
  final String title;
  final MusePresetGroup group;

  /// the default way; the user can change it
  final Outbound outbound;
  final List<String> domainSuffixes;
  final List<String> domainKeywords;
  final List<String> ipCidrs;
  final List<String> processNames;

  /// Android apps (1.4.1)
  final List<String> packageNames;

  /// bundled geosite rule-sets (assets/rule-sets/geosite-<name>.srs) (1.4.1)
  final List<String> geosites;

  String get ruleName => 'preset:$key';

  List<String> get ruleSetUrls => [for (final g in geosites) museGeositeUrl(g)];

  /// Text the 分流 page search looks in.
  String get searchText => '$title $key ${domainSuffixes.join(' ')} ${geosites.join(' ')}'.toLowerCase();
}

/// All presets, in the order their rules are checked: specific services before the broader
/// lists that also contain them (YouTube before Google and 其他流媒体, 隐私拦截 first so blocking
/// wins over a proxied Google), so a service set on its own overrides the broad preset.
const museRulePresets = <MuseRulePreset>[
  MuseRulePreset(
    key: 'privacy',
    title: '隐私拦截（追踪与统计）',
    group: MusePresetGroup.privacy,
    outbound: Outbound.block,
    domainSuffixes: [
      'doubleclick.net', 'google-analytics.com', 'googletagmanager.com', 'app-measurement.com',
      'scorecardresearch.com', 'hotjar.com', 'mixpanel.com', 'segment.io', 'adjust.com', 'appsflyer.com',
      'branch.io', 'umeng.com', 'growingio.com', 'sensorsdata.cn',
    ],
  ),
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
    key: 'academic',
    title: '学术（Google 学术 / 期刊）',
    group: MusePresetGroup.dev,
    outbound: Outbound.proxy,
    domainSuffixes: [
      'scholar.google.com', 'scholar.googleusercontent.com', 'sci-hub.se', 'researchgate.net', 'arxiv.org',
      'sciencedirect.com', 'springer.com', 'nature.com', 'ieee.org', 'acm.org', 'jstor.org', 'wiley.com',
    ],
  ),
  MuseRulePreset(
    key: 'youtube',
    title: 'YouTube',
    group: MusePresetGroup.streaming,
    outbound: Outbound.proxy,
    geosites: ['youtube'],
    domainSuffixes: ['youtube.com', 'googlevideo.com', 'ytimg.com', 'youtu.be', 'youtube-nocookie.com', 'youtubei.googleapis.com'],
  ),
  MuseRulePreset(
    key: 'netflix',
    title: 'Netflix',
    group: MusePresetGroup.streaming,
    outbound: Outbound.proxy,
    geosites: ['netflix'],
    domainSuffixes: ['netflix.com', 'netflix.net', 'nflxvideo.net', 'nflximg.net', 'nflxext.com', 'nflxso.net'],
  ),
  MuseRulePreset(
    key: 'spotify',
    title: 'Spotify',
    group: MusePresetGroup.streaming,
    outbound: Outbound.proxy,
    geosites: ['spotify'],
    domainSuffixes: ['spotify.com', 'scdn.co', 'spotifycdn.com', 'spoti.fi'],
  ),
  MuseRulePreset(
    key: 'tiktok',
    title: 'TikTok',
    group: MusePresetGroup.streaming,
    outbound: Outbound.proxy,
    geosites: ['tiktok'],
    domainSuffixes: ['tiktok.com', 'tiktokv.com', 'tiktokcdn.com', 'byteoversea.com', 'ibytedtos.com', 'muscdn.com'],
  ),
  MuseRulePreset(
    key: 'streaming',
    title: '其他流媒体（Disney+ / HBO / Prime Video 等）',
    group: MusePresetGroup.streaming,
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
    key: 'google',
    title: 'Google',
    outbound: Outbound.proxy,
    geosites: ['google'],
    domainSuffixes: ['google.com', 'googleapis.com', 'gstatic.com', 'gmail.com', 'googleusercontent.com', 'ggpht.com', 'gvt1.com'],
  ),
  MuseRulePreset(
    key: 'telegram',
    title: 'Telegram',
    group: MusePresetGroup.social,
    outbound: Outbound.proxy,
    domainSuffixes: ['telegram.org', 't.me', 'telegram.me', 'tdesktop.com', 'telegra.ph', 'telesco.pe'],
    ipCidrs: [
      '91.105.192.0/23', '91.108.4.0/22', '91.108.8.0/21', '91.108.16.0/21', '91.108.56.0/22',
      '95.161.64.0/20', '149.154.160.0/20', '185.76.151.0/24',
      '2001:67c:4e8::/48', '2001:b28:f23c::/47', '2001:b28:f23f::/48', '2a0a:f280:203::/48',
    ],
  ),
  MuseRulePreset(
    key: 'twitter',
    title: 'X / Twitter',
    group: MusePresetGroup.social,
    outbound: Outbound.proxy,
    geosites: ['twitter'],
    domainSuffixes: ['x.com', 'twitter.com', 'twimg.com', 't.co', 'twttr.com'],
  ),
  MuseRulePreset(
    key: 'meta',
    title: 'Meta（Facebook / Instagram / WhatsApp）',
    group: MusePresetGroup.social,
    outbound: Outbound.proxy,
    geosites: ['facebook', 'instagram', 'whatsapp'],
    domainSuffixes: ['facebook.com', 'fbcdn.net', 'fb.com', 'messenger.com', 'instagram.com', 'cdninstagram.com', 'whatsapp.com', 'whatsapp.net'],
  ),
  MuseRulePreset(
    key: 'discord',
    title: 'Discord',
    group: MusePresetGroup.social,
    outbound: Outbound.proxy,
    geosites: ['discord'],
    domainSuffixes: ['discord.com', 'discord.gg', 'discordapp.com', 'discordapp.net', 'discord.media'],
  ),
  MuseRulePreset(
    key: 'dev',
    title: 'GitHub / 开发者（GitHub、npm、PyPI、Docker Hub）',
    group: MusePresetGroup.dev,
    outbound: Outbound.proxy,
    geosites: ['github', 'npmjs', 'docker'],
    domainSuffixes: [
      'github.com', 'githubusercontent.com', 'githubassets.com', 'github.io', 'ghcr.io',
      'npmjs.org', 'npmjs.com', 'pypi.org', 'pythonhosted.org', 'docker.com', 'docker.io',
    ],
  ),
  MuseRulePreset(
    key: 'steam',
    title: 'Steam 商店走代理',
    group: MusePresetGroup.games,
    outbound: Outbound.proxy,
    domainSuffixes: ['steampowered.com', 'steamcommunity.com', 'steamstatic.com', 'steam-chat.com'],
  ),
  MuseRulePreset(
    key: 'payments',
    title: '海外支付（PayPal / Stripe）',
    group: MusePresetGroup.shopping,
    outbound: Outbound.proxy,
    geosites: ['paypal', 'stripe'],
    domainSuffixes: ['paypal.com', 'paypalobjects.com', 'paypal.me', 'stripe.com', 'stripe.network', 'stripecdn.com'],
  ),
  MuseRulePreset(
    key: 'crypto',
    title: '加密货币交易所',
    group: MusePresetGroup.shopping,
    outbound: Outbound.proxy,
    geosites: ['category-cryptocurrency'],
    domainSuffixes: ['binance.com', 'okx.com', 'coinbase.com', 'bybit.com', 'kraken.com', 'bitget.com', 'gate.io', 'kucoin.com'],
  ),
  MuseRulePreset(
    key: 'amazon',
    title: 'Amazon',
    group: MusePresetGroup.shopping,
    outbound: Outbound.proxy,
    geosites: ['amazon'],
    domainSuffixes: ['amazon.com', 'amazon.co.jp', 'amazon.co.uk', 'amazon.de', 'media-amazon.com', 'ssl-images-amazon.com'],
  ),
  MuseRulePreset(
    key: 'cnapps',
    title: '国内常用 App 直连（微信 / QQ / 淘宝 / 支付宝 / 抖音 / B 站 / 网易云）',
    group: MusePresetGroup.domestic,
    outbound: Outbound.direct,
    geosites: ['tencent', 'alibaba', 'douyin', 'bilibili', 'netease'],
    domainSuffixes: [
      'qq.com', 'weixin.qq.com', 'wechat.com', 'gtimg.com', 'qpic.cn', 'taobao.com', 'tmall.com', 'alicdn.com',
      'alipay.com', 'douyin.com', 'douyinvod.com', 'bilibili.com', 'hdslb.com', 'biliapi.net', 'music.163.com', '126.net',
    ],
    packageNames: [
      'com.tencent.mm', 'com.tencent.mobileqq', 'com.taobao.taobao', 'com.eg.android.AlipayGphone',
      'com.ss.android.ugc.aweme', 'tv.danmaku.bili', 'com.netease.cloudmusic',
    ],
  ),
  MuseRulePreset(
    key: 'banks',
    title: '国内银行与支付直连',
    group: MusePresetGroup.domestic,
    outbound: Outbound.direct,
    domainSuffixes: [
      'icbc.com.cn', 'ccb.com', 'abchina.com', 'boc.cn', 'bankcomm.com', 'cmbchina.com', 'psbc.com',
      'spdb.com.cn', 'cib.com.cn', 'cebbank.com', 'cmbc.com.cn', 'citicbank.com', 'pingan.com',
      'alipay.com', 'alipayobjects.com', 'tenpay.com', 'unionpay.com', '95516.com',
    ],
  ),
  MuseRulePreset(
    key: 'apple',
    title: '苹果服务直连',
    group: MusePresetGroup.domestic,
    outbound: Outbound.direct,
    domainSuffixes: ['apple.com', 'icloud.com', 'icloud-content.com', 'mzstatic.com', 'cdn-apple.com', 'apple-cloudkit.com', 'aaplimg.com'],
  ),
  MuseRulePreset(
    key: 'microsoft',
    title: '微软服务直连',
    group: MusePresetGroup.domestic,
    outbound: Outbound.direct,
    domainSuffixes: [
      'microsoft.com', 'windowsupdate.com', 'office.com', 'office.net', 'live.com', 'msftconnecttest.com',
      'msftncsi.com', 'onedrive.com', 'sharepoint.com', 'outlook.com', 'microsoftonline.com',
    ],
  ),
  MuseRulePreset(
    key: 'games',
    title: '游戏下载直连',
    group: MusePresetGroup.games,
    outbound: Outbound.direct,
    domainSuffixes: [
      'steamcontent.com', 'steamserver.net', 'dl.steam.clngaa.com', 'epicgames-download1.akamaized.net',
      'download.epicgames.com', 'blzddist1-a.akamaihd.net', 'gamecdn.blizzard.com', 'origin-a.akamaihd.net',
      'xboxlive.com', 'playstation.net', 'nintendo.net',
    ],
  ),
  MuseRulePreset(
    key: 'cncdn',
    title: '国内 CDN / 游戏下载直连',
    group: MusePresetGroup.domestic,
    outbound: Outbound.direct,
    geosites: ['category-cdn-cn', 'category-games@cn', 'steam@cn', 'category-game-platforms-download'],
    domainSuffixes: ['steamcontent.com', 'dl.steam.clngaa.com', 'alicdn.com', 'bdstatic.com', 'qcloudcdn.com', 'myqcloud.com'],
  ),
  MuseRulePreset(
    key: 'bt',
    title: '下载 / BT 直连',
    group: MusePresetGroup.download,
    outbound: Outbound.direct,
    geosites: ['category-public-tracker', 'category-pt'],
    processNames: [
      'qbittorrent.exe', 'BitComet.exe', 'Thunder.exe', 'uTorrent.exe', 'BitTorrent.exe', 'aria2c.exe',
      'IDMan.exe', 'transmission-qt.exe', 'Motrix.exe', 'NDM.exe',
    ],
    packageNames: [
      'com.xunlei.downloadprovider', 'org.proninyaroslav.libretorrent', 'com.utorrent.client', 'com.bittorrent.client',
      'idm.internet.download.manager',
    ],
  ),
];

/// Presets by their page section, in page order (the section order follows [MusePresetGroup]).
Map<MusePresetGroup, List<MuseRulePreset>> musePresetsByGroup({String query = ''}) {
  final q = query.trim().toLowerCase();
  final out = <MusePresetGroup, List<MuseRulePreset>>{};
  for (final g in MusePresetGroup.values) {
    final items = [for (final p in museRulePresets) if (p.group == g && (q.isEmpty || p.searchText.contains(q) || g.title.contains(q))) p];
    if (items.isNotEmpty) out[g] = items;
  }
  return out;
}

/// Every bundled geosite the presets use (each must be in assets/rule-sets).
Set<String> get musePresetGeosites => {for (final p in museRulePresets) ...p.geosites};

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

/// The core rules for one preset. Destinations (domains / IPs / rule-sets) and apps
/// (processes / Android packages) are separate rules, since the core requires every kind of
/// condition in one rule to match (1.4.1: apps are new; a mixed rule would match nothing).
List<Rule> musePresetRules(MuseRulePreset p, Outbound way) => [
  if (p.domainSuffixes.isNotEmpty || p.domainKeywords.isNotEmpty || p.ipCidrs.isNotEmpty || p.geosites.isNotEmpty)
    Rule(
      name: p.ruleName,
      enabled: true,
      outbound: way,
      domainSuffixes: p.domainSuffixes,
      domainKeywords: p.domainKeywords,
      ipCidrs: p.ipCidrs,
      ruleSets: p.ruleSetUrls,
    ),
  if (p.processNames.isNotEmpty || p.packageNames.isNotEmpty) ...[
    if (p.processNames.isNotEmpty) Rule(name: '${p.ruleName}:apps', enabled: true, outbound: way, processNames: p.processNames),
    if (p.packageNames.isNotEmpty) Rule(name: '${p.ruleName}:android', enabled: true, outbound: way, packageNames: p.packageNames),
  ],
];

/// The rule list sent to the core: the user's own rules first, then the enabled presets, then the
/// built-in rules (国内直连 / 局域网 / 去广告); list_order follows this order.
List<Rule> museApplyPresets(List<Rule> rules, Map<String, Outbound> enabled, {List<MuseRemoteRuleSet> remote = const []}) {
  if (enabled.isEmpty && remote.isEmpty) return rules;
  final own = rules.where((r) => !r.name.startsWith('builtin:')).toList();
  final builtin = rules.where((r) => r.name.startsWith('builtin:')).toList();
  final presets = <Rule>[
    for (final p in museRulePresets)
      if (enabled.containsKey(p.key)) ...musePresetRules(p, enabled[p.key]!),
    ...museRemoteRuleSetRules(remote),
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

// ---------------------------------------------------------------- 1.4.1: sites / apps → one node

/// 「指定节点」: sites (domain suffixes) and apps (Windows process / Android package) sent
/// through one chosen node, whatever the route mode (core option `muse-node-rules`; a rule whose
/// node is gone is dropped by the core instead of failing the connection).
class MuseNodeRule {
  const MuseNodeRule({required this.node, this.domains = const [], this.processes = const [], this.packages = const []});

  /// the node's tag
  final String node;
  final List<String> domains;
  final List<String> processes;
  final List<String> packages;

  bool get isEmpty => node.trim().isEmpty || (domains.isEmpty && processes.isEmpty && packages.isEmpty);

  /// What it covers, for the list.
  String get summary => [...domains, ...processes, ...packages].join('、');

  Map<String, dynamic> toJson() => {
    if (domains.isNotEmpty) 'domain_suffix': domains,
    if (processes.isNotEmpty) 'process_name': processes,
    if (packages.isNotEmpty) 'package_name': packages,
    'outbound': node,
  };

  static MuseNodeRule? fromJson(Object? j) {
    if (j is! Map) return null;
    List<String> list(String k) => [for (final v in (j[k] as List? ?? const [])) if ('$v'.trim().isNotEmpty) '$v'.trim()];
    final r = MuseNodeRule(node: '${j['outbound'] ?? ''}', domains: list('domain_suffix'), processes: list('process_name'), packages: list('package_name'));
    return r.isEmpty ? null : r;
  }
}

List<MuseNodeRule> museParseNodeRules(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! List) return const [];
    return [for (final e in j) ?MuseNodeRule.fromJson(e)];
  } catch (_) {
    return const [];
  }
}

String museNodeRulesToRaw(List<MuseNodeRule> rules) => jsonEncode([for (final r in rules) if (!r.isEmpty) r.toJson()]);

/// One typed entry (a site or an app) sorted into its kind: `*.exe` = Windows process,
/// `com.x.y` without a TLD-looking last part… is ambiguous, so a package must contain no dot-TLD:
/// anything with a known site ending is a domain, `a.b.c` with ≥ 2 dots and no known ending is a
/// package. Returns null for junk.
({String kind, String value})? museClassifyTarget(String raw) {
  var v = raw.trim().toLowerCase();
  if (v.isEmpty) return null;
  if (v.contains('://')) {
    final u = Uri.tryParse(v);
    if (u == null || u.host.isEmpty) return null;
    v = u.host;
  }
  v = v.replaceFirst(RegExp(r'^\*?\.'), '').split('/').first;
  if (v.endsWith('.exe')) return (kind: 'process', value: raw.trim().split(RegExp(r'[\\/]')).last);
  if (!RegExp(r'^[a-z0-9_\-]+(\.[a-z0-9_\-]+)+$').hasMatch(v)) return null;
  final last = v.split('.').last;
  const tlds = {
    'com', 'net', 'org', 'io', 'ai', 'cn', 'jp', 'hk', 'tw', 'uk', 'de', 'me', 'tv', 'co', 'app', 'dev', 'gg', 'so',
    'xyz', 'info', 'edu', 'gov', 'us', 'sg', 'kr', 'fr', 'ru', 'cc', 'to', 'im', 'fm', 'ly', 'be', 'eu', 'ca', 'au',
  };
  if (tlds.contains(last)) return (kind: 'domain', value: v);
  if (v.split('.').length >= 3) return (kind: 'package', value: raw.trim());
  return (kind: 'domain', value: v);
}

/// A node rule from typed lines (one site / app per line or comma-separated).
MuseNodeRule museNodeRuleFromText(String node, String text) {
  final domains = <String>[];
  final processes = <String>[];
  final packages = <String>[];
  for (final part in text.split(RegExp(r'[\n,，;；\s]+'))) {
    final c = museClassifyTarget(part);
    if (c == null) continue;
    final list = switch (c.kind) {
      'process' => processes,
      'package' => packages,
      _ => domains,
    };
    if (!list.contains(c.value)) list.add(c.value);
  }
  return MuseNodeRule(node: node, domains: domains, processes: processes, packages: packages);
}

// ---------------------------------------------------------------- 1.4.1: remote rule-sets

/// A rule-set the user subscribed to by link, with its way.
class MuseRemoteRuleSet {
  const MuseRemoteRuleSet(this.url, this.outbound);

  final String url;
  final Outbound outbound;

  Map<String, dynamic> toJson() => {'url': url, 'outbound': museOutboundKey(outbound)};
}

List<MuseRemoteRuleSet> museParseRemoteRuleSets(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! List) return const [];
    return [
      for (final e in j)
        if (e is Map && museIsRuleSetUrl('${e['url']}')) MuseRemoteRuleSet('${e['url']}'.trim(), museOutboundFromKey('${e['outbound']}') ?? Outbound.proxy),
    ];
  } catch (_) {
    return const [];
  }
}

String museRemoteRuleSetsToRaw(List<MuseRemoteRuleSet> l) => jsonEncode([for (final r in l) r.toJson()]);

/// The core rules for the remote rule-sets (checked after the presets, before the built-ins).
List<Rule> museRemoteRuleSetRules(List<MuseRemoteRuleSet> sets) => [
  for (var i = 0; i < sets.length; i++) Rule(name: 'remote:$i', enabled: true, outbound: sets[i].outbound, ruleSets: [sets[i].url]),
];

// ---------------------------------------------------------------- 1.5.0 (chunk 2)

const museGeoipBase = 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/';

String museGeoipUrl(String name) => '${museGeoipBase}geoip-$name.srs';

const museLanRuleName = 'builtin:bypassLan';

/// #57: 局域网 / 私有地址 always go direct: the built-in rule is switched on and checked before
/// every other rule (the user's own rules and presets included). A list without it is unchanged.
List<Rule> musePinLanRule(List<Rule> rules) {
  final i = rules.indexWhere((r) => r.name == museLanRuleName);
  if (i < 0) return rules;
  final lan = rules[i].deepCopy()..enabled = true;
  final out = <Rule>[lan];
  for (var k = 0; k < rules.length; k++) {
    if (k != i) out.add(rules[k]);
  }
  for (var k = 0; k < out.length; k++) {
    if (out[k].listOrder != k) out[k] = out[k].deepCopy()..listOrder = k;
  }
  return out;
}

/// #14: names that must get real addresses under Fake-IP — local networks, time servers and the
/// systems' connectivity checks (a fake address breaks them). They go direct, which is also where
/// they belong.
const museFakeIpExcludeSuffixes = [
  'lan', 'local', 'localdomain', 'localhost', 'home.arpa', 'internal',
  'msftconnecttest.com', 'msftncsi.com', 'time.windows.com', 'time.nist.gov',
  'pool.ntp.org', 'ntp.org', 'time.apple.com', 'time.android.com', 'time.google.com',
  'ntp.aliyun.com', 'ntp.tencent.com', 'ntp1.aliyun.com', 'cn.ntp.org.cn',
  'connectivitycheck.platform.hicloud.com', 'connect.rom.miui.com', 'wifi.vivo.com.cn',
  'stun.l.google.com', 'stun.miwifi.com', 'stun.qq.com',
];

const museFakeIpExcludeRuleName = 'muse:fakeip-exclude';

/// The rules with the Fake-IP exclusions first (after the 局域网 rule) when [fakeIp] is on.
List<Rule> museApplyFakeIpExclusions(List<Rule> rules, {required bool fakeIp}) {
  if (!fakeIp) return rules;
  final lanFirst = rules.isNotEmpty && rules.first.name == museLanRuleName;
  final exclude = Rule(
    name: museFakeIpExcludeRuleName,
    enabled: true,
    outbound: Outbound.direct,
    domainSuffixes: museFakeIpExcludeSuffixes,
  );
  final list = lanFirst ? [rules.first, exclude, ...rules.skip(1)] : [exclude, ...rules];
  return [for (var k = 0; k < list.length; k++) list[k].deepCopy()..listOrder = k];
}

/// #59: the result of converting pasted Clash / Surge rule lines.
class MuseRuleConversion {
  const MuseRuleConversion(this.rules, this.converted, this.skipped);

  final List<Rule> rules;

  /// lines turned into conditions
  final int converted;

  /// rule lines that can't be expressed (AND / OR / RULE-SET / USER-AGENT …); MATCH / FINAL are
  /// the default anyway and not counted
  final int skipped;
}

Outbound _policyOf(String p) {
  final u = p.trim().toUpperCase();
  if (u == 'DIRECT') return Outbound.direct;
  if (u.startsWith('REJECT')) return Outbound.block;
  return Outbound.proxy;
}

/// #59: turns Clash (`- DOMAIN-SUFFIX,google.com,Proxy`) / Surge (`DOMAIN-SUFFIX,google.com,Proxy`)
/// rule lines into rules. DIRECT → 直连, REJECT* → 拦截, any other policy → 走节点. Consecutive lines
/// with the same way and kind are merged into one rule, so the order (priority) is kept.
MuseRuleConversion museConvertClashRules(String text, {String prefix = '导入'}) {
  final rules = <Rule>[];
  var converted = 0;
  var skipped = 0;
  String? lastKey;
  for (var raw in text.split(RegExp(r'\r?\n'))) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//') || line.startsWith(';')) continue;
    if (RegExp(r'^[\w-]+\s*:\s*$').hasMatch(line) || line.startsWith('[')) continue; // `rules:` / `[Rule]`
    if (line.startsWith('- ')) line = line.substring(2).trim();
    line = line.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
    final parts = line.split(',').map((e) => e.trim()).toList();
    final kind = parts.first.toUpperCase();
    if (kind == 'MATCH' || kind == 'FINAL') continue;
    if (parts.length < 3) {
      skipped++;
      continue;
    }
    final value = parts[1];
    final way = _policyOf(parts[2]);
    final String group;
    void Function(Rule) apply;
    switch (kind) {
      case 'DOMAIN':
        group = 'dest';
        apply = (r) => r.domains.add(value.toLowerCase());
      case 'DOMAIN-SUFFIX':
        group = 'dest';
        apply = (r) => r.domainSuffixes.add(value.toLowerCase().replaceFirst(RegExp(r'^\.'), ''));
      case 'DOMAIN-KEYWORD':
        group = 'dest';
        apply = (r) => r.domainKeywords.add(value.toLowerCase());
      case 'DOMAIN-REGEX':
        group = 'dest';
        apply = (r) => r.domainRegexes.add(value);
      case 'IP-CIDR' || 'IP-CIDR6':
        if (!value.contains('/')) {
          skipped++;
          continue;
        }
        group = 'dest';
        apply = (r) => r.ipCidrs.add(value);
      case 'SRC-IP-CIDR':
        group = 'src';
        apply = (r) => r.sourceIpCidrs.add(value);
      case 'DST-PORT' || 'DEST-PORT':
        group = 'port';
        apply = (r) => r.portRanges.add(value.replaceAll('-', ':'));
      case 'SRC-PORT':
        group = 'sport';
        apply = (r) => r.sourcePortRanges.add(value.replaceAll('-', ':'));
      case 'PROCESS-NAME':
        group = 'proc';
        apply = (r) => r.processNames.add(value);
      case 'PROCESS-PATH':
        group = 'path';
        apply = (r) => r.processPaths.add(value);
      case 'GEOSITE':
        group = 'set';
        apply = (r) => r.ruleSets.add(museGeositeUrl(value.toLowerCase()));
      case 'GEOIP':
        if (value.toUpperCase() == 'LAN' || value.toUpperCase() == 'PRIVATE') continue; // the built-in 局域网 rule
        group = 'set';
        apply = (r) => r.ruleSets.add(museGeoipUrl(value.toLowerCase()));
      default:
        skipped++;
        continue;
    }
    final key = '${way.value}/$group';
    if (key != lastKey || rules.isEmpty) {
      rules.add(Rule(name: '$prefix ${rules.length + 1} · ${museOutboundTitle(way)}', enabled: true, outbound: way));
      lastKey = key;
    }
    apply(rules.last);
    converted++;
  }
  for (var k = 0; k < rules.length; k++) {
    rules[k].listOrder = k;
  }
  return MuseRuleConversion(rules, converted, skipped);
}

/// #9: 屏蔽 QUIC — UDP 443 refused, so YouTube and other sites fall back to HTTP/2 over TCP
/// (steadier on nodes with poor UDP). Sits right after the 局域网 rule.
const museBlockQuicRuleName = 'muse:block-quic';

List<Rule> museApplyBlockQuic(List<Rule> rules, {required bool block}) {
  if (!block) return rules;
  final lanFirst = rules.isNotEmpty && rules.first.name == museLanRuleName;
  final quic = Rule(name: museBlockQuicRuleName, enabled: true, outbound: Outbound.block, network: Network.udp, portRanges: ['443']);
  final list = lanFirst ? [rules.first, quic, ...rules.skip(1)] : [quic, ...rules];
  return [for (var k = 0; k < list.length; k++) list[k].deepCopy()..listOrder = k];
}
