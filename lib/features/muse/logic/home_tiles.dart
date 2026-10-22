// 穿云 1.3.0 - 首页 dashboard tiles: which tiles exist, their order and which are hidden
// (pure logic, unit-tested). Saved as comma lists in Preferences.museHomeTileOrder / museHomeTilesHidden.
// Part of 穿云 (GPLv3).

enum MuseHomeTile {
  speed('speed', '网速'),
  traffic('traffic', '本次流量'),
  remaining('remaining', '剩余流量'),
  expiry('expiry', '到期'),
  exit('exit', '出口 IP'),
  adBlock('adblock', '去广告'),
  // 穿云 1.4.0 (Windows only): 网速 + 本次流量 in one tile
  flow('flow', '流量');

  const MuseHomeTile(this.key, this.title);

  final String key;
  final String title;

  static MuseHomeTile? fromKey(String key) => values.where((e) => e.key == key.trim()).firstOrNull;
}

/// The tiles that are saved / edited (流量 is derived on Windows from 网速 + 本次流量).
final museStoredTiles = [for (final t in MuseHomeTile.values) if (t != MuseHomeTile.flow) t];

/// The saved order, completed: unknown keys and duplicates dropped, tiles missing from the saved
/// list (new in a later version) appended in their default order.
List<MuseHomeTile> museParseTileOrder(String raw) {
  final out = <MuseHomeTile>[];
  for (final part in raw.split(',')) {
    final t = MuseHomeTile.fromKey(part);
    if (t != null && !out.contains(t)) out.add(t);
  }
  for (final t in MuseHomeTile.values) {
    if (t == MuseHomeTile.flow) continue; // derived, never stored
    if (!out.contains(t)) out.add(t);
  }
  out.remove(MuseHomeTile.flow);
  return out;
}

String museTileOrderToRaw(List<MuseHomeTile> order) => order.map((e) => e.key).join(',');

Set<MuseHomeTile> museParseHiddenTiles(String raw) =>
    {for (final part in raw.split(',')) ?MuseHomeTile.fromKey(part)}..remove(MuseHomeTile.flow);

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

/// 1.4.0 (Windows): 网速 and 本次流量 become one 「流量」 tile where the first of them was.
List<MuseHomeTile> museMergeFlowTiles(List<MuseHomeTile> tiles) {
  final i = tiles.indexWhere((t) => t == MuseHomeTile.speed || t == MuseHomeTile.traffic);
  if (i < 0) return tiles;
  final out = [for (final t in tiles) if (t != MuseHomeTile.speed && t != MuseHomeTile.traffic) t];
  out.insert(i.clamp(0, out.length), MuseHomeTile.flow);
  return out;
}

/// 1.4.0: columns for [count] tiles at [width] so no row is left with a lone tile: the widest
/// column count that divides the tiles evenly, else the one that fills the last row best
/// (the last row's tiles then stretch to the full width).
int museTileColumnsFor(double width, int count) {
  final max = museTileColumns(width);
  if (count <= 0) return max;
  if (count <= max) return count == 1 ? max.clamp(1, 2) : count;
  var best = 2;
  var bestScore = -1.0;
  for (var c = max; c >= 2; c--) {
    final rest = count % c;
    // an even split scores best, then the fullest last row; wider wins a tie
    final score = rest == 0 ? 2.0 : rest / c;
    if (score > bestScore) {
      best = c;
      bestScore = score;
    }
  }
  return best;
}

/// Rows of tile indexes for [count] tiles in [columns] columns (the last row may be shorter;
/// its tiles stretch).
List<List<int>> museTileRows(int count, int columns) {
  final rows = <List<int>>[];
  for (var i = 0; i < count; i += columns) {
    rows.add([for (var j = i; j < count && j < i + columns; j++) j]);
  }
  return rows;
}

/// 「2.4 MB/s」: KB/s at least (1.4.0: never 「110 B/s」), one decimal below 100, none above
/// (stable width, no flicker between units).
String museSpeedText(int bytesPerSecond) {
  const units = ['KB/s', 'MB/s', 'GB/s'];
  var v = bytesPerSecond <= 0 ? 0.0 : bytesPerSecond / 1024;
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  if (v == 0) return '0 KB/s';
  final n = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$n ${units[i]}';
}

/// Days left until [expire] (0 on the last day, negative once expired).
int museDaysLeft(DateTime expire, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return expire.difference(at).inHours ~/ 24;
}
