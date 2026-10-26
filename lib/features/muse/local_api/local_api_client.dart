// 穿云 1.6.0 C3 - the core's local control API (127.0.0.1 only, keyed by a random per-install
// secret): live connections, closing them, live logs. Never touches the connection state: a
// failure only makes the pages show 「暂不可用」.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// A random key (32 hex chars) for the local control API.
String museNewWebSecret([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// One live connection.
@immutable
class MuseConn {
  const MuseConn({
    required this.id,
    required this.host,
    required this.destination,
    required this.network,
    required this.inbound,
    required this.chains,
    required this.rule,
    required this.process,
    required this.upload,
    required this.download,
    required this.start,
    this.upSpeed = 0,
    this.downSpeed = 0,
    this.end,
  });

  final String id;

  /// domain if known, else the destination IP
  final String host;

  /// ip:port
  final String destination;
  final String network;
  final String inbound;

  /// outbound chain, last hop first as the core reports it
  final List<String> chains;
  final String rule;

  /// process path / package (empty when the core does not report it)
  final String process;
  final int upload;
  final int download;
  final DateTime start;

  /// bytes per second since the previous frame
  final int upSpeed;
  final int downSpeed;

  /// set once the connection has ended (请求)
  final DateTime? end;

  int get total => upload + download;
  int get speed => upSpeed + downSpeed;

  /// the node it went through (first entry of the chain)
  String get node => chains.isEmpty ? '' : chains.first;

  MuseConn copyWith({int? upSpeed, int? downSpeed, DateTime? end}) => MuseConn(
    id: id,
    host: host,
    destination: destination,
    network: network,
    inbound: inbound,
    chains: chains,
    rule: rule,
    process: process,
    upload: upload,
    download: download,
    start: start,
    upSpeed: upSpeed ?? this.upSpeed,
    downSpeed: downSpeed ?? this.downSpeed,
    end: end ?? this.end,
  );

  static MuseConn? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String) return null;
    final m = (j['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dIp = '${m['destinationIP'] ?? ''}';
    final dPort = '${m['destinationPort'] ?? ''}';
    final host = '${m['host'] ?? ''}';
    final rule = '${j['rule'] ?? ''}';
    final payload = '${j['rulePayload'] ?? ''}';
    return MuseConn(
      id: id,
      host: host.isNotEmpty ? host : dIp,
      destination: dIp.isEmpty ? '' : (dIp.contains(':') ? '[$dIp]:$dPort' : '$dIp:$dPort'),
      network: '${m['network'] ?? ''}',
      inbound: '${m['type'] ?? ''}',
      chains: [for (final c in (j['chains'] as List? ?? const [])) '$c'],
      rule: payload.isEmpty ? rule : '$rule($payload)',
      process: '${m['processPath'] ?? m['process'] ?? ''}',
      upload: (j['upload'] as num?)?.toInt() ?? 0,
      download: (j['download'] as num?)?.toInt() ?? 0,
      start: DateTime.tryParse('${j['start'] ?? ''}')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// One frame of /connections after parsing.
@immutable
class MuseConnFrame {
  const MuseConnFrame({required this.connections, required this.uploadTotal, required this.downloadTotal, this.memory = 0});

  final List<MuseConn> connections;
  final int uploadTotal;
  final int downloadTotal;
  final int memory;

  static const empty = MuseConnFrame(connections: [], uploadTotal: 0, downloadTotal: 0);
}

MuseConnFrame museParseConnFrame(String raw) {
  final j = jsonDecode(raw) as Map<String, dynamic>;
  return MuseConnFrame(
    connections: [
      for (final c in (j['connections'] as List? ?? const []))
        if (c is Map) MuseConn.fromJson(c.cast<String, dynamic>()),
    ].whereType<MuseConn>().toList(),
    uploadTotal: (j['uploadTotal'] as num?)?.toInt() ?? 0,
    downloadTotal: (j['downloadTotal'] as num?)?.toInt() ?? 0,
    memory: (j['memory'] as num?)?.toInt() ?? 0,
  );
}

/// Frames bigger than this are parsed off the UI thread.
const museConnIsolateBytes = 256 * 1024;

Future<MuseConnFrame> museParseConnFrameAsync(String raw) =>
    raw.length > museConnIsolateBytes ? compute(museParseConnFrame, raw) : Future.value(museParseConnFrame(raw));

/// Keeps the live list between frames: speeds from the byte deltas, ended connections go to
/// [MuseRequestHistory]. Rows that did not change keep their identity (cheap rebuilds).
class MuseConnTracker {
  MuseConnTracker({required this.history});

  final MuseRequestHistory history;
  Map<String, MuseConn> _live = {};
  DateTime? _last;

  List<MuseConn> get live => _live.values.toList(growable: false);

  /// Applies [frame] seen at [now]; returns the live list.
  List<MuseConn> apply(MuseConnFrame frame, DateTime now) {
    final secs = _last == null ? 1.0 : max(now.difference(_last!).inMilliseconds / 1000, 0.001);
    _last = now;
    final next = <String, MuseConn>{};
    for (final c in frame.connections) {
      final prev = _live[c.id];
      if (prev == null) {
        next[c.id] = c;
      } else if (prev.upload == c.upload && prev.download == c.download && prev.speed == 0) {
        next[c.id] = prev;
      } else {
        next[c.id] = c.copyWith(
          upSpeed: max(0, ((c.upload - prev.upload) / secs).round()),
          downSpeed: max(0, ((c.download - prev.download) / secs).round()),
        );
      }
    }
    for (final e in _live.entries) {
      if (!next.containsKey(e.key)) history.add(e.value.copyWith(upSpeed: 0, downSpeed: 0, end: now));
    }
    _live = next;
    return live;
  }

  void clear() {
    _live = {};
    _last = null;
  }
}

/// Ended connections, newest first, at most [capacity] (memory only, never saved).
class MuseRequestHistory {
  MuseRequestHistory({this.capacity = 500});

  final int capacity;
  final _items = <MuseConn>[];

  List<MuseConn> get items => List.unmodifiable(_items.reversed);
  int get length => _items.length;

  void add(MuseConn c) {
    _items.add(c);
    if (_items.length > capacity) _items.removeRange(0, _items.length - capacity);
  }

  void clear() => _items.clear();
}

/// How the connections are ordered on 连接.
enum MuseConnSort {
  speed('速度'),
  duration('时长'),
  traffic('流量'),
  host('主机');

  const MuseConnSort(this.title);
  final String title;
}

List<MuseConn> museSortConns(List<MuseConn> list, MuseConnSort sort, {String query = ''}) {
  final q = query.trim().toLowerCase();
  final out = q.isEmpty
      ? List.of(list)
      : [
          for (final c in list)
            if (c.host.toLowerCase().contains(q) || c.process.toLowerCase().contains(q) || c.rule.toLowerCase().contains(q) || c.node.toLowerCase().contains(q)) c,
        ];
  int cmp(MuseConn a, MuseConn b) => switch (sort) {
    MuseConnSort.speed => b.speed.compareTo(a.speed) != 0 ? b.speed.compareTo(a.speed) : b.total.compareTo(a.total),
    MuseConnSort.duration => a.start.compareTo(b.start),
    MuseConnSort.traffic => b.total.compareTo(a.total),
    MuseConnSort.host => a.host.compareTo(b.host),
  };
  out.sort(cmp);
  return out;
}

/// One live log line.
@immutable
class MuseLogLine {
  const MuseLogLine(this.level, this.text, this.time);

  /// debug / info / warning / error
  final String level;
  final String text;
  final DateTime time;

  static MuseLogLine? fromJson(String raw, DateTime now) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final type = '${j['type'] ?? 'info'}';
      return MuseLogLine(type == 'warn' ? 'warning' : type, '${j['payload'] ?? ''}', now);
    } catch (_) {
      return null;
    }
  }
}

/// Log levels the page filters by (in order of severity).
const museLogLevels = ['debug', 'info', 'warning', 'error'];

bool museLogPasses(MuseLogLine l, String minLevel, String query) {
  final li = museLogLevels.indexOf(l.level);
  final mi = museLogLevels.indexOf(minLevel);
  if (li >= 0 && mi >= 0 && li < mi) return false;
  final q = query.trim().toLowerCase();
  return q.isEmpty || l.text.toLowerCase().contains(q);
}

/// A ring buffer of log lines (1000 by default).
class MuseLogBuffer {
  MuseLogBuffer({this.capacity = 1000});

  final int capacity;
  final _lines = <MuseLogLine>[];

  List<MuseLogLine> get lines => List.unmodifiable(_lines);

  void add(MuseLogLine l) {
    _lines.add(l);
    if (_lines.length > capacity) _lines.removeRange(0, _lines.length - capacity);
  }

  void clear() => _lines.clear();
}

/// Why the local API could not be used.
class MuseLocalApiError implements Exception {
  const MuseLocalApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// HTTP / WebSocket client for 127.0.0.1:[port] with the bearer [secret].
class MuseLocalApi {
  MuseLocalApi({required this.port, required this.secret, HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 3);
  }

  final int port;
  final String secret;
  final HttpClient _client;

  Uri _uri(String path, [Map<String, String>? q]) => Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path, queryParameters: q);

  Future<int> _send(String method, String path) async {
    try {
      final req = await _client.openUrl(method, _uri(path));
      if (secret.isNotEmpty) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      return res.statusCode;
    } on TimeoutException {
      throw const MuseLocalApiError('超时');
    } on SocketException {
      throw const MuseLocalApiError('端口未开启');
    }
  }

  /// GET [path] as JSON.
  Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final req = await _client.getUrl(_uri(path));
      if (secret.isNotEmpty) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      final res = await req.close().timeout(const Duration(seconds: 5));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == HttpStatus.unauthorized) throw const MuseLocalApiError('密钥不匹配');
      if (res.statusCode != HttpStatus.ok) throw MuseLocalApiError('HTTP ${res.statusCode}');
      return jsonDecode(body) as Map<String, dynamic>;
    } on TimeoutException {
      throw const MuseLocalApiError('超时');
    } on SocketException {
      throw const MuseLocalApiError('端口未开启');
    }
  }

  Future<bool> closeConnection(String id) async => _ok(await _send('DELETE', '/connections/${Uri.encodeComponent(id)}'));

  Future<bool> closeAll() async => _ok(await _send('DELETE', '/connections'));

  static bool _ok(int code) => code >= 200 && code < 300;

  /// A text WebSocket at [path] (frames as strings). Errors close the stream.
  Stream<String> stream(String path, {Map<String, String>? query}) async* {
    final q = {...?query, if (secret.isNotEmpty) 'token': secret};
    final uri = _uri(path, q).replace(scheme: 'ws');
    WebSocket ws;
    try {
      ws = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw const MuseLocalApiError('超时');
    } on SocketException {
      throw const MuseLocalApiError('端口未开启');
    } on WebSocketException catch (e) {
      throw MuseLocalApiError(e.message.contains('401') ? '密钥不匹配' : '无法连接');
    }
    try {
      await for (final m in ws) {
        if (m is String) yield m;
      }
    } finally {
      await ws.close();
    }
  }

  void close() => _client.close(force: true);
}
