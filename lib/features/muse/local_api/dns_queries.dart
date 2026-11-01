// 穿云 1.8.0 - DNS 查询: what the core resolved, which server answered, how long it took and
// whether the cache answered. Pure logic (parsing, labels, filtering, the in-app buffer); the
// stream itself lives in local_api_providers.dart and only runs while the DNS tab is visible.
// Part of 穿云 (GPLv3).

import 'dart:convert';

/// Most queries kept in the app (the core keeps the same number).
const museDnsCapacity = 500;

/// One DNS query as the core reports it on /dns/queries.
class MuseDnsQuery {
  const MuseDnsQuery({
    required this.id,
    required this.time,
    required this.domain,
    required this.type,
    this.server = '',
    this.serverType = '',
    this.address = '',
    this.group = '',
    this.answers = const [],
    this.rcode = '',
    this.elapsedMs = 0,
    this.cached = false,
    this.optimistic = false,
    this.error = '',
  });

  final int id;
  final DateTime time;
  final String domain;

  /// A, AAAA, HTTPS, …
  final String type;

  /// tag of the server that answered (inside a group: the member)
  final String server;
  final String serverType;

  /// the server address as configured (223.5.5.5, tcp://119.29.29.29, https://…), may be empty
  final String address;
  final String group;
  final List<String> answers;
  final String rcode;
  final double elapsedMs;
  final bool cached;
  final bool optimistic;
  final String error;

  bool get failed => error.isNotEmpty || (rcode.isNotEmpty && rcode != 'NOERROR');

  static MuseDnsQuery? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final domain = '${raw['domain'] ?? ''}';
    if (domain.isEmpty) return null;
    final t = raw['time'];
    return MuseDnsQuery(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      time: t is num ? DateTime.fromMillisecondsSinceEpoch(t.toInt()) : DateTime.fromMillisecondsSinceEpoch(0),
      domain: domain,
      type: '${raw['type'] ?? ''}',
      server: '${raw['server'] ?? ''}',
      serverType: '${raw['serverType'] ?? ''}',
      address: '${raw['address'] ?? ''}',
      group: '${raw['group'] ?? ''}',
      answers: [for (final a in (raw['answers'] as List? ?? const [])) '$a'],
      rcode: '${raw['rcode'] ?? ''}',
      elapsedMs: (raw['elapsed'] as num?)?.toDouble() ?? 0,
      cached: raw['cached'] == true,
      optimistic: raw['optimistic'] == true,
      error: '${raw['error'] ?? ''}',
    );
  }
}

/// One WebSocket frame: a JSON array of queries (bad entries are skipped, a bad frame is empty).
List<MuseDnsQuery> museParseDnsFrame(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! List) return const [];
    return [
      for (final e in j)
        if (MuseDnsQuery.fromJson(e) case final q?) q,
    ];
  } catch (_) {
    return const [];
  }
}

/// Which DNS answered, in words: 223.5.5.5 / tcp://119.29.29.29 / 远程 DNS / Fake-IP / 系统 DNS.
String museDnsServerLabel(MuseDnsQuery q) {
  if (q.serverType == 'fakeip' || q.server == 'dns-fake') return 'Fake-IP';
  if (q.server.startsWith('dns-remote') || q.group.startsWith('dns-remote')) {
    return q.address.isEmpty ? '远程 DNS' : '远程 DNS（${_plain(q.address)}）';
  }
  if (q.serverType == 'local' || q.server == 'dns-local') return '系统 DNS';
  if (q.serverType == 'hosts' || q.server == 'dns-static') return '静态解析';
  if (q.address.isNotEmpty) return _plain(q.address);
  return q.server.isEmpty ? '未知' : q.server;
}

String _plain(String address) => address.startsWith('udp://') ? address.substring(6) : address;

/// The row's answer line: the addresses, or what went wrong.
String museDnsAnswerText(MuseDnsQuery q) {
  if (q.error.isNotEmpty) return '失败：${museDnsErrorText(q.error)}';
  if (q.answers.isNotEmpty) return q.answers.join('  ');
  return switch (q.rcode) {
    'NXDOMAIN' => '域名不存在',
    'SERVFAIL' => '服务器失败',
    'REFUSED' => '被拒绝',
    '' || 'NOERROR' => '无地址',
    _ => q.rcode,
  };
}

String museDnsErrorText(String error) {
  final e = error.toLowerCase();
  if (e.contains('timeout') || e.contains('deadline')) return '超时';
  if (e.contains('rejected')) return '应答被拒';
  if (e.contains('refused')) return '连接被拒';
  return error.length > 60 ? '${error.substring(0, 60)}…' : error;
}

String museDnsElapsedText(MuseDnsQuery q) {
  final ms = q.elapsedMs;
  if (ms < 1) return '<1 ms';
  if (ms < 1000) return '${ms.round()} ms';
  return '${(ms / 1000).toStringAsFixed(1)} s';
}

/// What a tap copies.
String museDnsCopyText(MuseDnsQuery q) {
  final b = StringBuffer('${q.domain} ${q.type}');
  b.write(' → ${museDnsAnswerText(q)}');
  b.write('（${museDnsServerLabel(q)}${q.cached ? '，缓存' : ''}，${museDnsElapsedText(q)}）');
  return b.toString();
}

/// Search (domain, address or server) plus an exact-domain filter; newest first.
List<MuseDnsQuery> museFilterDns(List<MuseDnsQuery> items, {String query = '', String? domain}) {
  final q = query.trim().toLowerCase();
  final d = domain?.toLowerCase();
  final out = <MuseDnsQuery>[];
  for (var i = items.length - 1; i >= 0; i--) {
    final e = items[i];
    if (d != null && e.domain.toLowerCase() != d) continue;
    if (q.isNotEmpty &&
        !e.domain.toLowerCase().contains(q) &&
        !e.answers.any((a) => a.contains(q)) &&
        !museDnsServerLabel(e).toLowerCase().contains(q)) {
      continue;
    }
    out.add(e);
  }
  return out;
}

/// The queries the DNS tab shows (oldest first, at most [capacity]). Each WebSocket starts with
/// the core's buffer, which replaces ours (the core may have restarted); later frames append.
class MuseDnsBuffer {
  MuseDnsBuffer({this.capacity = museDnsCapacity});

  final int capacity;
  final List<MuseDnsQuery> _items = [];
  int _lastId = 0;

  List<MuseDnsQuery> get items => List.unmodifiable(_items);
  int get length => _items.length;

  void reset(List<MuseDnsQuery> snapshot) {
    _items
      ..clear()
      ..addAll(snapshot.length > capacity ? snapshot.sublist(snapshot.length - capacity) : snapshot);
    _lastId = _items.isEmpty ? 0 : _items.last.id;
  }

  void addAll(List<MuseDnsQuery> batch) {
    for (final q in batch) {
      if (q.id != 0 && q.id <= _lastId) continue; // already have it
      _items.add(q);
      if (q.id != 0) _lastId = q.id;
    }
    if (_items.length > capacity) _items.removeRange(0, _items.length - capacity);
  }

  void clear() {
    _items.clear();
  }
}
