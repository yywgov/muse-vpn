// 穿云 1.14.0 R21 - 手动添加 / 编辑节点.
// - 添加: a form for the common protocols becomes a share link, kept in the subscription's 覆写
//   (extra nodes), so a subscription update never removes it.
// - 编辑: the changed fields of a subscription node are kept as a local patch by node name in the
//   same 覆写 and laid over the node when the core's file is composed; the saved subscription is
//   never changed, so an update keeps the patch (a node that disappears just has nothing to patch).
// Pure and never throws.
// Part of 穿云 (GPLv3).

import 'dart:convert';

enum MuseFormProtocol {
  vless('vless', 'VLESS'),
  vmess('vmess', 'VMess'),
  trojan('trojan', 'Trojan'),
  shadowsocks('shadowsocks', 'Shadowsocks'),
  hysteria2('hysteria2', 'Hysteria2');

  const MuseFormProtocol(this.key, this.label);
  final String key;
  final String label;

  bool get usesUuid => this == vless || this == vmess;
  bool get usesPassword => !usesUuid;

  /// TLS is a choice (Hysteria2 always uses it, Shadowsocks never).
  bool get tlsOptional => this == vless || this == vmess || this == trojan;
  bool get hasTls => this != shadowsocks;
  bool get hasTransport => this == vless || this == vmess || this == trojan;
}

const museSsMethods = ['2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', 'aes-128-gcm', 'aes-256-gcm', 'chacha20-ietf-poly1305'];

final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final _host = RegExp(r'^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$|^\d{1,3}(?:\.\d{1,3}){3}$|^\[?[0-9a-fA-F:]+\]?$');

String? museServerError(String s) {
  final v = s.trim();
  if (v.isEmpty) return '请填写地址';
  if (!_host.hasMatch(v)) return '地址格式不对（填域名或 IP，不要带 http:// 和端口）';
  return null;
}

String? musePortError(String s) {
  final p = int.tryParse(s.trim());
  if (p == null || p < 1 || p > 65535) return '端口应为 1–65535 的数字';
  return null;
}

class MuseNodeForm {
  const MuseNodeForm({
    this.protocol = MuseFormProtocol.vless,
    this.name = '',
    this.server = '',
    this.port = '443',
    this.uuid = '',
    this.password = '',
    this.method = '2022-blake3-aes-128-gcm',
    this.tls = true,
    this.sni = '',
    this.insecure = false,
    this.ws = false,
    this.path = '',
    this.wsHost = '',
  });

  final MuseFormProtocol protocol;
  final String name;
  final String server;
  final String port;
  final String uuid;
  final String password;
  final String method;
  final bool tls;
  final String sni;
  final bool insecure;

  /// WebSocket transport (otherwise TCP)
  final bool ws;
  final String path;
  final String wsHost;

  bool get _tlsOn => protocol == MuseFormProtocol.hysteria2 || (protocol.tlsOptional && tls);

  /// The first thing to fix, in Chinese (null = ready).
  String? get error {
    if (name.trim().isEmpty) return '请填写名称';
    final s = museServerError(server) ?? musePortError(port);
    if (s != null) return s;
    if (protocol.usesUuid && !_uuid.hasMatch(uuid.trim())) return 'UUID 格式不对（如 1b2c3d4e-0000-1111-2222-333344445555）';
    if (protocol.usesPassword && password.isEmpty) return '请填写密码';
    if (protocol == MuseFormProtocol.shadowsocks && !museSsMethods.contains(method)) return '请选择加密方式';
    if (ws && path.isNotEmpty && !path.startsWith('/')) return '路径应以 / 开头';
    return null;
  }

  String _hostPort() {
    final h = server.trim();
    return '${h.contains(':') && !h.startsWith('[') ? '[$h]' : h}:${int.parse(port.trim())}';
  }

  String _q(Map<String, String> q) => q.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  Map<String, String> _transport() => {
    'type': ws ? 'ws' : 'tcp',
    if (ws) 'path': path,
    if (ws) 'host': wsHost.trim(),
  };

  Map<String, String> _tlsQuery() => {
    'security': _tlsOn ? 'tls' : 'none',
    if (_tlsOn) 'sni': sni.trim(),
    if (_tlsOn && insecure) 'allowInsecure': '1',
  };

  /// The share link the 覆写 keeps (null while [error] is set).
  String? toLink() {
    if (error != null) return null;
    final tag = Uri.encodeComponent(name.trim());
    switch (protocol) {
      case MuseFormProtocol.vless:
        return 'vless://${uuid.trim()}@${_hostPort()}?${_q({'encryption': 'none', ..._tlsQuery(), ..._transport()})}#$tag';
      case MuseFormProtocol.trojan:
        return 'trojan://${Uri.encodeComponent(password)}@${_hostPort()}?${_q({..._tlsQuery(), ..._transport()})}#$tag';
      case MuseFormProtocol.hysteria2:
        return 'hysteria2://${Uri.encodeComponent(password)}@${_hostPort()}?${_q({'sni': sni.trim(), if (insecure) 'insecure': '1'})}#$tag';
      case MuseFormProtocol.shadowsocks:
        final user = base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
        return 'ss://$user@${_hostPort()}#$tag';
      case MuseFormProtocol.vmess:
        final j = {
          'v': '2',
          'ps': name.trim(),
          'add': server.trim(),
          'port': port.trim(),
          'id': uuid.trim(),
          'aid': '0',
          'scy': 'auto',
          'net': ws ? 'ws' : 'tcp',
          'type': 'none',
          'host': ws ? wsHost.trim() : '',
          'path': ws ? path : '',
          'tls': _tlsOn ? 'tls' : '',
          'sni': _tlsOn ? sni.trim() : '',
          if (_tlsOn && insecure) 'allowInsecure': '1',
        };
        return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
  }
}

// ---------------------------------------------------------------- 编辑 (local patch)

/// The fields a subscription node's local patch may change. Anything left out keeps the
/// subscription's value.
class MuseNodeEdit {
  const MuseNodeEdit({this.server, this.port, this.sni, this.uuid, this.password});

  final String? server;
  final int? port;
  final String? sni;
  final String? uuid;
  final String? password;

  bool get isEmpty => server == null && port == null && sni == null && uuid == null && password == null;

  Map<String, Object> toJson() => {
    'server': ?server,
    'server_port': ?port,
    'sni': ?sni,
    'uuid': ?uuid,
    'password': ?password,
  };

  static MuseNodeEdit fromJson(Object? j) {
    if (j is! Map) return const MuseNodeEdit();
    String? s(String k) => j[k] is String && (j[k] as String).trim().isNotEmpty ? (j[k] as String).trim() : null;
    final p = j['server_port'] is int ? j['server_port'] as int : int.tryParse('${j['server_port'] ?? ''}');
    return MuseNodeEdit(
      server: s('server'),
      port: p != null && p > 0 && p < 65536 ? p : null,
      sni: s('sni'),
      uuid: s('uuid'),
      password: j['password'] is String && (j['password'] as String).isNotEmpty ? j['password'] as String : null,
    );
  }

  /// Only what differs from [outbound] (the node as the subscription has it).
  static MuseNodeEdit diff(Map<String, dynamic> outbound, {String? server, String? port, String? sni, String? uuid, String? password}) {
    final tls = outbound['tls'] is Map ? outbound['tls'] as Map : null;
    String? changed(String? v, Object? old) => v != null && v.trim().isNotEmpty && v.trim() != '${old ?? ''}' ? v.trim() : null;
    final p = int.tryParse(port?.trim() ?? '');
    return MuseNodeEdit(
      server: changed(server, outbound['server']),
      port: p != null && p != outbound['server_port'] ? p : null,
      sni: tls == null ? null : changed(sni, tls['server_name']),
      uuid: outbound.containsKey('uuid') ? changed(uuid, outbound['uuid']) : null,
      password: outbound.containsKey('password') && password != null && password.isNotEmpty && password != outbound['password'] ? password : null,
    );
  }

  /// [outbound] with the patch laid over it (a copy; fields the node doesn't have are not added,
  /// except the address and port every node has).
  Map<String, dynamic> applyTo(Map<String, dynamic> outbound) {
    final o = Map<String, dynamic>.of(outbound);
    if (server != null) o['server'] = server;
    if (port != null) o['server_port'] = port;
    if (sni != null && o['tls'] is Map) o['tls'] = Map<String, dynamic>.from(o['tls'] as Map)..['server_name'] = sni;
    if (uuid != null && o.containsKey('uuid')) o['uuid'] = uuid;
    if (password != null && o.containsKey('password')) o['password'] = password;
    return o;
  }
}
