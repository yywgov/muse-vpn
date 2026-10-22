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
  const MuseDeepLink({this.url, this.name, this.connect = false, this.node});

  /// a subscription to import
  final String? url;
  final String? name;

  /// `chuanyun://connect` (optionally `?node=`)
  final bool connect;
  final String? node;
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
