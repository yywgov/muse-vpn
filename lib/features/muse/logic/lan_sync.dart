// 穿云 1.4.1 - 局域网同步 (pure logic, unit-tested). One device shows a QR code / pairing code with
// its LAN address and a one-time key; the other scans or types it and the two merge their
// settings and subscriptions over the local network (no account, no server):
//   * the key is 160 random bits, used once, valid for a few minutes ([museLanPairingTtl]);
//   * every message is AES-256-GCM encrypted with it (logic/sync_core.dart) and carries the
//     session id and a timestamp, so a message from another session or an old one is refused;
//   * only private (LAN) addresses are used and accepted;
//   * the merge is the same field-level merge as WebDAV sync, subscriptions are never deleted.
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:math';

import 'package:hiddify/features/muse/logic/sync_core.dart';

/// How long a pairing code stays valid.
const museLanPairingTtl = Duration(minutes: 3);

/// PBKDF2 rounds for LAN messages: the key is random (full entropy), so key stretching adds
/// nothing but delay.
const museLanIterations = 1000;

/// Wrong-key requests after which the listener stops.
const museLanMaxBadRequests = 5;

/// Largest request body accepted (a snapshot is a few KB).
const museLanMaxBody = 1024 * 1024;

const museLanScheme = 'chuanyun-sync';

const _b32 = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/0/1: easy to type

/// A new pairing key: 32 characters (160 bits) from an unambiguous alphabet.
String museNewLanKey([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(32, (_) => _b32[r.nextInt(_b32.length)]).join();
}

/// [key] in groups of four for reading out / typing.
String museGroupKey(String key) {
  final out = StringBuffer();
  for (var i = 0; i < key.length; i += 4) {
    if (i > 0) out.write('-');
    out.write(key.substring(i, min(i + 4, key.length)));
  }
  return out.toString();
}

/// A typed key back to its canonical form (case, spaces and dashes ignored); null when invalid.
String? museNormalizeKey(String typed) {
  final k = typed.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
  if (k.length != 32) return null;
  for (final c in k.split('')) {
    if (!_b32.contains(c)) return null;
  }
  return k;
}

/// What a QR code / pairing code carries.
class MuseLanPairing {
  const MuseLanPairing({required this.host, required this.port, required this.key, required this.expiresAt, this.device = ''});

  final String host;
  final int port;
  final String key;

  /// ms since epoch
  final int expiresAt;
  final String device;

  bool expired(DateTime now) => now.millisecondsSinceEpoch >= expiresAt;

  /// The text inside the QR code.
  String toUri() => Uri(
    scheme: museLanScheme,
    host: host,
    port: port,
    queryParameters: {'k': key, 'e': '${expiresAt ~/ 1000}', if (device.isNotEmpty) 'n': device},
  ).toString();

  /// The code for typing on a device without a camera: 「192.168.1.5:43125 ABCD-EFGH-…」.
  String get manualCode => '$host:$port ${museGroupKey(key)}';
}

/// Parses a scanned `chuanyun-sync://` link or a typed pairing code. A typed code has no expiry
/// in it: the other side enforces its own. null when it isn't one.
MuseLanPairing? museParseLanPairing(String raw, {DateTime? now}) {
  final s = raw.trim();
  if (s.toLowerCase().startsWith('$museLanScheme://')) {
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty || !u.hasPort) return null;
    final key = museNormalizeKey(u.queryParameters['k'] ?? '');
    final exp = int.tryParse(u.queryParameters['e'] ?? '');
    if (key == null || exp == null || !museIsLanAddress(u.host)) return null;
    return MuseLanPairing(host: u.host, port: u.port, key: key, expiresAt: exp * 1000, device: u.queryParameters['n'] ?? '');
  }
  final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5})\s+([A-Za-z0-9\-\s]+)$').firstMatch(s);
  if (m == null) return null;
  final host = m.group(1)!;
  final port = int.parse(m.group(2)!);
  final key = museNormalizeKey(m.group(3)!);
  if (key == null || !museIsLanAddress(host) || port < 1 || port > 65535) return null;
  final t = now ?? DateTime.now();
  return MuseLanPairing(host: host, port: port, key: key, expiresAt: t.add(museLanPairingTtl).millisecondsSinceEpoch);
}

int? _v4(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return null;
  var v = 0;
  for (final x in p) {
    final n = int.tryParse(x);
    if (n == null || n < 0 || n > 255) return null;
    v = (v << 8) | n;
  }
  return v;
}

/// A private IPv4 address (10/8, 172.16/12, 192.168/16, 169.254/16): the only ones LAN sync
/// listens on, connects to and accepts.
bool museIsLanAddress(String ip) {
  final v = _v4(ip);
  if (v == null) return false;
  bool inNet(String base, int bits) => (v >> (32 - bits)) == (_v4(base)! >> (32 - bits));
  return inNet('10.0.0.0', 8) || inNet('172.16.0.0', 12) || inNet('192.168.0.0', 16) || inNet('169.254.0.0', 16);
}

/// Interface names that are not the real LAN (VPN tunnels, virtual machines, containers).
final _virtualIf = RegExp(r'(vethernet|vmware|virtualbox|vbox|hyper-v|wsl|docker|tun|tap|wintun|chuanyun|singbox|loopback|utun|ppp|rmnet)', caseSensitive: false);

/// The address to listen on out of (interface name, IPv4) pairs: a private address on a real
/// interface, Wi‑Fi / home ranges first. null when there is none (not on a LAN).
String? musePickLanAddress(List<(String, String)> addresses) {
  int rank((String, String) a) {
    final ip = a.$2;
    var r = ip.startsWith('192.168.') ? 0 : (ip.startsWith('10.') ? 1 : (ip.startsWith('169.254.') ? 4 : 2));
    if (_virtualIf.hasMatch(a.$1)) r += 10;
    return r;
  }

  final ok = addresses.where((a) => museIsLanAddress(a.$2)).toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  if (ok.isEmpty) return null;
  // a virtual adapter only when nothing else is there
  return ok.first.$2;
}

// ---------------------------------------------------------------- messages

class MuseLanException implements Exception {
  const MuseLanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One LAN message before encryption.
class MuseLanMessage {
  const MuseLanMessage({required this.type, required this.session, required this.at, required this.device, required this.snapshot, this.firstSync = false});

  /// 'push' (client → host) or 'merged' (host → client)
  final String type;
  final String session;
  final int at;
  final String device;
  final MuseSnapshot snapshot;

  /// the sender never synced before (its values yield to the other side's)
  final bool firstSync;

  Map<String, dynamic> toJson() => {
    't': type,
    'sid': session,
    'at': at,
    'dev': device,
    'first': firstSync,
    'snap': snapshot.toJson(),
  };

  static MuseLanMessage fromJson(Map<String, dynamic> j) => MuseLanMessage(
    type: '${j['t'] ?? ''}',
    session: '${j['sid'] ?? ''}',
    at: (j['at'] as num?)?.toInt() ?? 0,
    device: '${j['dev'] ?? ''}',
    firstSync: j['first'] == true,
    snapshot: MuseSnapshot.fromJson(Map<String, dynamic>.from(j['snap'] as Map? ?? const {})),
  );
}

/// The session id both sides derive from the key (never sent in the clear).
String museLanSession(String key) => base64Url.encode(utf8.encode(key)).substring(0, 12);

/// Encrypts [m] with the pairing key.
String museLanSeal(MuseLanMessage m, String key) => museEncrypt(jsonEncode(m.toJson()), key, iterations: museLanIterations);

/// Decrypts and checks a message: right key, this session, the expected type, not older or
/// newer than the pairing allows. Throws [MuseLanException].
MuseLanMessage museLanOpen(String body, String key, {required String expectType, required DateTime now}) {
  final String plain;
  try {
    plain = museDecrypt(body, key);
  } on MuseCryptoException {
    throw const MuseLanException('配对码不对');
  }
  final MuseLanMessage m;
  try {
    m = MuseLanMessage.fromJson(jsonDecode(plain) as Map<String, dynamic>);
  } catch (_) {
    throw const MuseLanException('数据已损坏');
  }
  if (m.session != museLanSession(key) || m.type != expectType) throw const MuseLanException('不是这次配对的数据');
  final age = now.millisecondsSinceEpoch - m.at;
  if (age.abs() > museLanPairingTtl.inMilliseconds + 60000) throw const MuseLanException('配对已过期，或两台设备的时间相差太多');
  return m;
}

/// The host's merge: its own stamped [host] entries with the client's. A client that never
/// synced before yields on keys the host has (its stamps count as 0), as with WebDAV.
MuseSnapshot museLanMerge(MuseSnapshot host, MuseLanMessage client) {
  var remote = client.snapshot;
  if (client.firstSync) {
    remote = MuseSnapshot({
      for (final e in remote.entries.entries)
        e.key: host.entries.containsKey(e.key) && e.value.value != null ? MuseSyncEntry(e.value.value, 0) : e.value,
    }, device: remote.device);
  }
  return museMergeSnapshots(host, remote);
}

/// 1.5.0 #195: what to check when the other device can't be reached.
const museLanChecks =
    '① 两台设备连着同一个 Wi‑Fi（访客网络、手机热点的「AP 隔离」会挡住设备互访）；② Windows 防火墙允许穿云访问专用网络；③ 对方没有开着其他 VPN';
const museLanUnreachableHint = '连不上对方，请检查：$museLanChecks';
const museLanNoAnswerHint = '对方没有回应：确认对方已打开配对码并点了同意；还不行请检查：$museLanChecks';
