// 穿云 1.3.0 - 首页 dashboard tiles: which tiles exist, their order and which are hidden
// (pure logic, unit-tested). Saved as comma lists in Preferences.museHomeTileOrder / museHomeTilesHidden.
// Part of 穿云 (GPLv3).

enum MuseHomeTile {
  speed('speed', '网速'),
  traffic('traffic', '本次流量'),
  remaining('remaining', '剩余流量'),
  expiry('expiry', '到期'),
  exit('exit', '出口 IP'),
  adBlock('adblock', '去广告');

  const MuseHomeTile(this.key, this.title);

  final String key;
  final String title;

  static MuseHomeTile? fromKey(String key) => values.where((e) => e.key == key.trim()).firstOrNull;
}

/// The saved order, completed: unknown keys and duplicates dropped, tiles missing from the saved
/// list (new in a later version) appended in their default order.
List<MuseHomeTile> museParseTileOrder(String raw) {
  final out = <MuseHomeTile>[];
  for (final part in raw.split(',')) {
    final t = MuseHomeTile.fromKey(part);
    if (t != null && !out.contains(t)) out.add(t);
  }
  for (final t in MuseHomeTile.values) {
    if (!out.contains(t)) out.add(t);
  }
  return out;
}

String museTileOrderToRaw(List<MuseHomeTile> order) => order.map((e) => e.key).join(',');

Set<MuseHomeTile> museParseHiddenTiles(String raw) =>
    {for (final part in raw.split(',')) ?MuseHomeTile.fromKey(part)};

String museHiddenTilesToRaw(Set<MuseHomeTile> hidden) =>
    MuseHomeTile.values.where(hidden.contains).map((e) => e.key).join(',');

/// [tile] moved one place towards the start ([by] = -1) or the end ([by] = 1) of [order].
List<MuseHomeTile> museMoveTile(List<MuseHomeTile> order, MuseHomeTile tile, int by) {
  final list = [...order];
  final from = list.indexOf(tile);
  if (from < 0) return list;
  final to = (from + by).clamp(0, list.length - 1);
  if (to == from) return list;
  list
    ..removeAt(from)
    ..insert(to, tile);
  return list;
}

/// [order] with [tile] moved to [to] (drag and drop).
List<MuseHomeTile> museMoveTileTo(List<MuseHomeTile> order, MuseHomeTile tile, int to) {
  final list = [...order]..remove(tile);
  list.insert(to.clamp(0, list.length), tile);
  return list;
}

Set<MuseHomeTile> museToggleHiddenTile(Set<MuseHomeTile> hidden, MuseHomeTile tile) =>
    hidden.contains(tile) ? ({...hidden}..remove(tile)) : {...hidden, tile};

/// The tiles 首页 shows, in order: not hidden by the user, and with something to show
/// ([hasData] false = e.g. a subscription that reports no traffic cap).
List<MuseHomeTile> museVisibleTiles(
  List<MuseHomeTile> order,
  Set<MuseHomeTile> hidden, {
  required bool Function(MuseHomeTile) hasData,
}) => [for (final t in order) if (!hidden.contains(t) && hasData(t)) t];

/// Grid columns for a content width: 2 on a phone, 3–4 on the desktop.
int museTileColumns(double width) {
  if (width >= 1000) return 4;
  if (width >= 600) return 3;
  return 2;
}

/// 「2.4 MB/s」: one decimal below 100, none above (stable width, no flicker between units).
String museSpeedText(int bytesPerSecond) {
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var v = bytesPerSecond < 0 ? 0.0 : bytesPerSecond.toDouble();
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final n = i == 0 || v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$n ${units[i]}';
}

/// Days left until [expire] (0 on the last day, negative once expired).
int museDaysLeft(DateTime expire, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return expire.difference(at).inHours ~/ 24;
}
