// 穿云 1.19.0 P1 - 首页「路由弧线图」：点阵世界底图 + 本机到出口城市的大圆弧。
// 连接成功时弧线 1100ms 画出，光点沿弧跑 1 趟后停（1.19.1 起，原 2 趟）；切节点终点 450ms 滑到新城市（原 700ms）。
// 分类线与终点在弧线最后 15% 淡入（1.19.1）。
// 动效档位：标准=完整；精简=弧线直接淡入、无光点；关闭=静态。所有动画一次性，结束后不再出帧；
// 页面不可见（TickerMode 关）时 Ticker 静音即停；无循环、无轮询。底图只在尺寸/颜色变化时预渲染一次成 ui.Image。
// 1.19.2：地图铺满卡片宽度（按宽高比裁纬度取景）；终点名与弧线同一坐标、夹在地图内靠边翻转；已连接时起点、终点、
// 弧线用「已连接色」（主色，对比度不足时向前景色调到 ≥ 3:1），未连接 / 连接中起点为中性色，颜色切换一次性 200ms。
// 1.20.0（首页方向 A）：地图做连接卡的底——未连接整幅世界、全灰、无弧线；已连接按本机 + 节点所在国家自动取景，
// 只把节点所在国家的点阵换成已连接色（略放大），换节点 / 连上 / 断开时取景一次性平移缩放 280ms（关闭档直接到位）。
// 国家归属查 route_countries.dart（Natural Earth 1:110m，公有领域），香港、新加坡这类底图上没有独立国土的地区
// 改为高亮出口城市附近的陆地点。
// 1.20.1：高亮永不抽稀、终点底色圈画在高亮下层、小国按 Natural Earth 1:50m 真实轮廓取点并保证屏幕上最小高亮面积；
// 过渡期间新旧两档点阵交叉淡化（不再整幅密度跳变）；取景 / 高亮 / 终点滑动统一 300ms、同一条对称缓动，中心与缩放
// 按「绕不动点缩放」协同；断开时弧线随取景淡出；首页不在前台（TickerMode 关）时状态变化直接到位，回来首帧即新状态。
// 只借鉴公开思路，不含任何第三方代码或素材。
// Part of 穿云 (GPLv3).

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/muse/home/route_map/route_countries.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/home/route_map/route_share.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';

/// 弧线图动效时长。
abstract final class MuseRouteMotion {
  /// 弧线画出
  static const draw = Duration(milliseconds: 1100);

  /// 光点每跑一趟
  static const lap = Duration(milliseconds: 900);

  /// 光点趟数（之后停）。1.19.1：2 → 1（连接后动效总长约 2.9s → 2.0s）
  static const laps = 1;

  /// 1.20.1：终点滑动、取景、国家高亮共用的时长（三者同步；1.19.1 起终点滑动为 450ms，取景 280、高亮 250）
  static const sync = Duration(milliseconds: 300);

  /// 1.20.1：上面三者共用的对称缓动（原用的 MuseMotion.curve 前 20% 时间走完 57%，取景看起来先跳后动）
  static const curve = MuseEaseInOutCubic();

  /// 切节点时终点滑动（1.19.1：700 → 450ms；1.20.1：与取景同步 300ms）
  static const slide = sync;

  /// 分类线与终点在弧线最后这段（按时间）淡入，不在画完那一帧跳出（1.19.1）
  static const tailFade = 0.15;

  /// 1.20.0：节点所在国家的高亮淡入 / 淡出（一次性；1.20.1 与取景同步）
  static const highlight = sync;

  /// 1.20.0：取景（平移 + 缩放）过渡，≤ 300ms（1.20.1：300ms，与终点、高亮同步）
  static const view = sync;
}

/// 1.20.1：对称的 easeInOutCubic（4t³ / 1 − (−2t + 2)³ / 2）。Flutter 的 Curves.easeInOutCubic 是一条近似的
/// 三次贝塞尔、并不严格对称，这里用精确式，取景的加速段与减速段一样长。
class MuseEaseInOutCubic extends Curve {
  const MuseEaseInOutCubic();

  @override
  double transformInternal(double t) => t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

/// 分类线与终点的透明度：弧线时间进度 [arcV] 的最后 [MuseRouteMotion.tailFade] 线性从 0 到 1。
double museRouteTailAlpha(double arcV) {
  const start = 1 - MuseRouteMotion.tailFade;
  return ((arcV - start) / MuseRouteMotion.tailFade).clamp(0.0, 1.0);
}

const museWorldDotsAsset = 'assets/map/world_dots.bin';

Future<MuseWorldDots?>? _dotsFuture;

/// 1.20.0: the dots once read — a map built later (back to 首页, a rebuilt card) draws them on its
/// first frame instead of waiting a frame for the future.
MuseWorldDots? _dotsLoaded;

/// 读一次底图点阵（进程内缓存）。
Future<MuseWorldDots?> museLoadWorldDots([AssetBundle? bundle]) => _dotsFuture ??= () async {
  try {
    final data = await (bundle ?? rootBundle).load(museWorldDotsAsset);
    return _dotsLoaded = MuseWorldDots.parse(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } catch (_) {
    return null;
  }
}();

/// 预渲染的底图（最多留 3 张：1.20.0 起取景随节点变化，留住前后两个取景）。
final _imageCache = <String, ui.Image>{};

/// 把点阵画成一张图（同尺寸、同颜色只画一次）。测试可读 [museDotImageRenders] 确认没有重复渲染。
/// 1.20.0：[share] 是点半径占格距的比例（连接卡用更细的 [MuseHomeA.dotShare]）。
ui.Image museDotMapImage(
  MuseWorldDots dots,
  Size size,
  double dpr,
  Color color, {
  MuseMapView? view,
  double share = MuseDesk.dotRadiusShare,
}) {
  final v = view ?? museMapView(size);
  final w = (size.width * dpr).round().clamp(1, 4096);
  final h = (size.height * dpr).round().clamp(1, 4096);
  final key = '${identityHashCode(dots)}:$w:$h:${color.toARGB32()}:${v.north}:${v.south}:${v.center}:${v.span}:$share';
  final hit = _imageCache[key];
  if (hit != null) return hit;
  museDotImageRenders++;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final paint = Paint()..color = color;
  final px = Size(w.toDouble(), h.toDouble());
  // 1.19.1 A2: the dot size in logical pixels (at least [MuseDesk.dotMinRadius]), then × dpr — it
  // was clamped in physical pixels, so a 1.0 dpr window got ~1 px dots
  final dprX = w / math.max(size.width, 1);
  final cell = size.width / v.span * dots.step;
  // a small map keeps every k-th dot instead of letting the minimum size run them together
  final k = museDotStride(cell, share);
  final r = museDotRadius(cell, k, share) * dprX;
  for (var row = 0; row < dots.height; row += k) {
    for (var col = 0; col < dots.width; col += k) {
      if (!dots.isLand(row, col)) continue;
      final p = dots.cellCenter(row, col);
      if (p.lat > v.north || p.lat < v.south) continue;
      final o = museProject(p.lat, p.lon, px, view: v);
      if (o.dx < -r || o.dx > px.width + r) continue;
      canvas.drawCircle(o, r, paint);
    }
  }
  final img = rec.endRecording().toImageSync(w, h);
  if (_imageCache.length >= 3) _imageCache.remove(_imageCache.keys.first);
  _imageCache[key] = img;
  return img;
}

int museDotImageRenders = 0;

/// 1.19.1 A2: every how-many-th dot to draw for a grid [cell] logical pixels apart, so that a dot
/// of [MuseDesk.dotMinRadius] still has room around it (1 = all of them).
int museDotStride(double cell, [double share = MuseDesk.dotRadiusShare]) {
  var k = 1;
  final min = museDotMinRadius(share);
  while (k < 8 && cell * k * share < min) {
    k++;
  }
  return k;
}

/// 1.20.0：点半径下限——细点（[share] 小于默认）可以小到 [MuseHomeA.dotMinRadius]。
double museDotMinRadius(double share) => share < MuseDesk.dotRadiusShare ? MuseHomeA.dotMinRadius : MuseDesk.dotMinRadius;

/// 一个点的半径（逻辑像素）：格距 [cell] × 抽稀 [k] × [share]，夹在上下限之间。
double museDotRadius(double cell, int k, double share) =>
    (cell * k * share).clamp(museDotMinRadius(share), MuseDesk.dotMaxRadius);

/// 首页路由弧线图。
class MuseRouteMap extends StatefulWidget {
  const MuseRouteMap({
    super.key,
    required this.connected,
    required this.exit,
    this.home = museHomeCity,
    this.dots,
    this.aspectRatio = 2.2,
    this.connecting = false,
    this.shares = const [],
    this.maxHeight,
    this.delayMs,
    this.height,
    this.showCaption = true,
    this.showLabels = true,
    this.dotColor,
    this.surface,
    this.labelColor,
    this.baseMask,
    this.centerLon,
    this.fit = false,
    this.highlightRegion,
    this.look,
  });

  /// 1.20.0：连接卡上的细节取值（点、弧线、端点、本机名）；null = 1.19 路由卡原样
  final MuseMapLook? look;

  /// 1.20.0：中央经线（null = [museMapCenterLon]，东经 110°）
  final double? centerLon;

  /// 1.20.0：已连接时按本机 + 节点所在国家取景（[museFitView]）；国家未知 / 未连接时用 [centerLon] 的整幅世界
  final bool fit;

  /// 1.20.0：已连接时高亮的国家（ISO 3166-1 alpha-2，点阵按 route_countries.dart 查表）；null = 不高亮
  final String? highlightRegion;

  /// 1.20.0：只作用于底图点阵的透明度渐变（弧线、端点、本机名不受影响）
  final Gradient? baseMask;

  /// 1.20.0：固定高度（null = 按宽高比，1.19 路由卡）
  final double? height;

  /// 1.20.0：是否显示地图下方的说明行（连接卡上不显示：节点行已写着节点与延迟）
  final bool showCaption;

  /// 是否显示城市名
  final bool showLabels;

  /// 1.20.0：底图点阵颜色（null = [museDotColor]）
  final Color? dotColor;

  /// 1.20.0：地图所在的底色（城市名描边、已连接色对比度按它算；null = 外层卡片色）
  final Color? surface;

  /// 1.20.0：本机名颜色（null = onSurface）
  final Color? labelColor;

  /// 1.19.1 A1: the map's height cap (null = as wide as it is, the phone)
  final double? maxHeight;

  /// 1.19.1 A3: the current node's delay, shown in the caption (null / ≤ 0 = none)
  final int? delayMs;

  /// 连接中（未连接时说明文字显示「连接中…」）
  final bool connecting;

  /// 1.19.0 分类线：各类占全部流量的比例；为空时只画主弧线
  final List<(MuseRouteKind, double)> shares;

  /// 是否已连接（未连接只显示底图与本机）
  final bool connected;

  /// 出口位置（未知时不画弧线，显示「出口位置未知」）
  final MuseExitPlace exit;

  /// 本机位置（默认固定中国大陆·上海）
  final MuseCity home;

  /// 底图点阵；为 null 时从 [museWorldDotsAsset] 读
  final MuseWorldDots? dots;

  final double aspectRatio;

  @override
  State<MuseRouteMap> createState() => MuseRouteMapState();
}

class MuseRouteMapState extends State<MuseRouteMap> with TickerProviderStateMixin {
  late final AnimationController _arc = AnimationController(vsync: this, duration: MuseRouteMotion.draw);
  late final AnimationController _dot = AnimationController(
    vsync: this,
    duration: MuseRouteMotion.lap * MuseRouteMotion.laps,
  );
  late final AnimationController _slide = AnimationController(vsync: this, duration: MuseRouteMotion.slide);

  /// 1.20.1 M5：断开时弧线随取景一起淡出（原来一下子消失）；淡完再清零
  late final AnimationController _out = AnimationController(vsync: this, duration: MuseRouteMotion.sync);

  /// 1.19.2：中性色 (0) ↔ 已连接色 (1)，连接状态变化时一次性过渡
  late final AnimationController _tint = AnimationController(
    vsync: this,
    duration: MuseMotion.fast,
    value: widget.connected ? 1 : 0,
  );

  /// 1.20.0：国家高亮的一次性过渡（[_hlFrom] 淡出、[_hlTo] 淡入）
  late final AnimationController _hl = AnimationController(vsync: this, duration: MuseRouteMotion.highlight, value: 1);

  /// 1.20.0：取景过渡（[_viewFrom] → [_viewTo]，一次性平移 + 缩放）；[_viewSize] 是上次排版的地图尺寸
  late final AnimationController _view = AnimationController(vsync: this, duration: MuseRouteMotion.view, value: 1);
  MuseMapView? _viewFrom;
  MuseMapView? _viewTo;
  Size? _viewSize;

  /// 测试用：当前（过渡中为插值后的）取景。
  MuseMapView? get view => _viewNow();

  MuseMapView? _viewNow() {
    final a = _viewFrom;
    final b = _viewTo;
    if (a == null || b == null || _view.value >= 1) return b;
    return museViewLerp(a, b, MuseRouteMotion.curve.transform(_view.value));
  }

  /// 1.20.1：过渡起止两个取景的底图抽稀档位（交叉淡化用；静止时两者相等）
  int? _kFrom;
  int? _kTo;

  /// 1.20.1：状态变化是否直接到位——关闭档，或首页不在前台（TickerMode 关：Ticker 静音，动画会停在第 0 帧，
  /// 回到首页的第一帧还是旧画面、下一帧才跳到新画面）。
  bool get _instant => _level == MuseMotionLevel.off || !TickerMode.valuesOf(context).enabled;

  int _strideFor(MuseMapView v, Size size) =>
      _dots == null ? 1 : museDotStride(size.width / v.span * _dots!.step, widget.look?.dotShare ?? MuseDesk.dotRadiusShare);

  /// [size] 下该用的取景：未连接 / 不取景 = [centerLon] 的整幅世界；已连接 = 本机 + 节点所在国家 + 整条弧。
  MuseMapView _targetView(Size size) {
    final v0 = museMapView(size);
    final base = widget.centerLon == null ? v0 : v0.centered(widget.centerLon!);
    final dots = _dots;
    final region = widget.highlightRegion;
    if (!widget.fit || dots == null || !widget.connected || region == null || size.isEmpty) return base;
    final city = widget.exit.city?.point;
    final pts = [
      ...museRegionPoints(dots, region, near: museCityForRegion(region)?.point ?? city),
      // 弧线也要整条在框内（去欧洲的大圆弧会先往北拱）
      if (city != null) ...museGreatCircle(widget.home.point, city, n: 24),
    ];
    if (pts.isEmpty) return base;
    final look = widget.look ?? MuseMapLook.card;
    return museFitView(size, widget.home.point, pts, topShare: look.fitTop, fill: look.fitFill, minSpan: look.fitMinSpan);
  }

  /// 连接状态 / 节点 / 国家变了：从当前取景一次性过渡到新取景（尺寸未知时等 build 直接定）。
  void _reframe() {
    final size = _viewSize;
    if (size == null || _viewTo == null) return;
    final target = _targetView(size);
    if (target == _viewTo) return;
    if (_instant) {
      _viewFrom = _viewTo = target;
      _kFrom = _kTo = _strideFor(target, size);
      _view.value = 1;
      return;
    }
    _viewFrom = _viewNow();
    _viewTo = target;
    _kFrom = _strideFor(_viewFrom!, size);
    _kTo = _strideFor(target, size);
    _view.duration = museScaleDuration(_level, MuseRouteMotion.view);
    _view.forward(from: 0);
  }
  String? _hlFrom;
  String? _hlTo;

  /// 1.20.1 M8：淡出的旧国家从它被打断时的透明度开始淡出（原来总从 1 开始，会先跳亮一下）
  double _hlFromAlpha = 1;

  String? get _hlTarget => widget.connected ? widget.highlightRegion : null;

  void _retarget() {
    final target = _hlTarget;
    if (target == _hlTo) return;
    _hlFromAlpha = _hl.isAnimating ? MuseRouteMotion.curve.transform(_hl.value) : 1.0;
    _hlFrom = _hlTo;
    _hlTo = target;
    if (_instant) {
      _hl.value = 1;
    } else {
      _hl.duration = museScaleDuration(_level, MuseRouteMotion.highlight);
      _hl.forward(from: 0);
    }
  }

  MuseWorldDots? _dots;
  MuseMotionLevel _level = MuseMotionLevel.standard;
  bool _started = false;

  /// 终点滑动的起止（未滑动时 from == to）
  MuseGeoPoint? _from;
  MuseGeoPoint? _to;

  /// 测试用：当前是否有动画在跑。
  bool get animating =>
      _out.isAnimating ||
      _arc.isAnimating ||
      _dot.isAnimating ||
      _slide.isAnimating ||
      _tint.isAnimating ||
      _hl.isAnimating ||
      _view.isAnimating;

  /// 测试用：已连接色的混合程度（0 = 中性，1 = 已连接）。
  double get tint => _tint.value;

  /// 测试用（1.20.1）：此刻的弧线终点（滑动中为插值）。
  MuseGeoPoint? get endPoint => _current();

  /// 测试用（1.20.1）：弧线此刻的整体透明度（断开淡出中 < 1，没有弧线为 0）。
  double get arcOpacity => _arc.value <= 0 ? 0 : 1 - MuseRouteMotion.curve.transform(_out.value);

  /// 测试用（1.20.1）：此刻画的底图点阵层（过渡中为交叉淡化的两档；静止时一层）。
  List<MuseDotLayer> dotLayersNow() {
    final size = _viewSize;
    final v = _viewNow();
    final dots = _dots;
    if (size == null || v == null || dots == null) return const [];
    final share = widget.look?.dotShare ?? MuseDesk.dotRadiusShare;
    return _view.isAnimating
        ? museDotLayers(dots, v, size, share, kFrom: _kFrom, kTo: _kTo, t: MuseRouteMotion.curve.transform(_view.value))
        : museDotLayers(dots, v, size, share);
  }

  @override
  void initState() {
    super.initState();
    _dots = widget.dots ?? _dotsLoaded;
    if (_dots == null) {
      museLoadWorldDots().then((d) {
        if (mounted && d != null) {
          setState(() {
            _dots = d;
            // the first frame had no dots to frame on: take the right view at once (no transition)
            _viewTo = null;
          });
        }
      });
    }
    _out.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _arc.value = 0;
        _out.value = 0;
      }
    });
    _arc.addStatusListener((s) {
      if (s == AnimationStatus.completed && _level == MuseMotionLevel.standard && widget.connected) {
        _dot.forward(from: 0);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _level = museMotionLevel(context);
    if (!_started) {
      _started = true;
      _to = _from = widget.exit.city?.point;
      if (widget.connected && widget.exit.known) _reveal();
      _retarget();
    } else if (_instant) {
      _finishAll();
    }
  }

  @override
  void didUpdateWidget(MuseRouteMap old) {
    super.didUpdateWidget(old);
    if (widget.dots != null && widget.dots != old.dots) _dots = widget.dots;
    _retarget();
    if (widget.connected != old.connected ||
        widget.highlightRegion != old.highlightRegion ||
        widget.exit.city?.point != old.exit.city?.point ||
        widget.fit != old.fit ||
        widget.centerLon != old.centerLon) {
      _reframe();
    }
    if (widget.connected != old.connected) {
      final target = widget.connected ? 1.0 : 0.0;
      if (_instant) {
        _tint.value = target;
      } else {
        _tint.duration = museScaleDuration(_level, MuseMotion.fast);
        _tint.animateTo(target, curve: MuseMotion.curve);
      }
    }
    final city = widget.exit.city?.point;
    if (!widget.connected || city == null) {
      _dot.stop();
      _dot.value = 0;
      final wasShown = old.connected && old.exit.known && _arc.value > 0;
      if (wasShown && !_instant && !widget.connected) {
        // 1.20.1 M5: the arc fades out with the reframe; the end stays where it was meanwhile
        _slide.stop();
        _from = _to = _current();
        _out.duration = museScaleDuration(_level, MuseRouteMotion.sync);
        _out.forward(from: 0);
        return;
      }
      if (_out.isAnimating) return;
      _arc.value = 0;
      _slide.stop();
      _from = _to = city;
      return;
    }
    if (_out.isAnimating || _out.value > 0) {
      _out.stop();
      _out.value = 0;
      _arc.value = 0;
    }
    final wasShown = old.connected && old.exit.known;
    if (!wasShown) {
      _from = _to = city;
      _reveal();
    } else if (city != _to) {
      _from = _current();
      _to = city;
      _dot.stop();
      _dot.value = 0;
      if (_instant) {
        _from = city;
        _slide.value = 1;
      } else {
        _slide.duration = museScaleDuration(_level, MuseRouteMotion.slide);
        _slide.forward(from: 0);
      }
    }
  }

  void _reveal() {
    _dot.value = 0;
    _slide.value = 1;
    switch (_instant ? MuseMotionLevel.off : _level) {
      case MuseMotionLevel.off:
        _arc.value = 1;
      case MuseMotionLevel.reduced:
        // 精简：整条弧直接淡入
        _arc.duration = museScaleDuration(_level, MuseMotion.enter);
        _arc.forward(from: 0);
      case MuseMotionLevel.standard:
        _arc.duration = MuseRouteMotion.draw;
        _arc.forward(from: 0);
    }
  }

  void _finishAll() {
    _dot.stop();
    _dot.value = 0;
    if (_arc.isAnimating) _arc.value = 1;
    if (_slide.isAnimating) _slide.value = 1;
    if (_tint.isAnimating) _tint.value = widget.connected ? 1 : 0;
    if (_hl.isAnimating) _hl.value = 1;
    if (_view.isAnimating) _view.value = 1;
    if (_out.isAnimating) _out.value = 1;
  }

  MuseGeoPoint? _current() {
    final a = _from;
    final b = _to;
    if (a == null || b == null) return b;
    return museSlideLerp(a, b, MuseRouteMotion.curve.transform(_slide.value));
  }

  @override
  void dispose() {
    _out.dispose();
    _arc.dispose();
    _dot.dispose();
    _slide.dispose();
    _tint.dispose();
    _hl.dispose();
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final exit = widget.exit;
    final shown = widget.connected && exit.known;
    final delay = widget.delayMs ?? 0;
    final caption = !widget.connected
        ? (widget.connecting ? '连接中…' : '未连接')
        : exit.known
        ? '${widget.home.name} → ${exit.city!.name} · ${exit.source.label}${delay > 0 ? ' · $delay ms' : ''}'
        : '出口位置未知';
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return Semantics(
      label: widget.connected && exit.known
          ? '路由：${widget.home.name} 到 ${exit.city!.name}（${exit.source.label}）'
          : caption,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1.19.2: as wide as the card (was centred at its aspect ratio under the height cap, which left
          // wide blank margins on a computer window); a flatter map shows less latitude instead
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth.isFinite ? c.maxWidth : 0.0;
              final h = widget.height ?? museRouteMapHeight(w, widget.aspectRatio, widget.maxHeight);
              return SizedBox(
                key: const ValueKey('muse_route_map_box'),
                width: w,
                height: h,
                child: Builder(
                  builder: (context) {
                    final size = Size(w, h);
                    final dots = _dots;
                    // 1.20.0: a new size (window resized, first layout) takes its view at once; a new
                    // node / connection state moves to it in [_reframe]
                    if (_viewTo == null || _viewSize != size) {
                      _viewSize = size;
                      _viewFrom = _viewTo = _targetView(size);
                      _kFrom = _kTo = _strideFor(_viewTo!, size);
                      _view.value = 1;
                    }
                    final dotColor = widget.dotColor ?? museDotColor(scheme);
                    final share = widget.look?.dotShare ?? MuseDesk.dotRadiusShare;
                    final bg = widget.surface ?? MuseSurfaceScope.of(context).color(scheme);
                    return AnimatedBuilder(
                      animation: _view,
                      builder: (context, _) {
                        final view = _viewNow() ?? MuseMapView.full;
                        // during a reframe the dots are drawn straight (one draw call per frame); at rest
                        // they are the one pre-rendered image of the final view
                        final moving = _view.isAnimating;
                        final img = dots == null || size.isEmpty || moving
                            ? null
                            : museDotMapImage(dots, size, dpr, dotColor, view: view, share: share);
                        final Widget? base = img != null
                            ? CustomPaint(key: const ValueKey('muse_route_base'), painter: _ImagePainter(img))
                            : dots != null && moving
                            ? CustomPaint(
                                key: const ValueKey('muse_route_base_moving'),
                                painter: _DotsPainter(
                                  dots: dots,
                                  view: view,
                                  color: dotColor,
                                  share: share,
                                  kFrom: _kFrom,
                                  kTo: _kTo,
                                  t: MuseRouteMotion.curve.transform(_view.value),
                                ),
                              )
                            : null;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            if (base != null)
                              RepaintBoundary(
                                child: widget.baseMask == null
                                    ? base
                                    : ShaderMask(
                                        blendMode: BlendMode.dstIn,
                                        shaderCallback: widget.baseMask!.createShader,
                                        child: base,
                                      ),
                              ),
                            // 1.20.1 B: the end dots' card-colour rings only clear the grey base dots — drawn
                            // under the lit country (they used to wipe a small country's last dots)
                            if (widget.look != null && widget.look!.ring > 0)
                              CustomPaint(
                                key: const ValueKey('muse_route_end_ring'),
                                painter: _EndRingPainter(
                                  state: this,
                                  home: widget.home.point,
                                  shown: shown,
                                  view: view,
                                  look: widget.look!,
                                  bg: bg,
                                ),
                              ),
                            if (dots != null && widget.highlightRegion != null)
                              CustomPaint(
                                key: const ValueKey('muse_route_highlight'),
                                painter: _HighlightPainter(
                                  state: this,
                                  dots: dots,
                                  view: view,
                                  color: museLinkedColor(
                                    scheme,
                                    bg,
                                    ratio: widget.look == null ? 3 : MuseHomeA.highlightContrast,
                                  ),
                                  look: widget.look,
                                ),
                              ),
                            CustomPaint(
                              key: const ValueKey('muse_route_arc'),
                              painter: _ArcPainter(
                                state: this,
                                home: widget.home.point,
                                shown: shown,
                                view: view,
                                fade: _level == MuseMotionLevel.reduced,
                                color: museLinkedColor(scheme, bg),
                                homeColor: museRouteIdleColor(scheme),
                                shares: widget.shares,
                                shareColors: museRouteKindColors(scheme),
                                glow: !widget.fit,
                                look: widget.look,
                                bg: bg,
                              ),
                            ),
                            // 1.19.1 A3: the city names on the map (the exit fades in with the arc's tail)
                            if (!size.isEmpty && widget.showLabels) ..._labels(context, size, view, shown, bg),
                          ],
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
          if (widget.showCaption) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            key: const ValueKey('muse_route_caption'),
            textAlign: TextAlign.center,
            // 1.19.1 A3: 13 on a computer window (was the 12 bodySmall, which a phone keeps so its
            // layout stays exactly as in 1.19.0)
            style: widget.maxHeight != null
                ? MuseTextLevel.footnote.style(context, color: scheme.onSurfaceVariant)
                : Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          ],
        ],
      ),
    );
  }

  /// 1.19.1 A3: 本机 and exit names beside their dots — 13 / w600 with a halo in the card's colour
  /// so the dot grid never runs through the letters; the exit name in the 已连接 colour. The names sit
  /// on the far sides of the two dots (they are often close together).
  /// 1.19.2: the exit name sits where the arc ends (the wrapped longitude — 洛杉矶 used to land left of
  /// the map), measured and kept wholly inside the map: flipped inward at an edge, never wrapped.
  List<Widget> _labels(BuildContext context, Size size, MuseMapView view, bool shown, Color bg) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final h = museProject(widget.home.point.lat, widget.home.point.lon, size, view: view);
    final look = widget.look;
    final style = look == null
        ? MuseTextLevel.footnote.style(context, weight: FontWeight.w600)
        : TextStyle(fontSize: look.labelSize, height: 1.2, fontWeight: look.labelWeight, color: scheme.onSurface);
    Size measure(String text) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final s = Size(tp.width + MuseDesk.mapLabelHalo, tp.height);
      tp.dispose();
      return s;
    }

    Widget label(String text, Color color, Key key) {
      final st = style.copyWith(color: color);
      return Stack(
        key: key,
        children: [
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: st.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = MuseDesk.mapLabelHalo
                ..strokeJoin = StrokeJoin.round
                ..color = bg,
            ),
          ),
          Text(text, maxLines: 1, softWrap: false, style: st),
        ],
      );
    }

    Widget place(Offset p, Size box, {required bool before, required bool above, required Widget child}) {
      final o = museLabelOffset(p, box, size, before: before, above: above);
      return Positioned(
        left: o.dx,
        top: o.dy,
        width: box.width,
        height: box.height,
        child: IgnorePointer(child: child),
      );
    }

    final exitName = widget.exit.city?.name;
    final homeBox = measure(widget.home.name);
    final exitBox = exitName == null ? Size.zero : measure(exitName);
    final exitColor = museLinkedColor(scheme, bg, ratio: 4.5);
    return [
      AnimatedBuilder(
        animation: Listenable.merge([_arc, _slide]),
        builder: (context, _) {
          final end = shown ? _current() : null;
          final e = end == null ? null : museProject(end.lat, end.lon, size, view: view);
          // the home name on the side away from the exit
          final before = e == null ? h.dx > size.width * 0.25 : e.dx >= h.dx;
          return Stack(
            fit: StackFit.expand,
            children: [
              place(
                h,
                homeBox,
                before: before,
                // 1.20.0 (连接卡): the home name above its dot, clear of the node row under the map
                above: widget.fit,
                child: label(
                  widget.home.name,
                  widget.labelColor ?? scheme.onSurface,
                  const ValueKey('muse_route_label_home'),
                ),
              ),
              // 1.20.0 (连接卡): no exit city name — the country is lit and the node row names it; the
              // name would sit on the country's outline
              if (e != null && exitName != null && _arc.value > 0 && !widget.fit)
                place(
                  e,
                  exitBox,
                  before: e.dx < h.dx,
                  above: true,
                  child: Opacity(
                    opacity: _level == MuseMotionLevel.reduced ? _arc.value : museRouteTailAlpha(_arc.value),
                    child: label(exitName, exitColor, const ValueKey('muse_route_label_exit')),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }
}

/// 1.19.2: the map's height for a card [width] wide — width / [aspectRatio], no more than [maxHeight]
/// (computer windows); the map always spans the full width.
double museRouteMapHeight(double width, double aspectRatio, double? maxHeight) {
  final h = width / aspectRatio;
  return maxHeight == null ? h : math.min(h, maxHeight);
}

/// 1.19.2 「已连接色」：主色；与底色 [bg] 的对比度不足 [ratio]（图形 3:1，文字 4.5:1）时向前景色（onSurface）
/// 逐步混合直到够（如藤黄、松花这类浅主色在浅色卡片上）。
Color museLinkedColor(ColorScheme s, Color bg, {double ratio = 3}) {
  var c = s.primary;
  for (var k = 1; k <= 10 && museContrast(c, bg) < ratio; k++) {
    c = Color.lerp(s.primary, s.onSurface, k / 10)!;
  }
  return c;
}

/// 1.19.2: 未连接 / 连接中时起点的中性色。
Color museRouteIdleColor(ColorScheme s) => s.onSurfaceVariant;


/// 1.19.1 A1: [child] no taller than [maxHeight] (centred, keeping its aspect ratio); null = as is.
Widget museCapHeight(double? maxHeight, Widget child) => maxHeight == null
    ? child
    : Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: child,
        ),
      );

/// 1.19.1 A2: the dot grid's colour — onSurface at 32 % on a light card, 24 % on a dark one (16 %
/// before, which nearly vanished on a light screen).
Color museDotColor(ColorScheme s) =>
    s.onSurface.withValues(alpha: s.brightness == Brightness.dark ? MuseDesk.dotAlphaDark : MuseDesk.dotAlphaLight);

/// 1.19.1 A1: the map's height cap on a window of [window] — ≤ 260 and ≤ 32 % of the window's
/// height, never under 160; null on a phone-sized window (unchanged there).
double? museRouteMapMaxHeight(Size window) {
  if (window.width <= MuseBreak.mobile) return null;
  return math.max(MuseDesk.mapMinHeight, math.min(MuseDesk.mapMaxHeight, window.height * MuseDesk.mapWindowShare));
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_ImagePainter old) => old.image != image;
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.state,
    required this.home,
    required this.shown,
    required this.fade,
    required this.color,
    required this.homeColor,
    this.view = MuseMapView.full,
    this.shares = const [],
    this.shareColors = const {},
    this.glow = true,
    this.look,
    this.bg,
  }) : super(repaint: Listenable.merge([state._arc, state._dot, state._slide, state._tint, state._out]));

  /// 1.20.0: the card's finer look (null = the 1.19 route card)
  final MuseMapLook? look;
  final Color? bg;

  final MuseRouteMapState state;
  final MuseGeoPoint home;
  final bool shown;
  final bool fade;

  /// 1.19.2: the 已连接 colour (arc, both ends while connected)
  final Color color;

  /// 1.19.2: the 本机 dot while not connected (neutral)
  final Color homeColor;
  final MuseMapView view;
  final List<(MuseRouteKind, double)> shares;
  final Map<MuseRouteKind, Color> shareColors;

  /// 1.20.0：取景模式下终点不画光晕、端点缩小，不盖住高亮的国家
  final bool glow;

  Offset _p(MuseGeoPoint g, Size size, {bool wrap = false}) => museProject(g.lat, g.lon, size, wrap: wrap, view: view);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final h = _p(home, size, wrap: true);
    // 1.19.2: neutral → 已连接 colour in one short step when the connection comes up (and back)
    final t = state._tint.value;
    final homeC = Color.lerp(homeColor.withValues(alpha: 0.8), look?.arcFromNeutral ?? false ? homeColor : color, t)!;
    canvas.drawCircle(h, look?.homeR ?? 3.5, Paint()..color = homeC);
    final end = state._current();
    final fading = state._out.value > 0;
    if ((!shown && !fading) || end == null) {
      canvas.restore();
      return;
    }
    final arcV = state._arc.value;
    if (arcV <= 0) {
      canvas.restore();
      return;
    }
    var pts = museGreatCircle(home, end);
    // 1.20.0：换了中央经线时把整条弧平移到视窗经度区间
    final shift = museWrapLon(pts.first.lon, center: view.center) - pts.first.lon;
    if (shift != 0) pts = [for (final p in pts) MuseGeoPoint(p.lat, p.lon + shift)];
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = _p(pts[i], size);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final metric = path.computeMetrics().firstOrNull;
    if (metric == null) {
      canvas.restore();
      return;
    }
    final progress = fade ? 1.0 : MuseMotion.curve.transform(arcV);
    final alpha = (fade ? arcV : 1.0) * (1 - MuseRouteMotion.curve.transform(state._out.value));
    final line = Paint()
      ..color = color.withValues(alpha: 0.9 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = look?.arcWidth ?? 2
      ..strokeCap = StrokeCap.round;
    if (look?.arcFromNeutral ?? false) {
      final b = path.getBounds();
      final hp = _p(pts.first, size);
      final ep = _p(pts.last, size);
      if (b.width > 0) {
        line.shader = ui.Gradient.linear(hp, ep, [homeColor.withValues(alpha: 0.55 * alpha), color.withValues(alpha: alpha)]);
      }
    }
    final drawn = metric.extractPath(0, metric.length * progress);
    // 1.19.2: an arc that runs past the map's east / west edge comes back in on the other side
    for (final dx in [-size.width * 360 / view.span, 0.0, size.width * 360 / view.span]) {
      canvas.drawPath(dx == 0 ? drawn : drawn.shift(Offset(dx, 0)), line);
    }
    // 1.19.1：分类线与终点随弧线尾段淡入（精简档整体已在淡入，不再叠加）
    final tail = fade ? alpha : alpha * museRouteTailAlpha(arcV);
    if (tail > 0 && shares.isNotEmpty) {
      for (final dx in [-size.width * 360 / view.span, 0.0, size.width * 360 / view.span]) {
        canvas.save();
        canvas.translate(dx, 0);
        _paintShares(canvas, size, pts, tail);
        canvas.restore();
      }
    }
    if (tail > 0) {
      final e = _p(pts.last, size, wrap: true);
      if (glow) canvas.drawCircle(e, 7, Paint()..color = color.withValues(alpha: 0.18 * tail));
      canvas.drawCircle(e, look?.endR ?? (glow ? 3.5 : 2.5), Paint()..color = color.withValues(alpha: tail));
    }
    final d = state._dot;
    if (d.isAnimating && d.value > 0 && d.value < 1) {
      final lapT = (d.value * MuseRouteMotion.laps) % 1.0;
      final tan = metric.getTangentForOffset(metric.length * lapT);
      if (tan != null) {
        final x = tan.position.dx % size.width;
        final pos = Offset(x < 0 ? x + size.width : x, tan.position.dy);
        canvas.drawCircle(pos, 5, Paint()..color = color.withValues(alpha: 0.25));
        canvas.drawCircle(pos, 2.5, Paint()..color = Colors.white);
      }
    }
    canvas.restore();
  }

  /// 分类线：走代理的类别画成主弧线两侧微微鼓起的细弧，直连画成本机周围的一圈；线宽随占比。
  void _paintShares(Canvas canvas, Size size, List<MuseGeoPoint> pts, double alpha) {
    final screen = [for (final p in pts) _p(p, size)];
    final h = screen.first;
    var side = 0;
    for (final (kind, share) in shares) {
      final w = museRouteShareWidth(share);
      final c = (shareColors[kind] ?? color).withValues(alpha: 0.75 * alpha);
      final paint = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round;
      if (kind == MuseRouteKind.direct) {
        canvas.drawCircle(h, 6 + w / 2, paint);
        continue;
      }
      // 交替放在两侧，越往后离主弧越远
      side++;
      final offset = (side.isOdd ? 1 : -1) * (4.0 + 3.0 * ((side - 1) ~/ 2));
      final path = Path();
      for (var i = 0; i < screen.length; i++) {
        final t = i / (screen.length - 1);
        final a = screen[i == 0 ? 0 : i - 1];
        final b = screen[i == screen.length - 1 ? i : i + 1];
        final d = b - a;
        final len = d.distance;
        final n = len == 0 ? Offset.zero : Offset(-d.dy / len, d.dx / len);
        // 两端贴住起止点，中间离开主弧
        final o = screen[i] + n * (offset * 4 * t * (1 - t));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.shares != shares ||
      old.shown != shown ||
      old.home != home ||
      old.fade != fade ||
      old.view != view ||
      old.color != color ||
      old.homeColor != homeColor;
}

/// 分类线线宽：占比 0–1 → 1–6 逻辑像素。
double museRouteShareWidth(double share) => 1.0 + 5.0 * share.clamp(0.0, 1.0);

/// 各类分类线的颜色（跟随当前配色）。
Map<MuseRouteKind, Color> museRouteKindColors(ColorScheme s) => {
  MuseRouteKind.ai: s.tertiary,
  MuseRouteKind.video: s.secondary,
  MuseRouteKind.dev: s.error.withValues(alpha: 0.9),
  MuseRouteKind.direct: s.onSurfaceVariant,
};


/// 1.20.0：连接卡上地图的细节取值——点更细更匀、弧线更细、端点带底色描边、本机名更轻；取景的留白比例。
class MuseMapLook {
  const MuseMapLook({
    this.dotShare = MuseDesk.dotRadiusShare,
    this.highlightScale = 1.0,
    this.arcWidth = 2,
    this.homeR = 3.5,
    this.endR = 2.5,
    this.ring = 0,
    this.labelSize = 13,
    this.labelWeight = FontWeight.w600,
    this.arcFromNeutral = false,
    this.fitTop = 0.24,
    this.fitFill = 0.48,
    this.fitMinSpan = 100,
  });

  /// 方向 A 连接卡（数值在 [MuseHomeA]）
  static const card = MuseMapLook(
    dotShare: MuseHomeA.dotShare,
    highlightScale: MuseHomeA.highlightScale,
    arcWidth: MuseHomeA.arcWidth,
    homeR: MuseHomeA.endDot,
    endR: MuseHomeA.endDot,
    ring: MuseHomeA.endRing,
    labelWeight: FontWeight.w400,
    arcFromNeutral: true,
    fitTop: MuseHomeA.fitTop,
    fitFill: MuseHomeA.fitFill,
    fitMinSpan: MuseHomeA.fitMinSpan,
  );

  /// 点半径 = 格距 × [dotShare]
  final double dotShare;

  /// 高亮国家点相对底图点的半径倍数
  final double highlightScale;
  final double arcWidth;
  final double homeR;
  final double endR;

  /// 端点外一圈卡片底色（把端点从高亮点阵里剥出来）
  final double ring;
  final double labelSize;
  final FontWeight labelWeight;

  /// 弧线从本机端的中性色渐变到目的地端的已连接色
  final bool arcFromNeutral;

  /// 取景：内容最北端放在地图高度的 [fitTop] 处，内容纬度跨度不超过地图高度的 [fitFill]，经度跨度至少 [fitMinSpan]°
  final double fitTop;
  final double fitFill;
  final double fitMinSpan;
}

final _regionCellsCache = <String, List<int>>{};

/// 1.20.0：国家 [region] 在点阵上的格序号；表里没有时取 [near] 附近 [MuseHomeA.nearCityDeg]° 内的陆地格
/// （结果按国家 + 城市缓存）。1.20.1 起表来自 1:50m，香港、新加坡、澳门、卡塔尔等也有格；[near] 应是该地区自己的
/// 代表城市（[museCityForRegion]），不能用当前节点的城市（淡出旧国家时曾用新节点的城市）。
List<int> museRegionCells(MuseWorldDots dots, String region, {MuseGeoPoint? near}) {
  final hit = museDotCountryCells[region.toUpperCase()];
  if (hit != null && hit.isNotEmpty) return hit;
  if (near == null) return const [];
  final key = '${identityHashCode(dots)}:${region.toUpperCase()}:${near.lat}:${near.lon}';
  final cached = _regionCellsCache[key];
  if (cached != null) return cached;
  const d = MuseHomeA.nearCityDeg;
  final out = <int>[];
  for (var r = 0; r < dots.height; r++) {
    for (var c = 0; c < dots.width; c++) {
      if (!dots.isLand(r, c)) continue;
      final p = dots.cellCenter(r, c);
      if ((p.lat - near.lat).abs() <= d && (museWrapLon(p.lon, center: near.lon) - near.lon).abs() <= d) {
        out.add(r * dots.width + c);
      }
    }
  }
  if (_regionCellsCache.length > 16) _regionCellsCache.clear();
  return _regionCellsCache[key] = out;
}

/// 1.20.1：细网格表里的一个点（打包格式见 route_countries.dart）。
MuseGeoPoint museUnpackFine(int v) => MuseGeoPoint((v ~/ 4096 - 720) / 8, (v % 4096 - 1440) / 8);

/// 1.20.1：细网格的格距（度），与 [museDotCountryFine] 的各级一一对应。
const museFineSteps = [0.5, 0.25];

/// 1.20.1：取景用的国家位置——底图格中心；底图格不到 [MuseHomeA.hlMinDots] 个的小国再加上 0.5° 细网格的点
/// （真实轮廓），都没有时是代表城市本身。
List<MuseGeoPoint> museRegionPoints(MuseWorldDots dots, String region, {MuseGeoPoint? near}) {
  final code = region.toUpperCase();
  final cells = museRegionCells(dots, code, near: near);
  final out = [for (final i in cells) dots.cellCenter(i ~/ dots.width, i % dots.width)];
  if (out.length < MuseHomeA.hlMinDots) {
    final fine = museDotCountryFine[code];
    if (fine != null) {
      for (final lv in fine) {
        if (lv.isEmpty) continue;
        out.addAll(lv.map(museUnpackFine));
        break;
      }
    }
  }
  if (out.isEmpty && near != null) out.add(near);
  return out;
}

/// 1.20.1：一层高亮点（屏幕坐标）与它们的半径。
class MuseHighlightLayer {
  const MuseHighlightLayer(this.points, this.radius);

  final List<Offset> points;
  final double radius;
}

bool _inMap(Offset o, Size size, double r) => o.dx >= -r && o.dx <= size.width + r && o.dy >= -r && o.dy <= size.height + r;

/// 1.20.1：节点所在国家 [region] 在 [view] / [size] 下要点亮的点——
/// 1. 永不抽稀：国家的每个底图格都画（原来跟底图一起隔点画，荷兰 4 个点只剩 1 个）；
/// 2. 底图格看得见的不到 [MuseHomeA.hlMinDots] 个时，改用 1:50m 细网格里点数够的最粗一级（真实轮廓，点更细）；
/// 3. 屏幕上仍不到 [MuseHomeA.hlMinDots] 个点或外接框小于 [MuseHomeA.hlMinPx] 像素（新加坡、香港、澳门）时，
///    再点亮出口城市（该地区自己的代表城市 [city]）[MuseHomeA.hlNearPx] 像素内的底图陆地格。
/// 半径随格距连续变化（不再随抽稀档位跳）。
List<MuseHighlightLayer> museHighlightLayers(
  MuseWorldDots dots,
  String region,
  MuseMapView view,
  Size size, {
  MuseMapLook? look,
  MuseGeoPoint? city,
}) {
  if (size.isEmpty) return const [];
  final code = region.toUpperCase();
  final share = look?.dotShare ?? MuseDesk.dotRadiusShare;
  final cell = size.width / view.span * dots.step;
  final r = math.max(
    museDotRadius(cell, 1, share) * (look?.highlightScale ?? MuseHomeA.highlightScale),
    look == null ? 0.0 : cell * MuseHomeA.highlightShare,
  );
  Offset proj(MuseGeoPoint p) => museProject(p.lat, p.lon, size, view: view);
  final cells = museDotCountryCells[code] ?? const <int>[];
  final coarse = <Offset>[];
  final taken = <int>{};
  for (final i in cells) {
    final o = proj(dots.cellCenter(i ~/ dots.width, i % dots.width));
    if (_inMap(o, size, r)) {
      coarse.add(o);
      taken.add(i);
    }
  }
  final layers = <MuseHighlightLayer>[];
  var shown = coarse;
  var shownR = r;
  if (coarse.length < MuseHomeA.hlMinDots) {
    final fine = museDotCountryFine[code];
    if (fine != null) {
      List<Offset>? best;
      var bestR = r;
      for (var lv = 0; lv < fine.length && lv < museFineSteps.length; lv++) {
        final pts = [for (final v in fine[lv]) proj(museUnpackFine(v))].where((o) => _inMap(o, size, r)).toList();
        if (pts.isEmpty) continue;
        final fr = (size.width / view.span * museFineSteps[lv] * MuseHomeA.fineShare).clamp(MuseHomeA.dotMinRadius, r);
        if (best == null || pts.length > best.length) {
          best = pts;
          bestR = fr;
        }
        if (pts.length >= MuseHomeA.hlMinDots) break;
      }
      if (best != null && best.length > coarse.length) {
        shown = best;
        shownR = bestR;
      }
    }
  }
  if (shown.isNotEmpty) layers.add(MuseHighlightLayer(shown, shownR));
  // 屏幕上的外接框
  var small = shown.length < MuseHomeA.hlMinDots;
  if (!small) {
    var l = double.infinity;
    var t = double.infinity;
    var rr = -double.infinity;
    var b = -double.infinity;
    for (final o in shown) {
      l = math.min(l, o.dx);
      t = math.min(t, o.dy);
      rr = math.max(rr, o.dx);
      b = math.max(b, o.dy);
    }
    small = math.max(rr - l, b - t) < MuseHomeA.hlMinPx;
  }
  if (small && city != null) {
    final c = proj(city);
    // 至少 [MuseHomeA.hlNearPx]，放大到格距很大时（香港、卡塔尔取景）至少够到相邻一圈格；终点实心点 [clear] 下面的点
    // 不算，看得见的仍不够 [MuseHomeA.hlMinDots] 个就再放大一点（最多到 3 格）
    var near = math.max(MuseHomeA.hlNearPx, cell * 1.5);
    final clear = look?.endR ?? 0;
    final seen = shown.where((o) => (o - c).distance > clear && _inMap(o, size, 0)).length;
    final reach = ((MuseHomeA.hlNearPx + cell * 3) / math.max(cell, 0.1)).ceil() + 1;
    final row0 = ((dots.north - city.lat) / dots.step).floor();
    final col0 = ((museWrapLon(city.lon, center: 0) + 180) / dots.step).floor();
    final ring = <(double, Offset)>[];
    for (var dr = -reach; dr <= reach; dr++) {
      final row = row0 + dr;
      if (row < 0 || row >= dots.height) continue;
      for (var dc = -reach; dc <= reach; dc++) {
        final col = (col0 + dc) % dots.width;
        if (!dots.isLand(row, col) || taken.contains(row * dots.width + col)) continue;
        final o = proj(dots.cellCenter(row, col));
        if (_inMap(o, size, 0)) ring.add(((o - c).distance, o));
      }
    }
    ring.sort((a, b) => a.$1.compareTo(b.$1));
    final limit = MuseHomeA.hlNearPx + cell * 3;
    double extent(double within) {
      final all = [...shown, for (final e in ring) if (e.$1 <= within) e.$2];
      if (all.isEmpty) return 0;
      final xs = all.map((o) => o.dx);
      final ys = all.map((o) => o.dy);
      return math.max(xs.reduce(math.max) - xs.reduce(math.min), ys.reduce(math.max) - ys.reduce(math.min));
    }

    while (near < limit &&
        (seen + ring.where((e) => e.$1 <= near && e.$1 > clear).length < MuseHomeA.hlMinDots ||
            extent(near) < MuseHomeA.hlMinPx)) {
      near += cell * 0.5;
    }
    final extra = [for (final e in ring) if (e.$1 <= near) e.$2];
    if (extra.isNotEmpty) layers.add(MuseHighlightLayer(extra, r));
  }
  return layers;
}

/// 1.20.1：一层底图点（屏幕坐标交错存 x, y）、半径与透明度。
class MuseDotLayer {
  const MuseDotLayer(this.points, this.radius, this.alpha);

  final Float32List points;
  final double radius;
  final double alpha;

  int get count => points.length ~/ 2;
}

/// 1.20.1 M1：取景过渡中的底图点阵。起止两个取景的抽稀档位 [kFrom] / [kTo] 不同时不再在某一帧整幅切换，
/// 而是交叉淡化：两档共有的点一直满不透明度（半径从起点档渐变到终点档），只属于起点档的点按 1 − [t] 淡出，
/// 只属于终点档的点按 [t] 淡入。[t] = 0 与起点取景的静止图一致，[t] = 1 与终点取景的静止图一致。
List<MuseDotLayer> museDotLayers(
  MuseWorldDots dots,
  MuseMapView view,
  Size size,
  double share, {
  int? kFrom,
  int? kTo,
  double t = 1,
}) {
  final cell = size.width / view.span * dots.step;
  final k = museDotStride(cell, share);
  final a = kFrom ?? k;
  final b = kTo ?? k;
  final ra = museDotRadius(cell, a, share);
  final rb = museDotRadius(cell, b, share);
  final both = <double>[];
  final onlyA = <double>[];
  final onlyB = <double>[];
  final rmax = math.max(ra, rb);
  for (var row = 0; row < dots.height; row++) {
    final inA = row % a == 0;
    final inB = row % b == 0;
    if (!inA && !inB) continue;
    for (var col = 0; col < dots.width; col++) {
      final ca = inA && col % a == 0;
      final cb = inB && col % b == 0;
      if (!ca && !cb) continue;
      if (!dots.isLand(row, col)) continue;
      final p = dots.cellCenter(row, col);
      if (p.lat > view.north || p.lat < view.south) continue;
      final o = museProject(p.lat, p.lon, size, view: view);
      if (o.dx < -rmax || o.dx > size.width + rmax) continue;
      final list = ca && cb ? both : (ca ? onlyA : onlyB);
      list
        ..add(o.dx)
        ..add(o.dy);
    }
  }
  final tt = t.clamp(0.0, 1.0);
  return [
    if (both.isNotEmpty) MuseDotLayer(Float32List.fromList(both), ra + (rb - ra) * tt, 1),
    if (onlyA.isNotEmpty && tt < 1) MuseDotLayer(Float32List.fromList(onlyA), ra, 1 - tt),
    if (onlyB.isNotEmpty && tt > 0) MuseDotLayer(Float32List.fromList(onlyB), rb, tt),
  ];
}

/// 1.20.0：取景过渡中直接画点阵（drawRawPoints），停下后换回预渲染的图。1.20.1：新旧两档交叉淡化（[museDotLayers]）。
class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.dots,
    required this.view,
    required this.color,
    required this.share,
    this.kFrom,
    this.kTo,
    this.t = 1,
  });

  final MuseWorldDots dots;
  final MuseMapView view;
  final Color color;
  final double share;
  final int? kFrom;
  final int? kTo;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in museDotLayers(dots, view, size, share, kFrom: kFrom, kTo: kTo, t: t)) {
      canvas.drawRawPoints(
        ui.PointMode.points,
        l.points,
        Paint()
          ..color = color.withValues(alpha: color.a * l.alpha)
          ..strokeWidth = l.radius * 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.view != view ||
      old.color != color ||
      old.dots != dots ||
      old.share != share ||
      old.kFrom != kFrom ||
      old.kTo != kTo ||
      old.t != t;
}

/// 1.20.1 B：两端点外一圈卡片底色——画在底图之上、国家高亮之下，只擦掉灰色底图点，不再盖住小国仅有的高亮点。
class _EndRingPainter extends CustomPainter {
  _EndRingPainter({
    required this.state,
    required this.home,
    required this.shown,
    required this.view,
    required this.look,
    required this.bg,
  }) : super(repaint: Listenable.merge([state._arc, state._slide, state._out]));

  final MuseRouteMapState state;
  final MuseGeoPoint home;
  final bool shown;
  final MuseMapView view;
  final MuseMapLook look;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final h = museProject(home.lat, home.lon, size, view: view);
    canvas.drawCircle(h, look.homeR + look.ring, Paint()..color = bg);
    final end = state._current();
    final fading = state._out.value > 0;
    if ((shown || fading) && end != null && state._arc.value > 0) {
      final tail = (state._level == MuseMotionLevel.reduced ? state._arc.value : museRouteTailAlpha(state._arc.value)) *
          (1 - MuseRouteMotion.curve.transform(state._out.value));
      if (tail > 0) {
        final e = museProject(end.lat, end.lon, size, view: view);
        canvas.drawCircle(e, look.endR + look.ring, Paint()..color = bg.withValues(alpha: bg.a * tail));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EndRingPainter old) => old.view != view || old.bg != bg || old.shown != shown || old.home != home;
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter({required this.state, required this.dots, required this.view, required this.color, this.look})
    : super(repaint: state._hl);

  final MuseMapLook? look;

  final MuseRouteMapState state;
  final MuseWorldDots dots;
  final MuseMapView view;
  final Color color;

  void _region(Canvas canvas, Size size, String region, double alpha) {
    if (alpha <= 0) return;
    final paint = Paint()..color = color.withValues(alpha: color.a * alpha);
    // 1.20.1 M9: a region's own city (the fading-out old country used the new node's city)
    final own = museCityForRegion(region)?.point ??
        (state.widget.highlightRegion?.toUpperCase() == region.toUpperCase() ? state.widget.exit.city?.point : null);
    for (final l in museHighlightLayers(dots, region, view, size, look: look, city: own)) {
      for (final o in l.points) {
        canvas.drawCircle(o, l.radius, paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = MuseRouteMotion.curve.transform(state._hl.value);
    final from = state._hlFrom;
    final to = state._hlTo;
    if (from != null && from != to) _region(canvas, size, from, state._hlFromAlpha * (1 - t));
    if (to != null) _region(canvas, size, to, t);
  }

  @override
  bool shouldRepaint(_HighlightPainter old) => old.color != color || old.view != view || old.dots != dots;
}
