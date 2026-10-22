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
  const MuseNodeMeta({this.rename = '', this.note = '', this.hidden = false});

  final String rename;
  final String note;
  final bool hidden;

  bool get isEmpty => rename.isEmpty && note.isEmpty && !hidden;

  MuseNodeMeta copyWith({String? rename, String? note, bool? hidden}) =>
      MuseNodeMeta(rename: rename ?? this.rename, note: note ?? this.note, hidden: hidden ?? this.hidden);

  Map<String, dynamic> toJson() => {
    if (rename.isNotEmpty) 'n': rename,
    if (note.isNotEmpty) 'r': note,
    if (hidden) 'h': 1,
  };

  static MuseNodeMeta fromJson(Map<String, dynamic> m) =>
      MuseNodeMeta(rename: '${m['n'] ?? ''}', note: '${m['r'] ?? ''}', hidden: m['h'] == 1 || m['h'] == true);

  @override
  bool operator ==(Object other) =>
      other is MuseNodeMeta && other.rename == rename && other.note == note && other.hidden == hidden;

  @override
  int get hashCode => Object.hash(rename, note, hidden);
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

// ---------------------------------------------------------------- landing region

/// The landing region does not match the region in the node's name (「名不符实」): both known and
/// different. Hong Kong / Taiwan / Macau are kept apart from mainland China.
bool museRegionMismatch({required String? nameRegion, required String? exitRegion}) {
  if (nameRegion == null || exitRegion == null || exitRegion.isEmpty) return false;
  return nameRegion.toUpperCase() != exitRegion.toUpperCase();
}
