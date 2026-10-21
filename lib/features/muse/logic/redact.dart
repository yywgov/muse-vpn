// 穿云 1.2.8 - 脱敏: what an exported log must not carry — subscription links, node share links,
// passwords / tokens, UUIDs, server addresses (IPs and server / host / sni values), e-mails.
// Part of 穿云 (GPLv3).

final _rules = <(RegExp, String Function(Match))>[
  // node share links: vmess://… vless://… ss://… trojan://… hysteria2://… tuic://… etc.
  (
    RegExp(r'\b(vmess|vless|ss|ssr|trojan|hysteria2?|hy2|tuic|wireguard|socks5?|naive\+https|anytls|mieru|shadowtls)://\S+', caseSensitive: false),
    (m) => '${m[1]}://***',
  ),
  // any other URL (subscription links, panels): keep the scheme only
  (RegExp(r'\bhttps?://[^\s"<>]+', caseSensitive: false), (m) => '${m[0]!.split('://').first}://***'),
  // "password": "…" / password=… / "uuid": … / token=…
  (
    RegExp(r'''("?(?:password|passwd|pass|psk|private_key|privatekey|pre_shared_key|uuid|token|secret|auth|auth_str|obfs-password|obfs_password|key)"?\s*[:=]\s*)("[^"]*"|[^\s,;&}]+)''', caseSensitive: false),
    (m) => '${m[1]}***',
  ),
  // "server": "…" / server=… / host / sni / server_name
  (
    RegExp(r'''("?(?:server|server_name|sni|host|address|peer|endpoint)"?\s*[:=]\s*)("[^"]*"|[^\s,;&}]+)''', caseSensitive: false),
    (m) => '${m[1]}***',
  ),
  // UUIDs
  (RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', caseSensitive: false), (m) => '<uuid>'),
  // e-mail addresses
  (RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b'), (m) => '<email>'),
  // IPv4 (loopback / unspecified kept: they say nothing about the user)
  (
    RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
    (m) => m[0]!.startsWith('127.') || m[0] == '0.0.0.0' ? m[0]! : '<ip>',
  ),
  // IPv6 (at least 3 groups, so times like 12:34:56 are left alone; ::1 kept)
  (
    RegExp(r'\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b|\b(?:[0-9a-f]{1,4}:){1,6}:[0-9a-f]{1,4}\b', caseSensitive: false),
    (m) => RegExp(r'^\d+:\d+:\d+$').hasMatch(m[0]!) ? m[0]! : '<ip6>',
  ),
];

/// [text] with every secret / address replaced.
String museRedact(String text) {
  var out = text;
  for (final (re, f) in _rules) {
    out = out.replaceAllMapped(re, f);
  }
  return out;
}
