// 穿云 1.16.0 B7 - 按应用的流量（统计页「按应用」图）。数据只存本机（muse_app_traffic），保留 30 天。
// 不在后台采样、不轮询：只在打开「统计」页（读一次 /connections）和「连接」页开着时（它本来就每秒收一帧）
// 累计各连接的增量，离开连接页时写入一次；连接 / 断开时清空基线。内核报告了发起的应用才计入。
// Part of 穿云 (GPLv3).

import 'dart:convert';

import 'package:hiddify/features/muse/connections/conn_app.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart' show museDayKey;

/// Per day, per app: `{"2026-11-08": {"com.x": [bytes, "显示名"]}}`, the last [keepDays] days.
class MuseAppTrafficLog {
  const MuseAppTrafficLog(this.days);

  final Map<String, Map<String, (int, String)>> days;

  static const keepDays = 30;

  /// At most this many apps a day are kept (the rest are folded into the smallest ones' bytes).
  static const maxAppsPerDay = 200;
  static const empty = MuseAppTrafficLog({});

  static MuseAppTrafficLog parse(String raw) {
    if (raw.trim().isEmpty) return empty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return MuseAppTrafficLog({
        for (final d in m.entries)
          if (d.value is Map)
            d.key: {
              for (final a in (d.value as Map).entries)
                if (a.value is List && (a.value as List).length >= 2 && (a.value as List)[0] is num)
                  '${a.key}': (((a.value as List)[0] as num).toInt(), '${(a.value as List)[1]}'),
            },
      });
    } catch (_) {
      return empty;
    }
  }

  String toRaw() => jsonEncode({
    for (final d in days.entries) d.key: {for (final a in d.value.entries) a.key: [a.value.$1, a.value.$2]},
  });

  /// [bytes] (app id → (bytes, name)) added to [day]; days older than [keepDays] before [day] dropped.
  MuseAppTrafficLog add(DateTime day, Map<String, (int, String)> bytes) {
    final adds = {for (final e in bytes.entries) if (e.value.$1 > 0) e.key: e.value};
    if (adds.isEmpty) return this;
    final k = museDayKey(day);
    final cur = {...?days[k]};
    adds.forEach((id, v) {
      final old = cur[id];
      cur[id] = ((old?.$1 ?? 0) + v.$1, v.$2.isNotEmpty ? v.$2 : (old?.$2 ?? id));
    });
    if (cur.length > maxAppsPerDay) {
      final keep = cur.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
      cur
        ..clear()
        ..addEntries(keep.take(maxAppsPerDay));
    }
    final cutoff = museDayKey(DateTime(day.year, day.month, day.day - (keepDays - 1)));
    final next = {
      for (final e in days.entries)
        if (e.key.compareTo(cutoff) >= 0) e.key: e.value,
      k: cur,
    };
    return MuseAppTrafficLog(next);
  }

  /// The biggest apps over the last [n] days ending [today], biggest first: (id, name, bytes).
  List<(String, String, int)> top(DateTime today, {int n = 1, int count = 10}) {
    final sum = <String, (int, String)>{};
    for (var i = 0; i < n; i++) {
      final d = days[museDayKey(DateTime(today.year, today.month, today.day - i))];
      if (d == null) continue;
      d.forEach((id, v) {
        final old = sum[id];
        sum[id] = ((old?.$1 ?? 0) + v.$1, old?.$2 ?? v.$2);
      });
    }
    final l = sum.entries.where((e) => e.value.$1 > 0).toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    return [for (final e in l.take(count)) (e.key, e.value.$2, e.value.$1)];
  }
}

/// Turns live connections into per-app byte deltas. A connection seen for the first time counts
/// from zero (it started while 穿云 was connected); one that went away is forgotten.
class MuseAppTrafficSampler {
  final _seen = <String, int>{};

  int get tracked => _seen.length;

  /// app id → (new bytes, name) since the last call.
  Map<String, (int, String)> sample(Iterable<MuseConn> conns) {
    final out = <String, (int, String)>{};
    final alive = <String>{};
    for (final c in conns) {
      if (c.end != null) continue;
      alive.add(c.id);
      final total = c.total < 0 ? 0 : c.total;
      final before = _seen[c.id];
      _seen[c.id] = total;
      final delta = before == null ? total : (total >= before ? total - before : total);
      if (delta <= 0) continue;
      final app = museConnApp(c.process, const {});
      if (app == null) continue;
      final old = out[app.id];
      out[app.id] = ((old?.$1 ?? 0) + delta, app.name);
    }
    _seen.removeWhere((id, _) => !alive.contains(id));
    return out;
  }

  void reset() => _seen.clear();
}

/// Adds two delta maps.
Map<String, (int, String)> museMergeAppBytes(Map<String, (int, String)> a, Map<String, (int, String)> b) {
  final out = {...a};
  b.forEach((id, v) {
    final old = out[id];
    out[id] = ((old?.$1 ?? 0) + v.$1, v.$2);
  });
  return out;
}
