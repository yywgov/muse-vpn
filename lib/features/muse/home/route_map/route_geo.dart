// 穿云 1.19.0 P1 - 首页路由弧线图的地理部分：城市坐标表、出口位置判断、投影、大圆弧、点阵底图解析。
// 纯 Dart（不依赖界面），便于测试。底图数据来自 Natural Earth（公有领域），由
// tool/world_dots/gen_world_dots.py 离线生成 assets/map/world_dots.bin。
// Part of 穿云 (GPLv3).

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:hiddify/features/muse/home/node_label.dart';

/// 地图上的一个位置。
class MuseGeoPoint {
  const MuseGeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) => other is MuseGeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'MuseGeoPoint($lat, $lon)';
}

/// 一座城市：显示名（中文）+ 坐标 + 所在地区代码（ISO 3166 alpha-2）。
class MuseCity {
  const MuseCity(this.name, this.region, this.lat, this.lon);

  final String name;
  final String region;
  final double lat;
  final double lon;

  MuseGeoPoint get point => MuseGeoPoint(lat, lon);
}

/// 出口位置从哪来。
enum MuseExitSource {
  /// 实测：来自出口 IP 检测（地区代码）
  measured('实测'),

  /// 按名称：从节点名推断
  byName('按名称'),

  /// 未知
  unknown('未知');

  const MuseExitSource(this.label);

  final String label;
}

/// 出口位置：城市（未知时为 null）+ 来源。
class MuseExitPlace {
  const MuseExitPlace(this.city, this.source);

  static const unknown = MuseExitPlace(null, MuseExitSource.unknown);

  final MuseCity? city;
  final MuseExitSource source;

  bool get known => city != null;

  @override
  bool operator ==(Object other) => other is MuseExitPlace && other.source == source && other.city?.name == city?.name;

  @override
  int get hashCode => Object.hash(source, city?.name);
}

/// 本机位置：固定为中国大陆（上海）。不读系统定位、不联网；系统时区只给出时差，不足以定位城市，
/// 所以不用它推断。
const museHomeCity = MuseCity('上海', 'CN', 31.23, 121.47);

/// 地区代码 → 代表城市（机房常见城市）。未收录返回 null。
const museRegionCities = <String, MuseCity>{
  'CN': MuseCity('上海', 'CN', 31.23, 121.47),
  'HK': MuseCity('香港', 'HK', 22.32, 114.17),
  'MO': MuseCity('澳门', 'MO', 22.20, 113.55),
  'TW': MuseCity('台北', 'TW', 25.03, 121.57),
  'JP': MuseCity('东京', 'JP', 35.68, 139.69),
  'KR': MuseCity('首尔', 'KR', 37.57, 126.98),
  'SG': MuseCity('新加坡', 'SG', 1.35, 103.82),
  'MY': MuseCity('吉隆坡', 'MY', 3.14, 101.69),
  'TH': MuseCity('曼谷', 'TH', 13.76, 100.50),
  'VN': MuseCity('胡志明市', 'VN', 10.82, 106.63),
  'PH': MuseCity('马尼拉', 'PH', 14.60, 120.98),
  'ID': MuseCity('雅加达', 'ID', -6.21, 106.85),
  'KH': MuseCity('金边', 'KH', 11.56, 104.92),
  'MN': MuseCity('乌兰巴托', 'MN', 47.89, 106.91),
  'IN': MuseCity('孟买', 'IN', 19.08, 72.88),
  'PK': MuseCity('卡拉奇', 'PK', 24.86, 67.01),
  'BD': MuseCity('达卡', 'BD', 23.81, 90.41),
  'KZ': MuseCity('阿拉木图', 'KZ', 43.24, 76.89),
  'AE': MuseCity('迪拜', 'AE', 25.20, 55.27),
  'SA': MuseCity('利雅得', 'SA', 24.71, 46.68),
  'IL': MuseCity('特拉维夫', 'IL', 32.09, 34.78),
  'TR': MuseCity('伊斯坦布尔', 'TR', 41.01, 28.98),
  'RU': MuseCity('莫斯科', 'RU', 55.76, 37.62),
  'UA': MuseCity('基辅', 'UA', 50.45, 30.52),
  'GB': MuseCity('伦敦', 'GB', 51.51, -0.13),
  'IE': MuseCity('都柏林', 'IE', 53.35, -6.26),
  'FR': MuseCity('巴黎', 'FR', 48.86, 2.35),
  'DE': MuseCity('法兰克福', 'DE', 50.11, 8.68),
  'NL': MuseCity('阿姆斯特丹', 'NL', 52.37, 4.90),
  'BE': MuseCity('布鲁塞尔', 'BE', 50.85, 4.35),
  'LU': MuseCity('卢森堡', 'LU', 49.61, 6.13),
  'CH': MuseCity('苏黎世', 'CH', 47.38, 8.54),
  'AT': MuseCity('维也纳', 'AT', 48.21, 16.37),
  'IT': MuseCity('米兰', 'IT', 45.46, 9.19),
  'ES': MuseCity('马德里', 'ES', 40.42, -3.70),
  'PT': MuseCity('里斯本', 'PT', 38.72, -9.14),
  'SE': MuseCity('斯德哥尔摩', 'SE', 59.33, 18.07),
  'NO': MuseCity('奥斯陆', 'NO', 59.91, 10.75),
  'FI': MuseCity('赫尔辛基', 'FI', 60.17, 24.94),
  'DK': MuseCity('哥本哈根', 'DK', 55.68, 12.57),
  'PL': MuseCity('华沙', 'PL', 52.23, 21.01),
  'CZ': MuseCity('布拉格', 'CZ', 50.08, 14.44),
  'HU': MuseCity('布达佩斯', 'HU', 47.50, 19.04),
  'RO': MuseCity('布加勒斯特', 'RO', 44.43, 26.10),
  'IS': MuseCity('雷克雅未克', 'IS', 64.15, -21.94),
  'US': MuseCity('洛杉矶', 'US', 34.05, -118.24),
  'CA': MuseCity('多伦多', 'CA', 43.65, -79.38),
  'MX': MuseCity('墨西哥城', 'MX', 19.43, -99.13),
  'BR': MuseCity('圣保罗', 'BR', -23.55, -46.63),
  'AR': MuseCity('布宜诺斯艾利斯', 'AR', -34.60, -58.38),
  'CL': MuseCity('圣地亚哥', 'CL', -33.45, -70.67),
  'CO': MuseCity('波哥大', 'CO', 4.71, -74.07),
  'AU': MuseCity('悉尼', 'AU', -33.87, 151.21),
  'NZ': MuseCity('奥克兰', 'NZ', -36.85, 174.76),
  'ZA': MuseCity('约翰内斯堡', 'ZA', -26.20, 28.05),
  'EG': MuseCity('开罗', 'EG', 30.04, 31.24),
  'NG': MuseCity('拉各斯', 'NG', 6.52, 3.38),
};

/// 节点名里的城市关键词 → 城市（比地区代表城市更准）。
final _cityKeywords = <(RegExp, MuseCity)>[
  (RegExp('东京|Tokyo', caseSensitive: false), const MuseCity('东京', 'JP', 35.68, 139.69)),
  (RegExp('大阪|Osaka', caseSensitive: false), const MuseCity('大阪', 'JP', 34.69, 135.50)),
  (RegExp('春川|Chuncheon', caseSensitive: false), const MuseCity('春川', 'KR', 37.88, 127.73)),
  (RegExp('首尔|Seoul', caseSensitive: false), const MuseCity('首尔', 'KR', 37.57, 126.98)),
  (RegExp(r'洛杉矶|Los ?Angeles|\bLAX\b', caseSensitive: false), const MuseCity('洛杉矶', 'US', 34.05, -118.24)),
  (
    RegExp(r'圣何塞|San ?Jose|\bSJC\b|硅谷|Silicon ?Valley', caseSensitive: false),
    const MuseCity('圣何塞', 'US', 37.34, -121.89),
  ),
  (RegExp(r'旧金山|San ?Francisco|\bSFO\b', caseSensitive: false), const MuseCity('旧金山', 'US', 37.77, -122.42)),
  (RegExp('西雅图|Seattle', caseSensitive: false), const MuseCity('西雅图', 'US', 47.61, -122.33)),
  (RegExp('凤凰城|Phoenix', caseSensitive: false), const MuseCity('凤凰城', 'US', 33.45, -112.07)),
  (RegExp('达拉斯|Dallas', caseSensitive: false), const MuseCity('达拉斯', 'US', 32.78, -96.80)),
  (RegExp('芝加哥|Chicago', caseSensitive: false), const MuseCity('芝加哥', 'US', 41.88, -87.63)),
  (RegExp(r'纽约|New ?York|\bNYC\b', caseSensitive: false), const MuseCity('纽约', 'US', 40.71, -74.01)),
  (RegExp('阿什本|Ashburn|弗吉尼亚|Virginia', caseSensitive: false), const MuseCity('阿什本', 'US', 39.04, -77.49)),
  (RegExp('迈阿密|Miami', caseSensitive: false), const MuseCity('迈阿密', 'US', 25.76, -80.19)),
  (RegExp('温哥华|Vancouver', caseSensitive: false), const MuseCity('温哥华', 'CA', 49.28, -123.12)),
  (RegExp('多伦多|Toronto', caseSensitive: false), const MuseCity('多伦多', 'CA', 43.65, -79.38)),
  (RegExp('伦敦|London', caseSensitive: false), const MuseCity('伦敦', 'GB', 51.51, -0.13)),
  (RegExp('法兰克福|Frankfurt', caseSensitive: false), const MuseCity('法兰克福', 'DE', 50.11, 8.68)),
  (RegExp('柏林|Berlin', caseSensitive: false), const MuseCity('柏林', 'DE', 52.52, 13.40)),
  (RegExp('悉尼|Sydney', caseSensitive: false), const MuseCity('悉尼', 'AU', -33.87, 151.21)),
  (RegExp('墨尔本|Melbourne', caseSensitive: false), const MuseCity('墨尔本', 'AU', -37.81, 144.96)),
  (RegExp('台中|Taichung', caseSensitive: false), const MuseCity('台中', 'TW', 24.15, 120.67)),
  (RegExp('新北|New ?Taipei', caseSensitive: false), const MuseCity('新北', 'TW', 25.01, 121.47)),
];

/// 地区代码的代表城市；未收录返回 null。
MuseCity? museCityForRegion(String? code) => code == null ? null : museRegionCities[code.trim().toUpperCase()];

/// 节点名里能认出的城市（先城市关键词，再地区代表城市）；认不出返回 null。
MuseCity? museCityForNodeName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  for (final (re, city) in _cityKeywords) {
    if (re.hasMatch(name)) return city;
  }
  return museCityForRegion(museRegionCode(name));
}

/// 出口位置：有实测地区代码时以实测为准（节点名里的城市若在同一地区则用更准的城市），否则按节点名，
/// 都没有则未知。
MuseExitPlace museResolveExitPlace({String? nodeName, String? measuredRegion}) {
  final named = museCityForNodeName(nodeName);
  final m = measuredRegion?.trim().toUpperCase() ?? '';
  if (m.isNotEmpty) {
    if (named != null && named.region == m) return MuseExitPlace(named, MuseExitSource.measured);
    final c = museCityForRegion(m);
    if (c != null) return MuseExitPlace(c, MuseExitSource.measured);
  }
  if (named != null) return MuseExitPlace(named, MuseExitSource.byName);
  return MuseExitPlace.unknown;
}

/// 地图视窗：等距圆柱投影，中央经线 [museMapCenterLon]（东经 110°，让中国居中、太平洋航线不被切断），
/// 纬度范围与底图一致（北 84° 到南 60°）。
const museMapCenterLon = 110.0;
const museMapNorth = 84.0;
const museMapSouth = -60.0;

/// 把经度换算到以中央经线为中心的连续区间 [center-180, center+180)。
double museWrapLon(double lon, {double center = museMapCenterLon}) {
  var x = (lon - (center - 180)) % 360;
  if (x < 0) x += 360;
  return x + center - 180;
}

/// 1.19.2 地图取景：经度始终 360° 铺满宽度，纬度只取 [north]–[south] 这一段。
class MuseMapView {
  const MuseMapView(this.north, this.south);

  /// 1.19 的整幅（北 84° 到南 60°）
  static const full = MuseMapView(museMapNorth, museMapSouth);

  final double north;
  final double south;

  @override
  bool operator ==(Object other) => other is MuseMapView && other.north == north && other.south == south;

  @override
  int get hashCode => Object.hash(north, south);

  @override
  String toString() => 'MuseMapView($north, $south)';
}

/// 取景时纬度跨度的下限（北纬 ~62° 到南纬 ~38°：伦敦、莫斯科、悉尼、圣保罗、开普敦都在内）与中心纬度。
const museMapMinLatSpan = 100.0;
const museMapCenterLat = 12.0;

/// 1.19.2：[size] 这么大的地图取哪一段纬度——宽高比不比整幅（360:144 = 2.5）扁时整幅不变（手机 2.2 与 1.19 完全一样，
/// 只是纵向略拉伸）；更扁时按宽度等比、上下裁掉（中心北纬 12°），最多裁到 [museMapMinLatSpan]。
MuseMapView museMapView(Size size) {
  if (size.width <= 0 || size.height <= 0) return MuseMapView.full;
  final span = (360 * size.height / size.width).clamp(museMapMinLatSpan, museMapNorth - museMapSouth);
  if (span >= museMapNorth - museMapSouth) return MuseMapView.full;
  return MuseMapView(museMapCenterLat + span / 2, museMapCenterLat - span / 2);
}

/// 经纬度 → 画布坐标。[lon] 不再取模（大圆弧采样已展开成连续经度时用 [wrap] = false）。
/// 1.19.2：[view] 是纬度取景（默认整幅）。
Offset museProject(double lat, double lon, Size size, {bool wrap = true, MuseMapView view = MuseMapView.full}) {
  final l = wrap ? museWrapLon(lon) : lon;
  final x = (l - (museMapCenterLon - 180)) / 360 * size.width;
  final y = (view.north - lat) / (view.north - view.south) * size.height;
  return Offset(x, y);
}

/// 1.19.2 地图上一段文字（城市名）放在哪：点 [dot] 的 [before]（左）或右侧、[above]（上）或与点平齐，
/// 但永远整块落在 [map] 里——靠右边缘放不下就翻到左边，靠左边缘就翻到右边，靠上边缘就放到点下方，
/// 最后再夹进地图（窄到放不下时贴边）。返回文字左上角。
Offset museLabelOffset(Offset dot, Size label, Size map, {required bool before, required bool above, double gap = 6}) {
  double xFor(bool b) => b ? dot.dx - gap - label.width : dot.dx + gap;
  var x = xFor(before);
  if (x < 0 || x + label.width > map.width) {
    final flipped = xFor(!before);
    if (flipped >= 0 && flipped + label.width <= map.width) x = flipped;
  }
  var y = above ? dot.dy - gap / 2 - label.height : dot.dy - gap;
  if (y < 0) y = dot.dy + gap / 2;
  if (y + label.height > map.height) y = dot.dy - gap / 2 - label.height;
  final maxX = math.max(0.0, map.width - label.width);
  final maxY = math.max(0.0, map.height - label.height);
  return Offset(x.clamp(0.0, maxX), y.clamp(0.0, maxY));
}

/// 两点间大圆弧上的 [n]+1 个采样点（经度连续展开，起点经度落在视窗内）。
List<MuseGeoPoint> museGreatCircle(MuseGeoPoint a, MuseGeoPoint b, {int n = 64}) {
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  List<double> vec(MuseGeoPoint p) {
    final la = rad(p.lat);
    final lo = rad(p.lon);
    return [math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)];
  }

  final va = vec(a);
  final vb = vec(b);
  final dot = (va[0] * vb[0] + va[1] * vb[1] + va[2] * vb[2]).clamp(-1.0, 1.0);
  final omega = math.acos(dot);
  final out = <MuseGeoPoint>[];
  double? prevLon;
  for (var i = 0; i <= n; i++) {
    final t = i / n;
    List<double> v;
    if (omega < 1e-9) {
      v = va;
    } else {
      final s = math.sin(omega);
      final ka = math.sin((1 - t) * omega) / s;
      final kb = math.sin(t * omega) / s;
      v = [ka * va[0] + kb * vb[0], ka * va[1] + kb * vb[1], ka * va[2] + kb * vb[2]];
    }
    final lat = deg(math.atan2(v[2], math.sqrt(v[0] * v[0] + v[1] * v[1])));
    var lon = deg(math.atan2(v[1], v[0]));
    if (prevLon == null) {
      lon = museWrapLon(lon);
    } else {
      while (lon - prevLon > 180) {
        lon -= 360;
      }
      while (lon - prevLon < -180) {
        lon += 360;
      }
    }
    prevLon = lon;
    out.add(MuseGeoPoint(lat, lon));
  }
  return out;
}

/// 两城市之间的位置插值（切节点时终点滑动用）：沿大圆弧取 t 处。
MuseGeoPoint museGeoLerp(MuseGeoPoint a, MuseGeoPoint b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  final pts = museGreatCircle(a, b, n: 32);
  final f = t * 32;
  final i = f.floor().clamp(0, 31);
  final k = f - i;
  final p = pts[i];
  final q = pts[i + 1];
  return MuseGeoPoint(p.lat + (q.lat - p.lat) * k, p.lon + (q.lon - p.lon) * k);
}

/// 点阵底图（assets/map/world_dots.bin，格式见 tool/world_dots/gen_world_dots.py）。
class MuseWorldDots {
  MuseWorldDots._(this.width, this.height, this.step, this.north, this.south, this._bits);

  final int width;
  final int height;

  /// 格距（度）
  final double step;
  final int north;
  final int south;
  final Uint8List _bits;

  /// 解析；格式不对返回 null。
  static MuseWorldDots? parse(Uint8List b) {
    if (b.length < 12 || String.fromCharCodes(b.sublist(0, 4)) != 'CYWD' || b[4] != 1) return null;
    final bd = ByteData.sublistView(b);
    final w = bd.getUint16(5, Endian.little);
    final h = bd.getUint16(7, Endian.little);
    final step = b[9] / 10;
    final north = bd.getInt8(10);
    final south = bd.getInt8(11);
    final bits = Uint8List.sublistView(b, 12);
    if (w == 0 || h == 0 || bits.length < (w * h + 7) ~/ 8) return null;
    return MuseWorldDots._(w, h, step, north, south, bits);
  }

  bool isLand(int row, int col) {
    final k = row * width + col;
    return (_bits[k >> 3] >> (k & 7)) & 1 == 1;
  }

  int get landCount {
    var n = 0;
    for (var r = 0; r < height; r++) {
      for (var c = 0; c < width; c++) {
        if (isLand(r, c)) n++;
      }
    }
    return n;
  }

  /// 第 (row, col) 格中心的经纬度。
  MuseGeoPoint cellCenter(int row, int col) => MuseGeoPoint(north - (row + 0.5) * step, -180 + (col + 0.5) * step);
}
