// 穿云 1.4.0 - 测速 over dozens of nodes (pure logic, unit-tested):
//   * how long one 测速 may take before the list stops showing 「测速中」 (bounded by the core's
//     worker count and probe timeout, never longer than 90 s);
//   * what a row shows: a live result, 「测速中」 only for nodes not answered yet in the running
//     测速, otherwise the last known delay (cached, grey) instead of a spinner text;
//   * the delay cache (last result per node of the active subscription), so 节点 shows the last
//     delays at once, also while disconnected.
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:math' as math;

/// Defaults for 设置 › 高级 › 测速.
const museTestWorkersDefault = 16;
const museTestWorkersChoices = [8, 16, 32];
const museTestTimeoutDefault = 5; // seconds per probe
const museTestTimeoutChoices = [3, 5, 8];

/// The longest a 测速 of [nodes] nodes can take with [workers] parallel tests and a probe
/// timeout of [timeoutSec]: a dead node holds a worker about timeout + 3 s (warm-up, then short
/// samples). Clamped to 8–90 s.
Duration museTestCap({required int nodes, int workers = museTestWorkersDefault, int timeoutSec = museTestTimeoutDefault}) {
  final w = workers <= 0 ? museTestWorkersDefault : workers;
  final rounds = (math.max(nodes, 1) / w).ceil();
  final perNode = timeoutSec + 3 + 1;
  final secs = (rounds * perNode + 3).clamp(8, 90);
  return Duration(seconds: secs);
}

enum MuseDelayKind { live, cached, pending, timeout, none }

class MuseDelayView {
  const MuseDelayView(this.kind, this.delay);

  final MuseDelayKind kind;
  final int delay;

  String get text => switch (kind) {
    MuseDelayKind.live || MuseDelayKind.cached => '$delay ms',
    MuseDelayKind.pending => '测速中',
    MuseDelayKind.timeout => '超时',
    MuseDelayKind.none => '—',
  };

  @override
  bool operator ==(Object other) => other is MuseDelayView && other.kind == kind && other.delay == delay;

  @override
  int get hashCode => Object.hash(kind, delay);

  @override
  String toString() => 'MuseDelayView($kind, $delay)';
}

bool museIsValidDelayMs(int d) => d > 0 && d < 65000;

/// What a node row shows.
/// [delay]/[testedAt]: the core's value (0 = none; >= 65000 = timeout).
/// [since]: when this connection started (older results count as cached, not live).
/// [testStarted]: the running 测速 (null = none). [cached]: the delay cache's value.
MuseDelayView museDelayView({
  required int delay,
  DateTime? testedAt,
  DateTime? since,
  DateTime? testStarted,
  int? cached,
}) {
  final fromBefore = since != null && testedAt != null && testedAt.isBefore(since.subtract(const Duration(seconds: 2)));
  final answeredThisTest =
      testStarted != null && testedAt != null && !testedAt.isBefore(testStarted.subtract(const Duration(seconds: 1)));
  if (testStarted != null && !answeredThisTest) {
    return const MuseDelayView(MuseDelayKind.pending, 0);
  }
  if (delay != 0 && !fromBefore) {
    return museIsValidDelayMs(delay) ? MuseDelayView(MuseDelayKind.live, delay) : const MuseDelayView(MuseDelayKind.timeout, 0);
  }
  if (cached != null && museIsValidDelayMs(cached)) return MuseDelayView(MuseDelayKind.cached, cached);
  if (delay != 0 && museIsValidDelayMs(delay)) return MuseDelayView(MuseDelayKind.cached, delay);
  return const MuseDelayView(MuseDelayKind.none, 0);
}

/// One cached result.
class MuseCachedDelay {
  const MuseCachedDelay(this.delay, this.at);

  final int delay;
  final DateTime at;
}

/// Last delays of the active subscription's nodes: `{"p": profileId, "d": {tag: [ms, epochSec]}}`.
class MuseLatencyCache {
  const MuseLatencyCache(this.profileId, this.delays);

  final String profileId;
  final Map<String, MuseCachedDelay> delays;

  static const empty = MuseLatencyCache('', {});

  /// Entries older than this are dropped when saving.
  static const maxAge = Duration(days: 7);

  static MuseLatencyCache parse(String raw) {
    if (raw.trim().isEmpty) return empty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final d = <String, MuseCachedDelay>{};
      (m['d'] as Map<String, dynamic>? ?? const {}).forEach((tag, v) {
        final l = v as List;
        if (l.length < 2) return;
        d[tag] = MuseCachedDelay((l[0] as num).toInt(), DateTime.fromMillisecondsSinceEpoch((l[1] as num).toInt() * 1000));
      });
      return MuseLatencyCache('${m['p'] ?? ''}', d);
    } catch (_) {
      return empty;
    }
  }

  String toRaw({DateTime? now}) {
    final t = now ?? DateTime.now();
    return jsonEncode({
      'p': profileId,
      'd': {
        for (final e in delays.entries)
          if (t.difference(e.value.at) < maxAge) e.key: [e.value.delay, e.value.at.millisecondsSinceEpoch ~/ 1000],
      },
    });
  }

  MuseLatencyCache forProfile(String? id) => id != null && id == profileId ? this : MuseLatencyCache(id ?? '', const {});

  int? delayOf(String tag) => delays[tag]?.delay;

  /// This cache with fresh results merged in (timeouts are kept too, so a dead node isn't shown
  /// with an old good value). Returns the same instance when nothing changed.
  MuseLatencyCache merge(String profileId, Map<String, MuseCachedDelay> fresh) {
    final base = profileId == this.profileId ? delays : const <String, MuseCachedDelay>{};
    var changed = profileId != this.profileId;
    final out = Map<String, MuseCachedDelay>.of(base);
    fresh.forEach((tag, v) {
      if (v.delay == 0) return;
      final old = out[tag];
      if (old == null || old.delay != v.delay || old.at != v.at) {
        out[tag] = v;
        changed = true;
      }
    });
    return changed ? MuseLatencyCache(profileId, out) : this;
  }
}
