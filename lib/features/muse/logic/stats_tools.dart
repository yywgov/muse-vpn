// 穿云 1.4.0 - 统计 (pure logic, unit-tested): traffic per day kept on the device (for the day /
// month charts and the monthly report), connection success counts, top lists, and the local
// crash log with its redacted feedback bundle. Nothing is ever uploaded.
// Part of 穿云 (GPLv3).

import 'dart:convert';

String museDayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String museMonthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Traffic per day: `{"2026-10-22": [up, down]}`, the last [keepDays] days.
class MuseTrafficLog {
  const MuseTrafficLog(this.days);

  final Map<String, (int, int)> days;

  static const keepDays = 400;
  static const empty = MuseTrafficLog({});

  static MuseTrafficLog parse(String raw) {
    if (raw.trim().isEmpty) return empty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return MuseTrafficLog({
        for (final e in m.entries)
          if (e.value is List && (e.value as List).length >= 2)
            e.key: (((e.value as List)[0] as num).toInt(), ((e.value as List)[1] as num).toInt()),
      });
    } catch (_) {
      return empty;
    }
  }

  String toRaw() => jsonEncode({for (final e in days.entries) e.key: [e.value.$1, e.value.$2]});

  /// [up] / [down] bytes added to [day]; days older than [keepDays] dropped.
  MuseTrafficLog add(DateTime day, int up, int down) {
    if (up <= 0 && down <= 0) return this;
    final k = museDayKey(day);
    final cur = days[k] ?? (0, 0);
    final next = {...days, k: (cur.$1 + (up < 0 ? 0 : up), cur.$2 + (down < 0 ? 0 : down))};
    if (next.length > keepDays) {
      final keys = next.keys.toList()..sort();
      for (final old in keys.take(next.length - keepDays)) {
        next.remove(old);
      }
    }
    return MuseTrafficLog(next);
  }

  /// The last [n] days ending [today] (missing days = 0), oldest first.
  List<(String, int, int)> lastDays(DateTime today, int n) => [
    for (var i = n - 1; i >= 0; i--)
      () {
        final d = DateTime(today.year, today.month, today.day - i);
        final v = days[museDayKey(d)] ?? (0, 0);
        return (museDayKey(d), v.$1, v.$2);
      }(),
  ];

  /// Totals per month, oldest first: (month, up, down).
  List<(String, int, int)> months() {
    final m = <String, (int, int)>{};
    days.forEach((k, v) {
      final mk = k.substring(0, 7);
      final cur = m[mk] ?? (0, 0);
      m[mk] = (cur.$1 + v.$1, cur.$2 + v.$2);
    });
    final keys = m.keys.toList()..sort();
    return [for (final k in keys) (k, m[k]!.$1, m[k]!.$2)];
  }
}

/// Turns the core's running session totals into per-day deltas: a total that went down means a
/// new session (counted from zero).
/// 1.4.1: the first sample after start-up / [reset] only sets the baseline. The core's totals
/// cover the whole session, and a session that was already running when the app (re)started was
/// counted before: adding the first total again double-counted it.
class MuseTrafficCounter {
  int _lastUp = 0;
  int _lastDown = 0;
  bool _primed = false;

  (int, int) delta(int up, int down) {
    if (!_primed) {
      _primed = true;
      _lastUp = up < 0 ? 0 : up;
      _lastDown = down < 0 ? 0 : down;
      return (0, 0);
    }
    final du = up >= _lastUp ? up - _lastUp : (up < 0 ? 0 : up);
    final dd = down >= _lastDown ? down - _lastDown : (down < 0 ? 0 : down);
    _lastUp = up;
    _lastDown = down;
    return (du, dd);
  }

  void reset() {
    _lastUp = 0;
    _lastDown = 0;
    _primed = false;
  }
}

/// Connect attempts and successes per day: `{"2026-10-22": [tries, ok]}`.
class MuseConnectStats {
  const MuseConnectStats(this.days);

  final Map<String, (int, int)> days;

  static const empty = MuseConnectStats({});

  static MuseConnectStats parse(String raw) {
    final t = MuseTrafficLog.parse(raw);
    return MuseConnectStats(t.days);
  }

  String toRaw() => MuseTrafficLog(days).toRaw();

  MuseConnectStats record(DateTime day, {required bool ok}) {
    final k = museDayKey(day);
    final cur = days[k] ?? (0, 0);
    final next = {...days, k: (cur.$1 + 1, cur.$2 + (ok ? 1 : 0))};
    final keys = next.keys.toList()..sort();
    for (final old in keys.take(next.length > 60 ? next.length - 60 : 0)) {
      next.remove(old);
    }
    return MuseConnectStats(next);
  }

  /// Success rate over the last [n] days ending [today] (null = no attempts).
  double? rate(DateTime today, {int n = 30}) {
    var tries = 0;
    var ok = 0;
    for (var i = 0; i < n; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      final v = days[museDayKey(d)];
      if (v == null) continue;
      tries += v.$1;
      ok += v.$2;
    }
    return tries == 0 ? null : ok / tries;
  }
}

/// The [n] biggest entries of [bytes] (name → bytes), biggest first.
List<MapEntry<String, int>> museTop(Map<String, int> bytes, {int n = 10}) {
  final l = bytes.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
  return l.take(n).toList();
}

/// The monthly report lines for [month] ('2026-10').
List<String> museMonthlyReport(MuseTrafficLog log, String month, {required String Function(int) bytes}) {
  final ds = log.days.entries.where((e) => e.key.startsWith(month)).toList()..sort((a, b) => a.key.compareTo(b.key));
  if (ds.isEmpty) return ['$month 还没有流量记录'];
  var up = 0;
  var down = 0;
  MapEntry<String, (int, int)>? top;
  for (final e in ds) {
    up += e.value.$1;
    down += e.value.$2;
    if (top == null || e.value.$1 + e.value.$2 > top.value.$1 + top.value.$2) top = e;
  }
  return [
    '$month 共用 ${bytes(up + down)}（↑ ${bytes(up)}  ↓ ${bytes(down)}）',
    '使用 ${ds.length} 天，日均 ${bytes((up + down) ~/ ds.length)}',
    '用得最多：${top!.key.substring(5)}，${bytes(top.value.$1 + top.value.$2)}',
  ];
}

// ---------------------------------------------------------------- crash log

/// One captured error.
class MuseCrash {
  const MuseCrash(this.at, this.message, this.stack);

  final DateTime at;
  final String message;
  final String stack;

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'm': message, 's': stack};

  static MuseCrash? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    return MuseCrash(at, '${j['m'] ?? ''}', '${j['s'] ?? ''}');
  }
}

/// The crash log: the newest [keep] errors (stack traces cut to [stackLines] lines).
List<MuseCrash> museAddCrash(List<MuseCrash> log, MuseCrash c, {int keep = 30, int stackLines = 24}) {
  final cut = MuseCrash(c.at, c.message.length > 2000 ? c.message.substring(0, 2000) : c.message, c.stack.split('\n').take(stackLines).join('\n'));
  final next = [...log, cut];
  return next.length > keep ? next.sublist(next.length - keep) : next;
}

List<MuseCrash> museParseCrashes(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    return [for (final e in jsonDecode(raw) as List) ?MuseCrash.fromJson(e)];
  } catch (_) {
    return const [];
  }
}

String museCrashesToRaw(List<MuseCrash> l) => jsonEncode([for (final c in l) c.toJson()]);
