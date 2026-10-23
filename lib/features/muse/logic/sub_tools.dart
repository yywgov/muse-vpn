// 穿云 1.4.0 - subscription tools (pure logic, unit-tested): what format a subscription is in,
// what changed between two updates, when to remind about expiry / traffic, `chuanyun://` links,
// QR payloads and the user-agent choices.
// Part of 穿云 (GPLv3).

import 'dart:convert';

enum MuseSubFormat {
  clash('Clash'),
  singBox('sing-box'),
  sip008('SIP008'),
  base64('Base64'),
  links('链接'),
  unknown('未知');

  const MuseSubFormat(this.title);

  final String title;
}

const _linkSchemes = [
  'vless://', 'vmess://', 'trojan://', 'ss://', 'ssr://', 'hysteria://', 'hysteria2://', 'hy2://',
  'tuic://', 'wireguard://', 'wg://', 'socks://', 'socks5://', 'http://', 'https://', 'anytls://', 'ssh://', 'naive+https://',
];

bool _looksLikeLinks(String s) {
  final lines = s.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (lines.isEmpty) return false;
  final hits = lines.where((l) => _linkSchemes.any((p) => l.toLowerCase().startsWith(p) && p != 'http://' && p != 'https://')).length;
  return hits > 0 && hits >= lines.length / 2;
}

/// The format of a downloaded subscription body.
MuseSubFormat museDetectSubFormat(String body) {
  final s = body.trim();
  if (s.isEmpty) return MuseSubFormat.unknown;
  if (s.startsWith('{') || s.startsWith('[')) {
    try {
      final j = jsonDecode(s);
      if (j is Map && (j.containsKey('outbounds') || j.containsKey('endpoints'))) return MuseSubFormat.singBox;
      if (j is Map && j['servers'] is List) return MuseSubFormat.sip008;
      if (j is List && j.isNotEmpty && j.first is Map && (j.first as Map).containsKey('server_port')) return MuseSubFormat.sip008;
      if (j is List && j.isNotEmpty && j.first is Map && (j.first as Map).containsKey('type')) return MuseSubFormat.singBox;
    } catch (_) {}
    return MuseSubFormat.unknown;
  }
  if (RegExp(r'^(proxies|proxy-groups|port|mixed-port|rules)\s*:', multiLine: true).hasMatch(s)) return MuseSubFormat.clash;
  if (_looksLikeLinks(s)) return MuseSubFormat.links;
  final compact = s.replaceAll(RegExp(r'\s'), '');
  if (RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact) && compact.length >= 16) {
    try {
      final norm = compact.replaceAll('-', '+').replaceAll('_', '/');
      final padded = norm.padRight((norm.length + 3) ~/ 4 * 4, '=');
      final decoded = utf8.decode(base64.decode(padded), allowMalformed: true);
      if (_looksLikeLinks(decoded)) return MuseSubFormat.base64;
    } catch (_) {}
  }
  return MuseSubFormat.unknown;
}

/// Node names added / removed by an update.
class MuseSubDiff {
  const MuseSubDiff(this.added, this.removed, this.kept);

  final List<String> added;
  final List<String> removed;
  final int kept;

  bool get changed => added.isNotEmpty || removed.isNotEmpty;

  String get summary {
    if (!changed) return '节点没有变化';
    final parts = <String>[
      if (added.isNotEmpty) '新增 ${added.length}',
      if (removed.isNotEmpty) '移除 ${removed.length}',
      '保留 $kept',
    ];
    return parts.join(' · ');
  }
}

MuseSubDiff museSubDiff(List<String> before, List<String> after) {
  final b = before.toSet();
  final a = after.toSet();
  return MuseSubDiff(
    [for (final n in after) if (!b.contains(n)) n],
    [for (final n in before) if (!a.contains(n)) n],
    a.intersection(b).length,
  );
}

/// The reminders due for a subscription (1.4.0: 3 days before expiry, 10 % traffic left).
enum MuseSubReminder { expiresSoon, expired, trafficLow, trafficOut }

Set<MuseSubReminder> museSubReminders({
  required int total,
  required int used,
  DateTime? expire,
  DateTime? now,
}) {
  final out = <MuseSubReminder>{};
  final t = now ?? DateTime.now();
  if (expire != null && expire.year > 1971 && expire.year < 2100) {
    final left = expire.difference(t);
    if (left.isNegative) {
      out.add(MuseSubReminder.expired);
    } else if (left <= const Duration(days: 3)) {
      out.add(MuseSubReminder.expiresSoon);
    }
  }
  if (total > 0) {
    final rest = total - used;
    if (rest <= 0) {
      out.add(MuseSubReminder.trafficOut);
    } else if (rest <= total * 0.1) {
      out.add(MuseSubReminder.trafficLow);
    }
  }
  return out;
}

/// What a `chuanyun://` link asks for.
class MuseDeepLink {
  const MuseDeepLink({this.url, this.name, this.connect = false, this.node, this.disconnect = false});

  /// a subscription to import
  final String? url;
  final String? name;

  /// `chuanyun://connect` (optionally `?node=`)
  final bool connect;
  final String? node;

  /// `chuanyun://disconnect` (1.4.1)
  final bool disconnect;
}

/// Parses `chuanyun://import?url=…&name=…`, `chuanyun://install-config?url=…`,
/// `chuanyun://import/<url>` and `chuanyun://connect[?node=…]`. null = not ours / no use.
MuseDeepLink? museParseDeepLink(String raw) {
  final s = raw.trim();
  if (!s.toLowerCase().startsWith('chuanyun://')) return null;
  final rest = s.substring('chuanyun://'.length);
  final action = rest.split(RegExp(r'[/?#]')).first.toLowerCase();
  Uri? uri;
  try {
    uri = Uri.parse(s);
  } catch (_) {}
  final q = uri?.queryParameters ?? const {};
  switch (action) {
    case 'connect':
      return MuseDeepLink(connect: true, node: q['node']);
    case 'disconnect':
      return const MuseDeepLink(disconnect: true);
    case 'import':
    case 'install-config':
    case 'install-sub':
      var url = q['url'];
      if (url == null) {
        final slash = rest.indexOf('/');
        if (slash >= 0) url = Uri.decodeComponent(rest.substring(slash + 1).split('#').first);
      }
      if (url == null || !(url.startsWith('http://') || url.startsWith('https://') || url.contains('://'))) return null;
      final fragment = uri?.fragment ?? '';
      return MuseDeepLink(url: url, name: q['name'] ?? (fragment.isEmpty ? null : Uri.decodeComponent(fragment)));
  }
  return null;
}

/// The link a QR code of a subscription carries (opens 穿云 when scanned by the phone camera).
String museSubscriptionQrPayload(String url, {String? name}) {
  final n = name == null || name.isEmpty ? '' : '&name=${Uri.encodeQueryComponent(name)}';
  return 'chuanyun://import?url=${Uri.encodeQueryComponent(url)}$n';
}

/// User-agent choices for downloading a subscription (the server picks the format by it).
const museUserAgents = <(String, String)>[
  ('auto', '自动'),
  ('clash', 'Clash'),
  ('singbox', 'sing-box'),
  ('v2ray', 'v2rayN'),
  ('shadowrocket', 'Shadowrocket'),
];

String? museUserAgentFor(String key, {required String appVersion}) => switch (key) {
  'clash' => 'clash.meta/1.19.0 mihomo/1.19.0',
  'singbox' => 'sing-box/1.12.0',
  'v2ray' => 'v2rayN/7.0',
  'shadowrocket' => 'Shadowrocket/2.2.60',
  _ => null, // the app's own
};

/// A subscription link with its secret parts hidden, for showing on screen.
String museMaskSubUrl(String url) {
  try {
    final u = Uri.parse(url);
    if (u.host.isEmpty) return '••••';
    final path = u.path.length > 4 ? '/••••' : u.path;
    return '${u.scheme}://${u.host}$path${u.hasQuery ? '?••••' : ''}';
  } catch (_) {
    return '••••';
  }
}

/// 1.4.1: node names in a stored subscription config (sing-box JSON: proxy outbounds; groups,
/// direct / block / dns left out). Empty when it isn't JSON.
List<String> museConfigNodeNames(String raw) {
  const skip = {'selector', 'urltest', 'direct', 'block', 'dns', 'loadbalance'};
  try {
    final j = jsonDecode(raw);
    final outs = j is Map ? j['outbounds'] : null;
    if (outs is! List) return const [];
    return [
      for (final o in outs)
        if (o is Map && o['tag'] is String && !skip.contains('${o['type']}'.toLowerCase())) o['tag'] as String,
    ];
  } catch (_) {
    return const [];
  }
}

// ---------------------------------------------------------------- 1.5.0 (chunk 2)

/// #42: a WireGuard `.conf` ([Interface] / [Peer]) is a format of its own.
bool museIsWireGuardConf(String body) {
  final s = body.trimLeft();
  return s.startsWith('[Interface]') && RegExp(r'^\s*\[Peer\]', multiLine: true).hasMatch(s);
}

/// The text a subscription body holds, base64 decoded when it is base64 ('' when it can't be read).
String museSubPlainText(String body) {
  final s = body.trim();
  if (museDetectSubFormat(s) != MuseSubFormat.base64) return s;
  try {
    final compact = s.replaceAll(RegExp(r'\s'), '');
    final norm = compact.replaceAll('-', '+').replaceAll('_', '/');
    return utf8.decode(base64.decode(norm.padRight((norm.length + 3) ~/ 4 * 4, '=')), allowMalformed: true);
  } catch (_) {
    return '';
  }
}

/// What 添加订阅 shows before saving: the format and how many nodes the body holds.
class MuseSubPreview {
  const MuseSubPreview({required this.format, required this.nodes, this.formatLabel});

  final MuseSubFormat format;
  final int nodes;

  /// overrides [format]'s title (WireGuard)
  final String? formatLabel;

  String get formatTitle => formatLabel ?? format.title;
  bool get empty => nodes == 0;
}

const _previewSkipTypes = {'selector', 'urltest', 'direct', 'block', 'dns', 'loadbalance'};

/// #42: counts the nodes of a downloaded subscription without the core (never throws).
MuseSubPreview museSubPreview(String body) {
  try {
    if (museIsWireGuardConf(body)) {
      return MuseSubPreview(format: MuseSubFormat.unknown, nodes: 1, formatLabel: 'WireGuard');
    }
    final format = museDetectSubFormat(body);
    switch (format) {
      case MuseSubFormat.singBox:
        final j = jsonDecode(body.trim());
        final list = <Object?>[
          if (j is Map) ...((j['outbounds'] as List?) ?? const []),
          if (j is Map) ...((j['endpoints'] as List?) ?? const []),
          if (j is List) ...j,
        ];
        final n = list.where((o) => o is Map && !_previewSkipTypes.contains('${o['type']}'.toLowerCase())).length;
        return MuseSubPreview(format: format, nodes: n);
      case MuseSubFormat.sip008:
        final j = jsonDecode(body.trim());
        final n = j is Map ? ((j['servers'] as List?)?.length ?? 0) : (j is List ? j.length : 0);
        return MuseSubPreview(format: format, nodes: n);
      case MuseSubFormat.clash:
        return MuseSubPreview(format: format, nodes: _clashProxyCount(body));
      case MuseSubFormat.links:
      case MuseSubFormat.base64:
        final text = museSubPlainText(body);
        final n = text
            .split(RegExp(r'[\r\n]+'))
            .map((e) => e.trim().toLowerCase())
            .where((l) => _linkSchemes.any((p) => p != 'http://' && p != 'https://' && l.startsWith(p)))
            .length;
        return MuseSubPreview(format: format, nodes: n);
      case MuseSubFormat.unknown:
        return const MuseSubPreview(format: MuseSubFormat.unknown, nodes: 0);
    }
  } catch (_) {
    return const MuseSubPreview(format: MuseSubFormat.unknown, nodes: 0);
  }
}

/// Entries under the top-level `proxies:` key of a Clash YAML (block `- name:` items or flow `- {…}`).
int _clashProxyCount(String body) {
  final lines = body.split(RegExp(r'\r?\n'));
  var inProxies = false;
  int? itemIndent;
  var n = 0;
  for (final raw in lines) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    final indent = raw.length - raw.trimLeft().length;
    if (indent == 0) {
      inProxies = RegExp(r'^proxies\s*:').hasMatch(raw);
      itemIndent = null;
      continue;
    }
    if (!inProxies) continue;
    final t = raw.trimLeft();
    if (!t.startsWith('- ') && t != '-') continue;
    itemIndent ??= indent;
    if (indent == itemIndent) n++;
  }
  return n;
}

/// #41: how subscriptions are downloaded.
enum MuseSubFetch {
  auto('auto', '自动'),
  proxy('proxy', '走代理'),
  direct('direct', '直连');

  const MuseSubFetch(this.key, this.title);

  final String key;
  final String title;

  static MuseSubFetch fromKey(String key) => values.firstWhere((e) => e.key == key, orElse: () => auto);
}

/// The HTTP client mode for a download: 'proxy', 'direct' or 'both' (proxy, then direct).
/// 走代理 while nothing listens on the local port (not connected) has to go direct.
String museSubFetchMode(MuseSubFetch pref, {required bool proxyUp}) => switch (pref) {
  MuseSubFetch.direct => 'direct',
  MuseSubFetch.proxy => proxyUp ? 'proxy' : 'direct',
  MuseSubFetch.auto => proxyUp ? 'both' : 'direct',
};

/// #45: a failed subscription download in plain words, with what to try.
String museSubFetchError({int? status, String kind = '', String detail = ''}) {
  if (status != null && status > 0) {
    final advice = switch (status) {
      401 || 403 => '订阅链接可能已失效、被重置或限制了设备，请到服务商后台重新复制链接',
      404 || 410 => '订阅地址不存在，请确认链接完整或重新复制',
      429 => '请求太频繁，被服务商限流，请稍后再更新',
      >= 500 && < 600 => '服务商的服务器出错，请稍后再试',
      >= 300 && < 400 => '订阅地址发生了跳转，请重新复制最新链接',
      _ => '请检查链接或换一个订阅 UA 后再试',
    };
    return 'HTTP $status · $advice';
  }
  final k = kind.toLowerCase();
  final d = detail.toLowerCase();
  if (k.contains('timeout') || d.contains('timed out')) return '连接超时 · 订阅服务器响应太慢，可在 设置 › 节点 › 订阅更新方式 换成「走代理」或「直连」再试';
  if (d.contains('handshake') || d.contains('certificate') || k.contains('badcertificate')) return '证书校验失败 · 网络可能被劫持，或订阅服务器证书有问题';
  if (d.contains('failed host lookup') || d.contains('no address associated')) return '域名解析失败 · 订阅域名可能被屏蔽，可连接后用「走代理」更新';
  if (d.contains('connection refused') || d.contains('connection reset') || d.contains('connection closed')) {
    return '连接被拒绝或中断 · 订阅服务器可能被屏蔽，可连接后用「走代理」更新';
  }
  return '';
}

/// #46: traffic / expiry a subscription states in a 「剩余流量」/「到期」 entry name or a `STATUS=`
/// line, as a `subscription-userinfo` value; null when it states none. Only used when the server
/// sends no header.
String? museSubInfoFromContent(String body) {
  String text;
  try {
    text = museSubPlainText(body);
  } catch (_) {
    return null;
  }
  if (text.isEmpty) return null;
  // node names live in the link fragment (percent-encoded) or a Clash `name:`
  final decoded = StringBuffer();
  for (final line in text.split(RegExp(r'\r?\n')).take(4000)) {
    var l = line;
    final hash = l.indexOf('#');
    if (hash >= 0 && l.contains('://')) {
      try {
        l = Uri.decodeComponent(l.substring(hash + 1));
      } catch (_) {
        l = l.substring(hash + 1);
      }
    }
    decoded.writeln(l);
  }
  final s = decoded.toString();
  const unit = r'(TB|GB|MB|KB|T|G|M|K)i?B?';
  int? bytes(String num, String u) {
    final v = double.tryParse(num);
    if (v == null) return null;
    final m = switch (u.toUpperCase()[0]) { 'T' => 1024.0 * 1024 * 1024 * 1024, 'G' => 1024.0 * 1024 * 1024, 'M' => 1024.0 * 1024, _ => 1024.0 };
    return (v * m).round();
  }

  int? remaining;
  int? used;
  int? total;
  DateTime? expire;
  // STATUS=🚀↑:0.5GB,↓:10GB,TOT:100GB💡Expires:2026-11-01
  final status = RegExp(r'STATUS=([^\r\n]*)', caseSensitive: false).firstMatch(s)?.group(1);
  if (status != null) {
    final up = RegExp('↑\\s*:?\\s*([\\d.]+)\\s*$unit', caseSensitive: false).firstMatch(status);
    final down = RegExp('↓\\s*:?\\s*([\\d.]+)\\s*$unit', caseSensitive: false).firstMatch(status);
    final tot = RegExp('TOT\\s*:?\\s*([\\d.]+)\\s*$unit', caseSensitive: false).firstMatch(status);
    if (up != null || down != null) {
      used = (up == null ? 0 : bytes(up.group(1)!, up.group(2)!) ?? 0) + (down == null ? 0 : bytes(down.group(1)!, down.group(2)!) ?? 0);
    }
    if (tot != null) total = bytes(tot.group(1)!, tot.group(2)!);
  }
  final rem = RegExp('剩余流量\\s*[：:]?\\s*([\\d.]+)\\s*$unit', caseSensitive: false).firstMatch(s);
  if (rem != null) remaining = bytes(rem.group(1)!, rem.group(2)!);
  final tot2 = RegExp('(?:总流量|套餐流量)\\s*[：:]?\\s*([\\d.]+)\\s*$unit', caseSensitive: false).firstMatch(s);
  if (tot2 != null) total ??= bytes(tot2.group(1)!, tot2.group(2)!);
  final exp = RegExp(r'(?:到期|过期|Expires?)[^\d\r\n]{0,8}(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})', caseSensitive: false).firstMatch(s);
  if (exp != null) {
    final y = int.parse(exp.group(1)!);
    final m = int.parse(exp.group(2)!);
    final d = int.parse(exp.group(3)!);
    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) expire = DateTime(y, m, d, 23, 59, 59);
  }
  if (remaining == null && total == null && expire == null) return null;
  if (total != null && remaining != null && used == null) used = (total - remaining).clamp(0, total);
  if (total == null && remaining != null) {
    total = remaining + (used ?? 0);
  }
  final expireSec = expire == null ? 0 : expire.millisecondsSinceEpoch ~/ 1000;
  return 'upload=0; download=${used ?? 0}; total=${total ?? 0}; expire=$expireSec';
}

/// #43: 只显示 / 排除 for one subscription (by profile id), on top of the global ones.
class MuseSubFilter {
  const MuseSubFilter({this.include = '', this.exclude = ''});

  final String include;
  final String exclude;

  bool get isEmpty => include.trim().isEmpty && exclude.trim().isEmpty;

  Map<String, String> toJson() => {if (include.isNotEmpty) 'include': include, if (exclude.isNotEmpty) 'exclude': exclude};
}

Map<String, MuseSubFilter> museParseSubFilters(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return const {};
    return {
      for (final e in j.entries)
        if (e.value is Map)
          '${e.key}': MuseSubFilter(include: '${(e.value as Map)['include'] ?? ''}', exclude: '${(e.value as Map)['exclude'] ?? ''}'),
    };
  } catch (_) {
    return const {};
  }
}

String museSubFiltersToRaw(Map<String, MuseSubFilter> filters) =>
    jsonEncode({for (final e in filters.entries) if (!e.value.isEmpty) e.key: e.value.toJson()});
