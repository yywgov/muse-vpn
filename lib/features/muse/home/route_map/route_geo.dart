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
  // 1.20.1：补齐节点常见、之前没有代表城市的地区（否则有国旗也没有地图取景与高亮）
  'QA': MuseCity('多哈', 'QA', 25.29, 51.53),
  'BH': MuseCity('麦纳麦', 'BH', 26.23, 50.59),
  'KW': MuseCity('科威特城', 'KW', 29.38, 47.98),
  'OM': MuseCity('马斯喀特', 'OM', 23.59, 58.41),
  'JO': MuseCity('安曼', 'JO', 31.95, 35.93),
  'LB': MuseCity('贝鲁特', 'LB', 33.89, 35.50),
  'CY': MuseCity('尼科西亚', 'CY', 35.19, 33.38),
  'IR': MuseCity('德黑兰', 'IR', 35.69, 51.39),
  'IQ': MuseCity('巴格达', 'IQ', 33.32, 44.37),
  'GE': MuseCity('第比利斯', 'GE', 41.72, 44.79),
  'AM': MuseCity('埃里温', 'AM', 40.18, 44.51),
  'AZ': MuseCity('巴库', 'AZ', 40.41, 49.87),
  'UZ': MuseCity('塔什干', 'UZ', 41.30, 69.24),
  'KG': MuseCity('比什凯克', 'KG', 42.87, 74.59),
  'LK': MuseCity('科伦坡', 'LK', 6.93, 79.86),
  'NP': MuseCity('加德满都', 'NP', 27.72, 85.32),
  'MM': MuseCity('仰光', 'MM', 16.87, 96.20),
  'LA': MuseCity('万象', 'LA', 17.97, 102.63),
  'BN': MuseCity('斯里巴加湾', 'BN', 4.94, 114.95),
  'BY': MuseCity('明斯克', 'BY', 53.90, 27.56),
  'MD': MuseCity('基希讷乌', 'MD', 47.01, 28.86),
  'EE': MuseCity('塔林', 'EE', 59.44, 24.75),
  'LV': MuseCity('里加', 'LV', 56.95, 24.11),
  'LT': MuseCity('维尔纽斯', 'LT', 54.69, 25.28),
  'SK': MuseCity('布拉迪斯拉发', 'SK', 48.15, 17.11),
  'SI': MuseCity('卢布尔雅那', 'SI', 46.06, 14.51),
  'HR': MuseCity('萨格勒布', 'HR', 45.81, 15.98),
  'RS': MuseCity('贝尔格莱德', 'RS', 44.79, 20.45),
  'BA': MuseCity('萨拉热窝', 'BA', 43.86, 18.41),
  'ME': MuseCity('波德戈里察', 'ME', 42.44, 19.26),
  'MK': MuseCity('斯科普里', 'MK', 41.99, 21.43),
  'AL': MuseCity('地拉那', 'AL', 41.33, 19.82),
  'GR': MuseCity('雅典', 'GR', 37.98, 23.73),
  'BG': MuseCity('索非亚', 'BG', 42.70, 23.32),
  'MT': MuseCity('瓦莱塔', 'MT', 35.90, 14.51),
  'LI': MuseCity('瓦杜兹', 'LI', 47.14, 9.52),
  'MC': MuseCity('摩纳哥', 'MC', 43.74, 7.42),
  'PA': MuseCity('巴拿马城', 'PA', 8.98, -79.52),
  'CR': MuseCity('圣何塞（哥斯达黎加）', 'CR', 9.93, -84.08),
  'GT': MuseCity('危地马拉城', 'GT', 14.63, -90.51),
  'PE': MuseCity('利马', 'PE', -12.05, -77.04),
  'EC': MuseCity('基多', 'EC', -0.18, -78.47),
  'UY': MuseCity('蒙得维的亚', 'UY', -34.90, -56.16),
  'VE': MuseCity('加拉加斯', 'VE', 10.48, -66.90),
  'KE': MuseCity('内罗毕', 'KE', -1.29, 36.82),
  'MA': MuseCity('卡萨布兰卡', 'MA', 33.57, -7.59),
  'TN': MuseCity('突尼斯', 'TN', 36.81, 10.18),
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
  const MuseMapView(this.north, this.south, [this.center = museMapCenterLon, this.span = 360]);

  /// 1.20.0：中央经线（默认 [museMapCenterLon]）
  final double center;

  /// 1.20.0：宽度方向显示的经度跨度（默认 360°，整圈）
  final double span;

  /// 1.20.0：同一纬度取景、换中央经线
  MuseMapView centered(double c) => MuseMapView(north, south, c, span);

  /// 1.19 的整幅（北 84° 到南 60°）
  static const full = MuseMapView(museMapNorth, museMapSouth);

  final double north;
  final double south;

  @override
  bool operator ==(Object other) => other is MuseMapView && other.north == north && other.south == south && other.center == center && other.span == span;

  @override
  int get hashCode => Object.hash(north, south, center, span);

  @override
  String toString() => 'MuseMapView($north, $south, $center, $span)';
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
  final l = wrap ? museWrapLon(lon, center: view.center) : lon;
  final x = (l - (view.center - view.span / 2)) / view.span * size.width;
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

/// 1.20.1：切节点时终点滑动——经纬度直线插值（经度走近的一侧）。沿大圆弧走时荷兰 → 日本会经过西伯利亚、滑出地图上沿；
/// 直线插值始终在两座城市围成的经纬度框内。
MuseGeoPoint museSlideLerp(MuseGeoPoint a, MuseGeoPoint b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  final bl = museWrapLon(b.lon, center: a.lon);
  return MuseGeoPoint(a.lat + (b.lat - a.lat) * t, a.lon + (bl - a.lon) * t);
}

/// 两城市之间的位置插值：沿大圆弧取 t 处。
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


/// 1.20.0：连接卡的取景——把本机 [home] 与目的地 [targets]（节点所在国家的点阵格中心与整条弧）一起框进 [size]：
/// 经度跨度 = 两者跨度 × 1.3，至少 [minSpan]°、最多 360°；纬度按同一比例尺，内容的最北端放在地图高度 [topShare]
/// 处（上面留给状态文字），内容纬度跨度不超过地图高度的 [fill]。
MuseMapView museFitView(
  Size size,
  MuseGeoPoint home,
  List<MuseGeoPoint> targets, {
  double minSpan = 100,
  double topShare = 0.24,
  double fill = 0.48,
}) {
  if (size.isEmpty || targets.isEmpty) return MuseMapView.full;
  // 经度按「离本机近的那一侧」展开
  double rel(double lon) => museWrapLon(lon, center: home.lon);
  var lo = home.lon;
  var hi = home.lon;
  var south = home.lat;
  var north = home.lat;
  for (final p in targets) {
    final l = rel(p.lon);
    lo = math.min(lo, l);
    hi = math.max(hi, l);
    south = math.min(south, p.lat);
    north = math.max(north, p.lat);
  }
  final aspect = size.height / size.width;
  var span = math.max(minSpan, (hi - lo) * 1.3);
  final needLat = (north - south) / fill;
  span = math.max(span, needLat / aspect).clamp(minSpan, 360.0);
  final latSpan = span * aspect;
  final top = north + topShare * latSpan;
  return MuseMapView(top, top - latSpan, (lo + hi) / 2, span);
}

/// 两个取景之间按 [t]（0–1，已缓动）插值。1.20.1：跨度按对数插值（缩放匀速），中心按「绕不动点缩放」——
/// 两次取景里屏幕位置相同的那一点在整个过渡中都不动，其余点单调地移向终点位置（中心 = a + (b − a) × (s − sa) / (sb − sa)）；
/// 跨度几乎不变时退化为线性平移。纬度方向同理（按纬度跨度）。
MuseMapView museViewLerp(MuseMapView a, MuseMapView b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  final bc = museWrapLon(b.center, center: a.center);
  final span = a.span * math.pow(b.span / a.span, t).toDouble();
  final la = a.north - a.south;
  final lb = b.north - b.south;
  final latSpan = la * math.pow(lb / la, t).toDouble();
  double w(double s, double sa, double sb) => (sb - sa).abs() < 1e-6 * sa ? t : (s - sa) / (sb - sa);
  final wl = w(span, a.span, b.span);
  final wy = w(latSpan, la, lb);
  final center = a.center + (bc - a.center) * wl;
  final north = a.north + (b.north - a.north) * wy;
  return MuseMapView(north, north - latSpan, center, span);
}
