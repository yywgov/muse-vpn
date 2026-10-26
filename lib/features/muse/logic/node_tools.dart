// 穿云 1.4.0 - node tools (pure logic, unit-tested): your own names / notes / hidden nodes that
// survive subscription updates, name tidying, include / exclude filters (regex), duplicates,
// health score, country groups with their best delay, recently used, the landing-region check
// (「名不符实」) and the delay history behind the detail chart.
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:math' as math;

// ---------------------------------------------------------------- per-node meta

/// What the user set on one node, kept by its tag (the name the subscription gives it), so it
/// survives updates of the subscription.
class MuseNodeMeta {
  const MuseNodeMeta({this.rename = '', this.note = '', this.hidden = false, this.region = '', this.tags = const []});

  final String rename;
  final String note;
  final bool hidden;

  /// 1.6.0 #32: region set by hand (ISO code) when the name doesn't say; '' = recognised from the name
  final String region;

  /// 1.6.0 #33: the user's own tags (家宽 / 流媒体 / 游戏 …)
  final List<String> tags;

  bool get isEmpty => rename.isEmpty && note.isEmpty && !hidden && region.isEmpty && tags.isEmpty;

  MuseNodeMeta copyWith({String? rename, String? note, bool? hidden, String? region, List<String>? tags}) => MuseNodeMeta(
    rename: rename ?? this.rename,
    note: note ?? this.note,
    hidden: hidden ?? this.hidden,
    region: region == null ? this.region : region.toUpperCase(),
    tags: tags == null ? this.tags : museCleanNodeTags(tags),
  );

  Map<String, dynamic> toJson() => {
    if (rename.isNotEmpty) 'n': rename,
    if (note.isNotEmpty) 'r': note,
    if (hidden) 'h': 1,
    if (region.isNotEmpty) 'g': region,
    if (tags.isNotEmpty) 't': tags,
  };

  static MuseNodeMeta fromJson(Map<String, dynamic> m) => MuseNodeMeta(
    rename: '${m['n'] ?? ''}',
    note: '${m['r'] ?? ''}',
    hidden: m['h'] == 1 || m['h'] == true,
    region: '${m['g'] ?? ''}'.toUpperCase(),
    tags: m['t'] is List ? museCleanNodeTags([for (final e in m['t'] as List) '$e']) : const [],
  );

  @override
  bool operator ==(Object other) =>
      other is MuseNodeMeta &&
      other.rename == rename &&
      other.note == note &&
      other.hidden == hidden &&
      other.region == region &&
      other.tags.join('\n') == tags.join('\n');

  @override
  int get hashCode => Object.hash(rename, note, hidden, region, tags.join('\n'));
}

/// 1.6.0 #33: the tags offered first.
const museNodeTagPresets = ['家宽', '流媒体', '游戏'];

/// Tags trimmed, de-duplicated, at most [max] (8 per node) of at most 12 characters each, in the
/// given order.
List<String> museCleanNodeTags(Iterable<String> tags, {int max = 8}) {
  final out = <String>[];
  for (final t in tags) {
    var v = t.trim().replaceAll(RegExp(r'[\s,，]+'), ' ');
    if (v.isEmpty) continue;
    if (v.length > 12) v = v.substring(0, 12);
    if (!out.contains(v)) out.add(v);
    if (out.length == max) break;
  }
  return List.unmodifiable(out);
}

/// All node metas: `{tag: {n, r, h}}`.
class MuseNodeMetas {
  const MuseNodeMetas(this.byTag);

  final Map<String, MuseNodeMeta> byTag;

  static const empty = MuseNodeMetas({});

  static MuseNodeMetas parse(String raw) {
    if (raw.trim().isEmpty) return empty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return MuseNodeMetas({
        for (final e in m.entries)
          if (e.value is Map) e.key: MuseNodeMeta.fromJson(Map<String, dynamic>.from(e.value as Map)),
      });
    } catch (_) {
      return empty;
    }
  }

  String toRaw() => jsonEncode({
    for (final e in byTag.entries)
      if (!e.value.isEmpty) e.key: e.value.toJson(),
  });

  MuseNodeMeta of(String tag) => byTag[tag] ?? const MuseNodeMeta();

  MuseNodeMetas set(String tag, MuseNodeMeta meta) {
    final next = Map<String, MuseNodeMeta>.of(byTag);
    if (meta.isEmpty) {
      next.remove(tag);
    } else {
      next[tag] = meta;
    }
    return MuseNodeMetas(next);
  }

  /// [tags] hidden (or shown again) at once.
  MuseNodeMetas setHidden(Iterable<String> tags, bool hidden) {
    var out = this;
    for (final t in tags) {
      out = out.set(t, out.of(t).copyWith(hidden: hidden));
    }
    return out;
  }

  Set<String> get hiddenTags => {for (final e in byTag.entries) if (e.value.hidden) e.key};

  /// The name to show: the user's own name, else [original] (tidied when [beautify]).
  String displayName(String tag, String original, {bool beautify = false}) {
    final own = of(tag).rename.trim();
    if (own.isNotEmpty) return own;
    return beautify ? museBeautifyNodeName(original) : original;
  }

  /// 1.6.0 #32: the node's region — the one set by hand, else [fromName] (recognised from its name).
  String? regionOf(String tag, String? fromName) {
    final own = of(tag).region;
    return own.isNotEmpty ? own : fromName;
  }

  /// 1.6.0 #33: every tag in use, presets first, then the user's own in first-seen order.
  List<String> get allTags {
    final used = <String>[for (final m in byTag.values) ...m.tags];
    return [
      for (final p in museNodeTagPresets)
        if (used.contains(p)) p,
      ...{
        for (final t in used)
          if (!museNodeTagPresets.contains(t)) t,
      },
    ];
  }

  /// 1.5.3: the name to show for a group's pick (自动最快 → its node), given by the core as the
  /// node's raw name: looked up among [items] (tag, raw name) so it reads exactly like its row.
  String pickName(String raw, Iterable<(String, String)> items, {bool beautify = false}) {
    final r = raw.trim();
    if (r.isEmpty) return r;
    for (final (tag, name) in items) {
      if (name == r || tag == r) return displayName(tag, name, beautify: beautify);
    }
    return beautify ? museBeautifyNodeName(r) : r;
  }
}

// ---------------------------------------------------------------- names

final _spaces = RegExp(r'\s+');
final _sepRuns = RegExp(r'\s*[|｜丨_·•]+\s*');
final _bracketAds = RegExp(r'[\[【(（]\s*(?:官网|官方|网址|购买|续费|订阅|客服|群|频道|TG|telegram)[^\]】)）]*[\]】)）]', caseSensitive: false);
final _flagRun = RegExp('([\u{1F1E6}-\u{1F1FF}]{2})', unicode: true);

/// Tidy a subscription's node name: separators unified to 「 · 」, advert brackets dropped,
/// repeated flags collapsed, spaces trimmed. Never returns an empty name.
String museBeautifyNodeName(String name) {
  var s = name.replaceAll(_bracketAds, ' ');
  // keep only the first flag
  var seen = false;
  s = s.replaceAllMapped(_flagRun, (m) {
    if (seen) return '';
    seen = true;
    return '${m[1]} ';
  });
  s = s.replaceAll(_sepRuns, ' · ').replaceAll(_spaces, ' ').trim();
  s = s.replaceAll(RegExp(r'^(·\s*)+|(\s*·)+$'), '').trim();
  return s.isEmpty ? name.trim() : s;
}

/// Include / exclude filters on node names (regex; an invalid pattern filters nothing and is
/// reported by [museNodeFilterError]).
bool museNodeNamePasses(String name, {String include = '', String exclude = ''}) {
  final inc = _safeRegex(include);
  final exc = _safeRegex(exclude);
  if (inc != null && !inc.hasMatch(name)) return false;
  if (exc != null && exc.hasMatch(name)) return false;
  return true;
}

String? museNodeFilterError(String pattern) {
  if (pattern.trim().isEmpty) return null;
  try {
    RegExp(pattern, caseSensitive: false);
    return null;
  } catch (e) {
    return '表达式无效';
  }
}

RegExp? _safeRegex(String p) {
  if (p.trim().isEmpty) return null;
  try {
    return RegExp(p, caseSensitive: false);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- duplicates

/// Nodes with the same protocol, address and port are duplicates; returns the tags to drop
/// (the first of each kind is kept). Nodes without an address are never duplicates.
Set<String> museDuplicateTags<T>(
  List<T> nodes, {
  required String Function(T) tag,
  required String Function(T) type,
  required String Function(T) host,
  required int Function(T) port,
}) {
  final seen = <String>{};
  final drop = <String>{};
  for (final n in nodes) {
    final h = host(n).trim().toLowerCase();
    if (h.isEmpty) continue;
    final key = '${type(n).toLowerCase()}|$h|${port(n)}';
    if (!seen.add(key)) drop.add(tag(n));
  }
  return drop;
}

// ---------------------------------------------------------------- history & health

/// The last delays of one node (0 = not answered), newest last.
class MuseDelayHistory {
  const MuseDelayHistory(this.samples);

  final List<int> samples;

  static const keep = 20;

  MuseDelayHistory add(int delay) {
    final next = [...samples, delay];
    return MuseDelayHistory(next.length > keep ? next.sublist(next.length - keep) : next);
  }

  int get answered => samples.where(_ok).length;

  /// Share of tests without an answer (0–1).
  double get loss => samples.isEmpty ? 0 : 1 - answered / samples.length;

  /// Mean absolute difference between consecutive answered delays (ms).
  double get jitter {
    final ok = samples.where(_ok).toList();
    if (ok.length < 2) return 0;
    var sum = 0;
    for (var i = 1; i < ok.length; i++) {
      sum += (ok[i] - ok[i - 1]).abs();
    }
    return sum / (ok.length - 1);
  }

  int get median {
    final ok = samples.where(_ok).toList()..sort();
    if (ok.isEmpty) return 0;
    return ok[ok.length ~/ 2];
  }

  static bool _ok(int d) => d > 0 && d < 65000;
}

/// Delay histories of the active subscription's nodes: `{"p": id, "h": {tag: [ms, ...]}}`.
class MuseDelayHistories {
  const MuseDelayHistories(this.profileId, this.byTag);

  final String profileId;
  final Map<String, MuseDelayHistory> byTag;

  static const empty = MuseDelayHistories('', {});

  static MuseDelayHistories parse(String raw) {
    if (raw.trim().isEmpty) return empty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return MuseDelayHistories('${m['p'] ?? ''}', {
        for (final e in (m['h'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: MuseDelayHistory([for (final v in e.value as List) (v as num).toInt()]),
      });
    } catch (_) {
      return empty;
    }
  }

  String toRaw() => jsonEncode({
    'p': profileId,
    'h': {for (final e in byTag.entries) e.key: e.value.samples},
  });

  MuseDelayHistory of(String tag) => byTag[tag] ?? const MuseDelayHistory([]);

  /// One new result per node ([results] tag → delay, 65535 = timeout). Another subscription
  /// starts over.
  MuseDelayHistories add(String profileId, Map<String, int> results) {
    final base = profileId == this.profileId ? byTag : const <String, MuseDelayHistory>{};
    return MuseDelayHistories(profileId, {
      ...base,
      for (final e in results.entries) e.key: (base[e.key] ?? const MuseDelayHistory([])).add(e.value >= 65000 ? 0 : e.value),
    });
  }
}

/// Health 0–100 from delay, loss and jitter (no samples = null).
int? museHealthScore(MuseDelayHistory h) {
  if (h.samples.isEmpty) return null;
  if (h.answered == 0) return 0;
  final med = h.median;
  // 100 at <= 80 ms, falling to 30 at 800 ms
  final delayScore = med <= 80 ? 100.0 : math.max(30.0, 100 - (med - 80) * 70 / 720);
  final lossPenalty = h.loss * 100;
  final jitterPenalty = math.min(25.0, h.jitter / 8);
  return (delayScore - lossPenalty - jitterPenalty).clamp(0, 100).round();
}

String museHealthLabel(int? score) => switch (score) {
  null => '未知',
  >= 80 => '优',
  >= 60 => '良',
  >= 40 => '一般',
  _ => '差',
};

// ---------------------------------------------------------------- groups & recent

class MuseCountryGroup<T> {
  const MuseCountryGroup(this.code, this.items, this.bestDelay);

  /// ISO code, null = 其他
  final String? code;
  final List<T> items;

  /// lowest valid delay in the group (0 = none)
  final int bestDelay;
}

/// Nodes grouped by country in first-seen order (其他 last), each with its best delay.
List<MuseCountryGroup<T>> museCountryGroups<T>(
  List<T> nodes, {
  required String? Function(T) region,
  required int Function(T) delay,
}) {
  final order = <String?>[];
  final map = <String?, List<T>>{};
  for (final n in nodes) {
    final r = region(n);
    if (!map.containsKey(r)) order.add(r);
    map.putIfAbsent(r, () => []).add(n);
  }
  if (order.remove(null)) order.add(null);
  return [
    for (final r in order)
      MuseCountryGroup<T>(r, map[r]!, map[r]!.map(delay).where((d) => d > 0 && d < 65000).fold<int>(0, (a, b) => a == 0 || b < a ? b : a)),
  ];
}

/// Recently used tags, newest first, at most [keep].
List<String> museAddRecent(List<String> recent, String tag, {int keep = 5}) =>
    [tag, ...recent.where((t) => t != tag)].take(keep).toList();

List<String> museParseRecent(String raw) =>
    raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// 1.6.0 #37: the stored recent list (a JSON list, so tags with commas survive; the older comma
/// list is still read).
List<String> museRecentFromRaw(String raw) {
  final r = raw.trim();
  if (r.startsWith('[')) {
    try {
      return [for (final e in jsonDecode(r) as List) if ('$e'.isNotEmpty) '$e'];
    } catch (_) {
      return const [];
    }
  }
  return museParseRecent(r);
}

String museRecentToRaw(List<String> recent) => jsonEncode(recent);

// ---------------------------------------------------------------- landing region

/// The landing region does not match the region in the node's name (「名不符实」): both known and
/// different. Hong Kong / Taiwan / Macau are kept apart from mainland China.
bool museRegionMismatch({required String? nameRegion, required String? exitRegion}) {
  if (nameRegion == null || exitRegion == null || exitRegion.isEmpty) return false;
  return nameRegion.toUpperCase() != exitRegion.toUpperCase();
}

// ---------------------------------------------------------------- 1.5.0 (chunk 2)

/// #25: 测速 progress — how many of [testedAt] (one entry per node, null = never tested) have an
/// answer from the run that started at [started].
({int done, int total}) museTestProgress(Iterable<DateTime?> testedAt, DateTime started) {
  var done = 0;
  var total = 0;
  final from = started.subtract(const Duration(seconds: 1));
  for (final t in testedAt) {
    total++;
    if (t != null && !t.isBefore(from)) done++;
  }
  return (done: done, total: total);
}

/// #26 / #10: one node's settings as the subscription gave them (from the saved config).
class MuseOutboundDetail {
  const MuseOutboundDetail({
    this.type = '',
    this.transport = '',
    this.tls = '',
    this.sni = '',
    this.alpn = const [],
    this.fingerprint = '',
    this.ports = '',
    this.bandwidth = '',
    this.flow = '',
  });

  final String type;

  /// ws / grpc / http / httpupgrade / xhttp / quic; '' = plain TCP
  final String transport;

  /// 'TLS' / 'REALITY' / ''
  final String tls;
  final String sni;
  final List<String> alpn;
  final String fingerprint;

  /// Hysteria2 port hopping range(s), e.g. 「20000-30000」
  final String ports;

  /// Hysteria / Hysteria2 / TUIC declared bandwidth, e.g. 「↑ 50 · ↓ 200 Mbps」
  final String bandwidth;
  final String flow;

  /// rows for the detail sheet, in order
  List<(String, String)> get rows => [
    if (transport.isNotEmpty) ('传输', transport),
    if (tls.isNotEmpty) ('安全', tls),
    if (sni.isNotEmpty) ('SNI', sni),
    if (alpn.isNotEmpty) ('ALPN', alpn.join(', ')),
    if (fingerprint.isNotEmpty) ('指纹', fingerprint),
    if (flow.isNotEmpty) ('流控', flow),
    if (ports.isNotEmpty) ('端口跳跃', ports),
    if (bandwidth.isNotEmpty) ('带宽', bandwidth),
  ];
}

String _transportLabel(String t) => switch (t.toLowerCase()) {
  'ws' => 'WebSocket',
  'grpc' => 'gRPC',
  'http' => 'HTTP/2',
  'httpupgrade' => 'HTTPUpgrade',
  'xhttp' => 'XHTTP',
  'quic' => 'QUIC',
  '' => '',
  _ => t,
};

List<String> _strings(Object? v) => [
  if (v is List) for (final e in v) if ('$e'.isNotEmpty) '$e',
  if (v is String && v.isNotEmpty) v,
];

/// The node [tag] of a saved config (sing-box JSON, as the core wrote it); falls back to the one
/// at [host]:[port] when the tag isn't there. Null when it can't be read or isn't found.
MuseOutboundDetail? museOutboundDetail(String raw, String tag, {String host = '', int port = 0}) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    final all = [...((j['outbounds'] as List?) ?? const []), ...((j['endpoints'] as List?) ?? const [])].whereType<Map>().toList();
    Map? o = all.where((e) => e['tag'] == tag).firstOrNull;
    if (o == null && host.isNotEmpty) {
      o = all.where((e) => e['server'] == host && (port == 0 || e['server_port'] == port)).firstOrNull;
    }
    if (o == null) return null;
    final type = '${o['type'] ?? ''}'.toLowerCase();
    final tls = o['tls'] is Map ? o['tls'] as Map : const {};
    final transport = o['transport'] is Map ? '${(o['transport'] as Map)['type'] ?? ''}' : '';
    final utls = tls['utls'] is Map ? tls['utls'] as Map : const {};
    final reality = tls['reality'] is Map && (tls['reality'] as Map)['enabled'] == true;
    final quicBased = type == 'hysteria2' || type == 'hysteria' || type == 'tuic';
    final tlsLabel = reality
        ? 'REALITY'
        : tls['enabled'] == true
        ? (tls['insecure'] == true ? 'TLS（跳过证书验证）' : 'TLS')
        : '';
    final ports = _strings(o['server_ports']).map((p) => p.replaceAll(':', '-')).join(', ');
    final up = o['up_mbps'];
    final down = o['down_mbps'];
    final bw = (up is num && up > 0) || (down is num && down > 0)
        ? [if (up is num && up > 0) '↑ $up', if (down is num && down > 0) '↓ $down'].join(' · ') + ' Mbps'
        : '';
    return MuseOutboundDetail(
      type: type,
      transport: quicBased ? 'QUIC' : _transportLabel(transport),
      tls: tlsLabel,
      sni: '${tls['server_name'] ?? ''}',
      alpn: _strings(tls['alpn']),
      fingerprint: utls['enabled'] == true ? '${utls['fingerprint'] ?? ''}' : '',
      ports: ports,
      bandwidth: bw,
      flow: '${o['flow'] ?? ''}',
    );
  } catch (_) {
    return null;
  }
}

/// #24: a download speed in plain words (bytes per second).
String museSpeedText(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '—';
  final mbps = bytesPerSecond * 8 / 1e6;
  final mbs = bytesPerSecond / (1024 * 1024);
  if (mbs >= 1) return '${mbs.toStringAsFixed(mbs >= 10 ? 0 : 1)} MB/s（${mbps.toStringAsFixed(0)} Mbps）';
  final kbs = bytesPerSecond / 1024;
  return '${kbs.toStringAsFixed(0)} KB/s（${mbps.toStringAsFixed(1)} Mbps）';
}

// ---------------------------------------------------------------- 1.6.0 (batch 2, nodes)

/// #28 / #33: what 节点 is narrowed to — one protocol (by its short label, 「VLESS」) or one of the
/// user's tags. Stored as 「p:VLESS」 / 「t:家宽」; '' = everything.
class MuseNodeFilter {
  const MuseNodeFilter._(this.kind, this.value);

  /// 'p' (protocol), 't' (tag) or '' (none)
  final String kind;
  final String value;

  static const none = MuseNodeFilter._('', '');

  factory MuseNodeFilter.protocol(String short) => MuseNodeFilter._('p', short);
  factory MuseNodeFilter.tag(String tag) => MuseNodeFilter._('t', tag);

  static MuseNodeFilter parse(String raw) {
    final r = raw.trim();
    if (r.length > 2 && (r.startsWith('p:') || r.startsWith('t:'))) return MuseNodeFilter._(r[0], r.substring(2));
    if (r.isNotEmpty && !r.contains(':')) return MuseNodeFilter._('p', r.toUpperCase());
    return none;
  }

  bool get isNone => kind.isEmpty;

  String toRaw() => isNone ? '' : '$kind:$value';

  /// The label in the toolbar / menu.
  String get label => isNone ? '全部' : value;

  /// Whether a node of [protocolShort] with [tags] stays in the list.
  bool passes({required String protocolShort, required List<String> tags}) => switch (kind) {
    'p' => protocolShort.toUpperCase() == value.toUpperCase(),
    't' => tags.contains(value),
    _ => true,
  };

  /// A filter whose protocol / tag no longer exists among the nodes filters nothing (so the
  /// list never stays empty after the subscription changed).
  MuseNodeFilter within({required Iterable<String> protocols, required Iterable<String> tags}) => switch (kind) {
    'p' => protocols.any((p) => p.toUpperCase() == value.toUpperCase()) ? this : none,
    't' => tags.contains(value) ? this : none,
    _ => none,
  };

  @override
  bool operator ==(Object other) => other is MuseNodeFilter && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// #28: the protocols (short labels) among [shorts], most common first, ties by name.
List<String> museProtocolsPresent(Iterable<String> shorts) {
  final count = <String, int>{};
  for (final s in shorts) {
    if (s.isEmpty) continue;
    count[s] = (count[s] ?? 0) + 1;
  }
  return count.keys.toList()..sort((a, b) => count[b]! != count[a]! ? count[b]!.compareTo(count[a]!) : a.compareTo(b));
}

/// #29: the last [keep] delays as heights 0–1 for the detail's mini line (1 = the slowest of
/// them, 0.15 = the fastest, 0.5 when all are equal); null = no answer (a gap).
List<double?> museSparkline(List<int> samples, {int keep = 10}) {
  final last = samples.length > keep ? samples.sublist(samples.length - keep) : samples;
  bool ok(int d) => d > 0 && d < 65000;
  final good = last.where(ok);
  if (good.isEmpty) return [for (final _ in last) null];
  final hi = good.reduce(math.max).toDouble();
  final lo = good.reduce(math.min).toDouble();
  return [
    for (final d in last)
      if (!ok(d))
        null
      else if (hi == lo)
        0.5
      else
        0.15 + 0.85 * (d - lo) / (hi - lo),
  ];
}

/// #37: the recently used nodes to offer (newest first): only those still in the list, not the
/// one in use, at most [keep].
List<String> museRecentToOffer(List<String> recent, {required Iterable<String> present, required String selected, int keep = 5}) {
  final has = present.toSet();
  return recent.where((t) => t != selected && has.contains(t)).take(keep).toList();
}

/// #39: regions most people use; the others start folded when the list has many regions.
const museCommonRegions = {'HK', 'TW', 'JP', 'SG', 'US', 'KR'};

/// #39: whether the region [key] (ISO code or 'other') is folded. [stored] holds 「JP」 (folded by
/// the user) or 「+DE」 (opened by the user); anything else follows the default — uncommon regions
/// fold when there are more than [few] regions; [selectedRegion] (the key of the node in use)
/// never does.
bool museRegionFolded(String key, Set<String> stored, {required int regionCount, String? selectedRegion, int few = 4}) {
  if (stored.contains(key)) return true;
  if (stored.contains('+$key')) return false;
  if (selectedRegion != null && key == selectedRegion) return false;
  return regionCount > few && !museCommonRegions.contains(key);
}

/// #39: [stored] after the user tapped [key]'s header while it was [folded].
Set<String> museToggleRegionFold(Set<String> stored, String key, {required bool folded}) => {...stored}
  ..remove(key)
  ..remove('+$key')
  ..add(folded ? '+$key' : key);
