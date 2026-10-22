// 穿云 1.4.0 - 连接与网络 (pure logic, unit-tested): DNS presets (DoH / DoT / DoQ), local port
// checks, Wi‑Fi rules, timed connect / disconnect, connection-quality watch, the Windows system
// proxy bypass list and command-line arguments, and the release asset for this device.
// Part of 穿云 (GPLv3).

import 'dart:convert';

// ---------------------------------------------------------------- DNS

class MuseDnsPreset {
  const MuseDnsPreset(this.key, this.title, this.address);

  final String key;
  final String title;

  /// the core's remote DNS address
  final String address;
}

/// Remote DNS choices (through the node). 'default' keeps the app's built-in value.
const museDnsPresets = <MuseDnsPreset>[
  MuseDnsPreset('default', '默认', ''),
  MuseDnsPreset('cf-doh', 'Cloudflare DoH', 'https://1.1.1.1/dns-query'),
  MuseDnsPreset('google-doh', 'Google DoH', 'https://8.8.8.8/dns-query'),
  MuseDnsPreset('quad9-doh', 'Quad9 DoH', 'https://9.9.9.9/dns-query'),
  MuseDnsPreset('cf-dot', 'Cloudflare DoT', 'tls://1.1.1.1'),
  MuseDnsPreset('google-dot', 'Google DoT', 'tls://8.8.8.8'),
  MuseDnsPreset('adguard-doq', 'AdGuard DoQ', 'quic://94.140.14.140'),
  MuseDnsPreset('ali-doh', '阿里 DoH', 'https://223.5.5.5/dns-query'),
];

MuseDnsPreset museDnsPreset(String key) => museDnsPresets.where((p) => p.key == key).firstOrNull ?? museDnsPresets.first;

/// A custom DNS address the core understands: udp/tcp/tls/https/quic/h3 URL or a bare IP.
bool museIsValidDnsAddress(String s) {
  final v = s.trim();
  if (v.isEmpty) return false;
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(v)) return true;
  final u = Uri.tryParse(v);
  if (u == null || u.host.isEmpty) return false;
  return const {'udp', 'tcp', 'tls', 'https', 'quic', 'h3'}.contains(u.scheme);
}

// ---------------------------------------------------------------- ports

/// A local port the user may pick (1024–65535, not one of the others).
String? musePortError(int? port, {Iterable<int> others = const []}) {
  if (port == null) return '请输入端口';
  if (port < 1024 || port > 65535) return '端口范围 1024–65535';
  if (others.contains(port)) return '和其他端口重复';
  return null;
}

// ---------------------------------------------------------------- Wi‑Fi rules

enum MuseWifiAction { none, connect, disconnect }

/// Wi‑Fi rules: `{"HomeWiFi": "disconnect", "Cafe": "connect"}` (SSID → action).
Map<String, MuseWifiAction> museParseWifiRules(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        if (e.value == 'connect' || e.value == 'disconnect')
          e.key: e.value == 'connect' ? MuseWifiAction.connect : MuseWifiAction.disconnect,
    };
  } catch (_) {
    return const {};
  }
}

String museWifiRulesToRaw(Map<String, MuseWifiAction> rules) => jsonEncode({
  for (final e in rules.entries)
    if (e.value != MuseWifiAction.none) e.key: e.value.name,
});

/// What to do when the network becomes [ssid] (null = not on Wi‑Fi). A manual disconnect by the
/// user is respected: rules never connect while [userStopped].
MuseWifiAction museWifiDecide(Map<String, MuseWifiAction> rules, String? ssid, {required bool running, required bool userStopped}) {
  if (ssid == null) return MuseWifiAction.none;
  final a = rules[ssid] ?? MuseWifiAction.none;
  if (a == MuseWifiAction.connect && (running || userStopped)) return MuseWifiAction.none;
  if (a == MuseWifiAction.disconnect && !running) return MuseWifiAction.none;
  return a;
}

// ---------------------------------------------------------------- schedule

/// 定时连接 / 断开: minutes after midnight, -1 = off.
class MuseSchedule {
  const MuseSchedule({this.connectAt = -1, this.disconnectAt = -1});

  final int connectAt;
  final int disconnectAt;

  bool get isOff => connectAt < 0 && disconnectAt < 0;

  static MuseSchedule parse(String raw) {
    final p = raw.split(',');
    int at(int i) => i < p.length ? int.tryParse(p[i].trim()) ?? -1 : -1;
    return MuseSchedule(connectAt: at(0), disconnectAt: at(1));
  }

  String toRaw() => '$connectAt,$disconnectAt';
}

/// Minutes since the epoch (local wall clock), the unit [museScheduleDue] remembers.
int museEpochMinute(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute).millisecondsSinceEpoch ~/ 60000;

/// What the schedule wants at [now]. [lastFired] is the [museEpochMinute] of the slot that last
/// fired (so each time fires once per day — 1.4.1: was the minute of the day, which never fired
/// again on the next day at the same time). A tick that comes up to [grace] late (timer drift,
/// a busy moment) still fires the slot.
MuseWifiAction museScheduleDue(
  MuseSchedule s,
  DateTime now, {
  required int lastFired,
  required bool running,
  Duration grace = const Duration(minutes: 2),
}) {
  MuseWifiAction? check(int at, MuseWifiAction action) {
    if (at < 0 || at >= 24 * 60) return null;
    final slot = DateTime(now.year, now.month, now.day, at ~/ 60, at % 60);
    final late = now.difference(slot);
    if (late.isNegative || late > grace) return null;
    if (museEpochMinute(slot) == lastFired) return null;
    return action;
  }

  final c = check(s.connectAt, MuseWifiAction.connect);
  if (c != null && !running) return c;
  final d = check(s.disconnectAt, MuseWifiAction.disconnect);
  if (d != null && running) return d;
  return MuseWifiAction.none;
}

/// The slot [museScheduleDue] just fired at [now] for [action] (store it as lastFired).
int museScheduleSlot(MuseSchedule s, DateTime now, MuseWifiAction action) {
  final at = action == MuseWifiAction.connect ? s.connectAt : s.disconnectAt;
  return museEpochMinute(DateTime(now.year, now.month, now.day, at ~/ 60, at % 60));
}

String museMinuteLabel(int m) => m < 0 ? '关闭' : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

// ---------------------------------------------------------------- quality watch

/// 连接质量变差: the last [window] probes of the current node; worse = most of them over
/// [slowMs] or lost. One alert per bad spell (until it gets good again).
class MuseQualityWatch {
  MuseQualityWatch({this.window = 5, this.slowMs = 800});

  final int window;
  final int slowMs;
  final List<int> _samples = [];
  bool _alerted = false;

  /// Adds a probe (0 / >= 65000 = lost); true when the user should be told now.
  bool add(int delay) {
    _samples.add(delay);
    if (_samples.length > window) _samples.removeAt(0);
    if (_samples.length < window) return false;
    final bad = _samples.where((d) => d <= 0 || d >= 65000 || d > slowMs).length;
    if (bad * 2 > window) {
      if (_alerted) return false;
      _alerted = true;
      return true;
    }
    if (bad == 0) _alerted = false;
    return false;
  }
}

// ---------------------------------------------------------------- Windows

/// The system proxy bypass list as Windows wants it (`;`-separated), from one entry per line.
String museBypassList(String text) {
  final items = <String>[];
  for (final l in const LineSplitter().convert(text)) {
    for (final part in l.split(RegExp(r'[;,]'))) {
      final v = part.trim();
      if (v.isNotEmpty && !items.contains(v)) items.add(v);
    }
  }
  return items.join(';');
}

const museDefaultBypass = 'localhost\n127.*\n10.*\n172.16.*\n192.168.*\n<local>';

/// Command-line arguments 穿云.exe understands.
class MuseCliArgs {
  const MuseCliArgs({this.connect = false, this.disconnect = false, this.node, this.silent = false});

  final bool connect;
  final bool disconnect;
  final String? node;

  /// start in the tray without a window
  final bool silent;

  bool get isEmpty => !connect && !disconnect && node == null && !silent;
}

/// `--connect`, `--disconnect`, `--node=<name>` (or `--node <name>`), `--silent` / `--tray`.
MuseCliArgs museParseCliArgs(List<String> args) {
  var connect = false;
  var disconnect = false;
  var silent = false;
  String? node;
  for (var i = 0; i < args.length; i++) {
    final a = args[i].trim();
    if (a == '--connect') connect = true;
    if (a == '--disconnect') disconnect = true;
    if (a == '--silent' || a == '--tray' || a == '--autostart') silent = true;
    if (a.startsWith('--node=')) node = a.substring(7);
    if (a == '--node' && i + 1 < args.length) node = args[++i];
  }
  if (node != null && node.trim().isEmpty) node = null;
  return MuseCliArgs(connect: connect || node != null, disconnect: disconnect, node: node, silent: silent);
}

// ---------------------------------------------------------------- update assets

/// Android release asset names to try for a device ABI, best first (1.4.0: a small arm64 package
/// plus a universal one).
List<String> museApkAssetsFor(String abi) {
  final a = abi.toLowerCase();
  if (a.contains('arm64') || a.contains('aarch64')) return ['Chuanyun-Android-arm64.apk', 'Chuanyun-Android-universal.apk'];
  return ['Chuanyun-Android-universal.apk'];
}

/// The newest release out of a GitHub release list: stable only, or (beta channel) prereleases
/// too. Drafts are never used. The list is newest first as GitHub returns it.
Map<String, dynamic>? musePickRelease(List<Map<String, dynamic>> releases, {required bool beta}) {
  for (final r in releases) {
    if (r['draft'] == true) continue;
    if (r['prerelease'] == true && !beta) continue;
    return r;
  }
  return null;
}

// ---------------------------------------------------------------- 1.4.1: sleep / wake

/// Notices that the device slept (or the app was frozen): a periodic tick that arrives much later
/// than [interval].
class MuseWakeDetector {
  MuseWakeDetector({this.interval = const Duration(seconds: 15), this.slack = const Duration(seconds: 45)});

  final Duration interval;
  final Duration slack;
  DateTime? _last;

  /// The gap when this tick comes after a sleep, else null.
  Duration? tick(DateTime now) {
    final last = _last;
    _last = now;
    if (last == null) return null;
    final gap = now.difference(last);
    return gap > interval + slack ? gap : null;
  }
}

enum MuseWakeAction { none, recheck, reconnect }

/// After a wake: check the connection while the user wants it on (keep-alive on), reconnect once
/// when the check failed although the network itself is back ([directOk]).
MuseWakeAction museWakeDecide({
  required bool wantConnected,
  required bool keepAlive,
  required bool running,
  bool? reachOk,
  bool directOk = true,
}) {
  if (!wantConnected || !keepAlive || !running) return MuseWakeAction.none;
  if (reachOk == null) return MuseWakeAction.recheck;
  if (!reachOk && directOk) return MuseWakeAction.reconnect;
  return MuseWakeAction.none;
}

// ---------------------------------------------------------------- 1.4.1: leftover system proxy

/// The Windows system proxy as read from the registry.
class MuseProxySetting {
  const MuseProxySetting({required this.enabled, required this.server});

  final bool enabled;
  final String server;

  /// The loopback port it points at (127.0.0.1 / localhost / [::1]), else null.
  int? get loopbackPort {
    if (!enabled) return null;
    final m = RegExp(r'(?:^|[=;\s])(?:https?=|socks=)?(?:127\.0\.0\.1|localhost|\[::1\]):(\d{1,5})', caseSensitive: false).firstMatch(server.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}

/// A system proxy left behind (穿云 crashed / was killed, or another tool died): it points at a
/// local port that nothing listens on while 穿云 isn't connected. Such a setting breaks every
/// app's internet. [listening] = something answered on that port.
bool museIsStaleProxy(MuseProxySetting s, {required bool connected, required bool listening}) {
  if (connected) return false;
  return s.loopbackPort != null && !listening;
}

// ---------------------------------------------------------------- 1.4.1: clock

/// How far this device's clock is off a server's `Date` header (null when unreadable).
Duration? museClockSkew(String? dateHeader, DateTime localNow) {
  if (dateHeader == null || dateHeader.isEmpty) return null;
  try {
    final server = HttpDateParse.parse(dateHeader);
    return localNow.toUtc().difference(server);
  } catch (_) {
    return null;
  }
}

/// RFC 1123 dates (`Thu, 22 Oct 2026 12:00:00 GMT`) without dart:io.
abstract final class HttpDateParse {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static DateTime parse(String s) {
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})').firstMatch(s);
    if (m == null) throw const FormatException('bad date');
    final month = _months.indexOf(m.group(2)!) + 1;
    if (month == 0) throw const FormatException('bad month');
    return DateTime.utc(int.parse(m.group(3)!), month, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
  }
}
