// 穿云 1.6.0 - sharing one node (pure logic, unit-tested): its share link (二维码 / 复制链接),
// a Clash YAML entry and the node's own JSON from the saved config; the canonical settings used to
// tell duplicates apart by full parameters.
// Part of 穿云 (GPLv3).

import 'dart:convert';

/// #35: the formats 复制 offers.
enum MuseNodeCopyFormat {
  link('链接'),
  clash('Clash'),
  json('JSON 配置');

  const MuseNodeCopyFormat(this.label);
  final String label;
}

/// The node [tag] of the saved config [raw] (outbounds or endpoints), null when not there.
Map<String, dynamic>? museFindOutbound(String raw, String tag) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    final all = [...((j['outbounds'] as List?) ?? const []), ...((j['endpoints'] as List?) ?? const [])].whereType<Map>();
    final o = all.where((e) => e['tag'] == tag).firstOrNull;
    return o == null ? null : Map<String, dynamic>.from(o);
  } catch (_) {
    return null;
  }
}

/// #31: every node's settings as one canonical string (keys sorted, its tag left out), by tag.
Map<String, String> museOutboundParamsByTag(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return const {};
    final all = [...((j['outbounds'] as List?) ?? const []), ...((j['endpoints'] as List?) ?? const [])].whereType<Map>();
    return {
      for (final o in all)
        if (o['tag'] is String) o['tag'] as String: jsonEncode(_canonical(Map.of(o)..remove('tag'))),
    };
  } catch (_) {
    return const {};
  }
}

Object? _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((e) => '$e').toList()..sort();
    return {for (final k in keys) k: _canonical(v[k])};
  }
  if (v is List) return [for (final e in v) _canonical(e)];
  return v;
}

// ---------------------------------------------------------------- reading one outbound

class _Node {
  _Node(this.o);
  final Map<String, dynamic> o;

  String get type => '${o['type'] ?? ''}'.toLowerCase();
  String get server => '${o['server'] ?? ''}';
  int get port => (o['server_port'] as num?)?.toInt() ?? 0;
  String s(String k) => '${o[k] ?? ''}';

  Map get tls => o['tls'] is Map ? o['tls'] as Map : const {};
  bool get tlsOn => tls['enabled'] == true;
  bool get insecure => tls['insecure'] == true;
  String get sni => '${tls['server_name'] ?? ''}';
  List<String> get alpn => [
    if (tls['alpn'] is List) for (final e in tls['alpn'] as List) '$e',
    if (tls['alpn'] is String && (tls['alpn'] as String).isNotEmpty) tls['alpn'] as String,
  ];
  Map get _utls => tls['utls'] is Map ? tls['utls'] as Map : const {};
  String get fp => _utls['enabled'] == true ? '${_utls['fingerprint'] ?? ''}' : '';
  Map get _reality => tls['reality'] is Map ? tls['reality'] as Map : const {};
  bool get reality => _reality['enabled'] == true;
  String get pbk => '${_reality['public_key'] ?? ''}';
  String get sid => '${_reality['short_id'] ?? ''}';

  Map get tr => o['transport'] is Map ? o['transport'] as Map : const {};
  String get net => '${tr['type'] ?? ''}'.toLowerCase();
  String get path => '${tr['path'] ?? ''}';
  String get serviceName => '${tr['service_name'] ?? ''}';
  String get hostHeader {
    final h = tr['headers'] is Map ? (tr['headers'] as Map)['Host'] ?? (tr['headers'] as Map)['host'] : null;
    if (h is String && h.isNotEmpty) return h;
    if (h is List && h.isNotEmpty) return '${h.first}';
    final hh = tr['host'];
    if (hh is String) return hh;
    if (hh is List && hh.isNotEmpty) return '${hh.first}';
    return '';
  }

  List<String> get serverPorts => [
    if (o['server_ports'] is List) for (final e in o['server_ports'] as List) '$e',
    if (o['server_ports'] is String && (o['server_ports'] as String).isNotEmpty) o['server_ports'] as String,
  ];
  Map get obfs => o['obfs'] is Map ? o['obfs'] as Map : const {};
}

String _hostPort(String host, int port) => '${host.contains(':') && !host.startsWith('[') ? '[$host]' : host}:$port';

String _query(Map<String, String> q) =>
    q.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

String _withQuery(String base, Map<String, String> q, String name) {
  final qs = _query(q);
  return '$base${qs.isEmpty ? '' : '?$qs'}${name.isEmpty ? '' : '#${Uri.encodeComponent(name)}'}';
}

Map<String, String> _transportQuery(_Node n) => {
  'type': n.net.isEmpty ? 'tcp' : n.net,
  if (n.net == 'ws' || n.net == 'httpupgrade' || n.net == 'http') 'path': n.path,
  if (n.net == 'ws' || n.net == 'httpupgrade' || n.net == 'http') 'host': n.hostHeader,
  if (n.net == 'grpc') 'serviceName': n.serviceName,
};

/// #30 / #35: the node's share link (vless:// vmess:// trojan:// ss:// hysteria2:// tuic://
/// hysteria:// socks:// http://), named [name]; null when the protocol has no common link form
/// or the node isn't in [raw].
String? museNodeShareLink(String raw, String tag, {String name = ''}) {
  final o = museFindOutbound(raw, tag);
  if (o == null) return null;
  final n = _Node(o);
  if (n.server.isEmpty || n.port <= 0) return null;
  final label = name.isEmpty ? tag : name;
  final hp = _hostPort(n.server, n.port);
  final u = Uri.encodeComponent;
  switch (n.type) {
    case 'vless':
      return _withQuery('vless://${u(n.s('uuid'))}@$hp', {
        'encryption': 'none',
        'flow': n.s('flow'),
        'security': n.reality ? 'reality' : (n.tlsOn ? 'tls' : 'none'),
        'sni': n.sni,
        'fp': n.fp,
        'pbk': n.reality ? n.pbk : '',
        'sid': n.reality ? n.sid : '',
        'alpn': n.alpn.join(','),
        if (n.insecure) 'allowInsecure': '1',
        ..._transportQuery(n),
      }, label);
    case 'vmess':
      final m = {
        'v': '2',
        'ps': label,
        'add': n.server,
        'port': '${n.port}',
        'id': n.s('uuid'),
        'aid': '${(o['alter_id'] as num?)?.toInt() ?? 0}',
        'scy': n.s('security').isEmpty ? 'auto' : n.s('security'),
        'net': n.net.isEmpty ? 'tcp' : n.net,
        'type': 'none',
        'host': n.hostHeader,
        'path': n.net == 'grpc' ? n.serviceName : n.path,
        'tls': n.tlsOn ? 'tls' : '',
        'sni': n.sni,
        'alpn': n.alpn.join(','),
        'fp': n.fp,
      };
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(m)))}';
    case 'trojan':
      return _withQuery('trojan://${u(n.s('password'))}@$hp', {
        'security': n.reality ? 'reality' : 'tls',
        'sni': n.sni,
        'fp': n.fp,
        'pbk': n.reality ? n.pbk : '',
        'sid': n.reality ? n.sid : '',
        'alpn': n.alpn.join(','),
        if (n.insecure) 'allowInsecure': '1',
        ..._transportQuery(n),
      }, label);
    case 'shadowsocks':
      final user = base64Url.encode(utf8.encode('${n.s('method')}:${n.s('password')}')).replaceAll('=', '');
      final plugin = n.s('plugin');
      final opts = n.s('plugin_opts');
      return _withQuery('ss://$user@$hp', {
        if (plugin.isNotEmpty) 'plugin': opts.isEmpty ? plugin : '$plugin;$opts',
      }, label);
    case 'hysteria2':
      final auth = n.s('password');
      return _withQuery('hysteria2://${auth.isEmpty ? '' : '${u(auth)}@'}$hp/', {
        'sni': n.sni,
        if (n.insecure) 'insecure': '1',
        'obfs': '${n.obfs['type'] ?? ''}',
        'obfs-password': '${n.obfs['password'] ?? ''}',
        'mport': n.serverPorts.map((p) => p.replaceAll(':', '-')).join(','),
        'alpn': n.alpn.join(','),
      }, label);
    case 'tuic':
      return _withQuery('tuic://${u(n.s('uuid'))}:${u(n.s('password'))}@$hp', {
        'congestion_control': n.s('congestion_control'),
        'udp_relay_mode': n.s('udp_relay_mode'),
        'alpn': n.alpn.join(','),
        'sni': n.sni,
        if (n.insecure) 'allow_insecure': '1',
      }, label);
    case 'hysteria':
      return _withQuery('hysteria://$hp', {
        'protocol': 'udp',
        'auth': n.s('auth_str'),
        'peer': n.sni,
        if (n.insecure) 'insecure': '1',
        'upmbps': n.s('up_mbps'),
        'downmbps': n.s('down_mbps'),
        'alpn': n.alpn.join(','),
        'obfsParam': o['obfs'] is String ? n.s('obfs') : '',
      }, label);
    case 'socks':
      final user = n.s('username');
      final cred = user.isEmpty ? '' : '${base64Url.encode(utf8.encode('$user:${n.s('password')}')).replaceAll('=', '')}@';
      return _withQuery('socks://$cred$hp', const {}, label);
    case 'http':
      final user = n.s('username');
      final cred = user.isEmpty ? '' : '${u(user)}:${u(n.s('password'))}@';
      return _withQuery('${n.tlsOn ? 'https' : 'http'}://$cred$hp', const {}, label);
    default:
      return null;
  }
}

// ---------------------------------------------------------------- Clash YAML

String _y(Object v) => v is String ? jsonEncode(v) : '$v';

String _yv(Object v) => v is Map<String, Object>
    ? _flow(v)
    : v is List<String>
    ? '[${v.map(jsonEncode).join(', ')}]'
    : _y(v);

String _flow(Map<String, Object> m) => '{${m.entries.map((e) => '${e.key}: ${_yv(e.value)}').join(', ')}}';

/// #35: the node as one entry of a Clash `proxies:` list (YAML), named [name]; null when the
/// protocol has no Clash form or the node isn't in [raw].
String? museNodeAsClash(String raw, String tag, {String name = ''}) {
  final o = museFindOutbound(raw, tag);
  if (o == null) return null;
  final n = _Node(o);
  if (n.server.isEmpty || n.port <= 0) return null;
  final m = <String, Object>{'name': name.isEmpty ? tag : name};
  void transport() {
    if (n.net.isEmpty) return;
    m['network'] = n.net == 'http' ? 'h2' : n.net;
    if (n.net == 'ws' || n.net == 'httpupgrade') {
      m['ws-opts'] = <String, Object>{
        if (n.path.isNotEmpty) 'path': n.path,
        if (n.hostHeader.isNotEmpty) 'headers': <String, Object>{'Host': n.hostHeader},
        if (n.net == 'httpupgrade') 'v2ray-http-upgrade': true,
      };
      if (n.net == 'httpupgrade') m['network'] = 'ws';
    } else if (n.net == 'grpc') {
      m['grpc-opts'] = <String, Object>{'grpc-service-name': n.serviceName};
    } else if (n.net == 'http') {
      m['h2-opts'] = <String, Object>{
        if (n.path.isNotEmpty) 'path': n.path,
        if (n.hostHeader.isNotEmpty) 'host': [n.hostHeader],
      };
    }
  }

  void tlsCommon({String sniKey = 'servername'}) {
    if (n.sni.isNotEmpty) m[sniKey] = n.sni;
    if (n.alpn.isNotEmpty) m['alpn'] = n.alpn;
    if (n.fp.isNotEmpty) m['client-fingerprint'] = n.fp;
    if (n.insecure) m['skip-cert-verify'] = true;
    if (n.reality) m['reality-opts'] = <String, Object>{'public-key': n.pbk, if (n.sid.isNotEmpty) 'short-id': n.sid};
  }

  void head(String type) {
    m['type'] = type;
    m['server'] = n.server;
    m['port'] = n.port;
  }

  switch (n.type) {
    case 'vless':
      head('vless');
      m['uuid'] = n.s('uuid');
      if (n.s('flow').isNotEmpty) m['flow'] = n.s('flow');
      if (n.tlsOn) m['tls'] = true;
      tlsCommon();
      transport();
      m['udp'] = true;
    case 'vmess':
      head('vmess');
      m['uuid'] = n.s('uuid');
      m['alterId'] = (o['alter_id'] as num?)?.toInt() ?? 0;
      m['cipher'] = n.s('security').isEmpty ? 'auto' : n.s('security');
      if (n.tlsOn) m['tls'] = true;
      tlsCommon();
      transport();
      m['udp'] = true;
    case 'trojan':
      head('trojan');
      m['password'] = n.s('password');
      tlsCommon(sniKey: 'sni');
      transport();
      m['udp'] = true;
    case 'shadowsocks':
      head('ss');
      m['cipher'] = n.s('method');
      m['password'] = n.s('password');
      final plugin = n.s('plugin');
      if (plugin.isNotEmpty) {
        m['plugin'] = plugin == 'obfs-local' ? 'obfs' : plugin;
        final opts = <String, Object>{};
        for (final kv in n.s('plugin_opts').split(';')) {
          final i = kv.indexOf('=');
          if (i <= 0) continue;
          final k = kv.substring(0, i);
          opts[k == 'obfs' ? 'mode' : (k == 'obfs-host' ? 'host' : k)] = kv.substring(i + 1);
        }
        if (opts.isNotEmpty) m['plugin-opts'] = opts;
      }
      m['udp'] = true;
    case 'hysteria2':
      head('hysteria2');
      if (n.serverPorts.isNotEmpty) m['ports'] = n.serverPorts.map((p) => p.replaceAll(':', '-')).join(',');
      m['password'] = n.s('password');
      if ('${n.obfs['type'] ?? ''}'.isNotEmpty) {
        m['obfs'] = '${n.obfs['type']}';
        m['obfs-password'] = '${n.obfs['password'] ?? ''}';
      }
      tlsCommon(sniKey: 'sni');
    case 'tuic':
      head('tuic');
      m['uuid'] = n.s('uuid');
      m['password'] = n.s('password');
      if (n.s('congestion_control').isNotEmpty) m['congestion-controller'] = n.s('congestion_control');
      if (n.s('udp_relay_mode').isNotEmpty) m['udp-relay-mode'] = n.s('udp_relay_mode');
      tlsCommon(sniKey: 'sni');
    case 'hysteria':
      head('hysteria');
      if (n.s('auth_str').isNotEmpty) m['auth-str'] = n.s('auth_str');
      if (n.s('up_mbps').isNotEmpty) m['up'] = n.s('up_mbps');
      if (n.s('down_mbps').isNotEmpty) m['down'] = n.s('down_mbps');
      tlsCommon(sniKey: 'sni');
    case 'socks':
      head('socks5');
      if (n.s('username').isNotEmpty) {
        m['username'] = n.s('username');
        m['password'] = n.s('password');
      }
      m['udp'] = true;
    case 'http':
      head('http');
      if (n.s('username').isNotEmpty) {
        m['username'] = n.s('username');
        m['password'] = n.s('password');
      }
      if (n.tlsOn) m['tls'] = true;
    default:
      return null;
  }
  final lines = <String>[];
  var first = true;
  for (final e in m.entries) {
    lines.add('${first ? '- ' : '  '}${e.key}: ${_yv(e.value)}');
    first = false;
  }
  return lines.join('\n');
}

/// #35: the node's own JSON from the saved config, pretty printed (null when it isn't in [raw]).
String? museNodeAsJsonConfig(String raw, String tag) {
  final o = museFindOutbound(raw, tag);
  return o == null ? null : const JsonEncoder.withIndent('  ').convert(o);
}

/// #35: the node in [format]; null when that format can't express it.
String? museNodeCopyText(String raw, String tag, MuseNodeCopyFormat format, {String name = ''}) => switch (format) {
  MuseNodeCopyFormat.link => museNodeShareLink(raw, tag, name: name),
  MuseNodeCopyFormat.clash => museNodeAsClash(raw, tag, name: name),
  MuseNodeCopyFormat.json => museNodeAsJsonConfig(raw, tag),
};
