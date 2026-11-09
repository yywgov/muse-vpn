// 穿云 1.19.0 P1 - 首页「路由弧线图」：点阵世界底图 + 本机到出口城市的大圆弧。
// 连接成功时弧线 1100ms 画出，光点沿弧跑 1 趟后停（1.19.1 起，原 2 趟）；切节点终点 450ms 滑到新城市（原 700ms）。
// 分类线与终点在弧线最后 15% 淡入（1.19.1）。
// 动效档位：标准=完整；精简=弧线直接淡入、无光点；关闭=静态。所有动画一次性，结束后不再出帧；
// 页面不可见（TickerMode 关）时 Ticker 静音即停；无循环、无轮询。底图只在尺寸/颜色变化时预渲染一次成 ui.Image。
// 1.19.2：地图铺满卡片宽度（按宽高比裁纬度取景）；终点名与弧线同一坐标、夹在地图内靠边翻转；已连接时起点、终点、
// 弧线用「已连接色」（主色，对比度不足时向前景色调到 ≥ 3:1），未连接 / 连接中起点为中性色，颜色切换一次性 200ms。
// 只借鉴公开思路，不含任何第三方代码或素材。
// Part of 穿云 (GPLv3).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 切节点时终点滑动（1.19.1：700 → 450ms）
  static const slide = Duration(milliseconds: 450);

  /// 分类线与终点在弧线最后这段（按时间）淡入，不在画完那一帧跳出（1.19.1）
  static const tailFade = 0.15;
}

/// 分类线与终点的透明度：弧线时间进度 [arcV] 的最后 [MuseRouteMotion.tailFade] 线性从 0 到 1。
double museRouteTailAlpha(double arcV) {
  const start = 1 - MuseRouteMotion.tailFade;
  return ((arcV - start) / MuseRouteMotion.tailFade).clamp(0.0, 1.0);
}

const museWorldDotsAsset = 'assets/map/world_dots.bin';

Future<MuseWorldDots?>? _dotsFuture;

/// 读一次底图点阵（进程内缓存）。
Future<MuseWorldDots?> museLoadWorldDots([AssetBundle? bundle]) => _dotsFuture ??= () async {
  try {
    final data = await (bundle ?? rootBundle).load(museWorldDotsAsset);
    return MuseWorldDots.parse(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } catch (_) {
    return null;
  }
}();

/// 预渲染的底图（最多留 2 个尺寸）。
final _imageCache = <String, ui.Image>{};

/// 把点阵画成一张图（同尺寸、同颜色只画一次）。测试可读 [museDotImageRenders] 确认没有重复渲染。
ui.Image museDotMapImage(MuseWorldDots dots, Size size, double dpr, Color color, {MuseMapView? view}) {
  final v = view ?? museMapView(size);
  final w = (size.width * dpr).round().clamp(1, 4096);
  final h = (size.height * dpr).round().clamp(1, 4096);
  final key = '${identityHashCode(dots)}:$w:$h:${color.toARGB32()}:${v.north}:${v.south}';
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
  final cell = size.width / 360 * dots.step;
  // a small map keeps every k-th dot instead of letting the minimum size run them together
  final k = museDotStride(cell);
  final r = (cell * k * MuseDesk.dotRadiusShare).clamp(MuseDesk.dotMinRadius, MuseDesk.dotMaxRadius) * dprX;
  for (var row = 0; row < dots.height; row += k) {
    for (var col = 0; col < dots.width; col += k) {
      if (!dots.isLand(row, col)) continue;
      final p = dots.cellCenter(row, col);
      if (p.lat > v.north || p.lat < v.south) continue;
      canvas.drawCircle(museProject(p.lat, p.lon, px, view: v), r, paint);
    }
  }
  final img = rec.endRecording().toImageSync(w, h);
  if (_imageCache.length >= 2) _imageCache.remove(_imageCache.keys.first);
  _imageCache[key] = img;
  return img;
}

int museDotImageRenders = 0;

/// 1.19.1 A2: every how-many-th dot to draw for a grid [cell] logical pixels apart, so that a dot
/// of [MuseDesk.dotMinRadius] still has room around it (1 = all of them).
int museDotStride(double cell) {
  var k = 1;
  while (k < 8 && cell * k * MuseDesk.dotRadiusShare < MuseDesk.dotMinRadius) {
    k++;
  }
  return k;
}

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
  });

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

  /// 1.19.2：中性色 (0) ↔ 已连接色 (1)，连接状态变化时一次性过渡
  late final AnimationController _tint = AnimationController(
    vsync: this,
    duration: MuseMotion.fast,
    value: widget.connected ? 1 : 0,
  );

  MuseWorldDots? _dots;
  MuseMotionLevel _level = MuseMotionLevel.standard;
  bool _started = false;

  /// 终点滑动的起止（未滑动时 from == to）
  MuseGeoPoint? _from;
  MuseGeoPoint? _to;

  /// 测试用：当前是否有动画在跑。
  bool get animating => _arc.isAnimating || _dot.isAnimating || _slide.isAnimating || _tint.isAnimating;

  /// 测试用：已连接色的混合程度（0 = 中性，1 = 已连接）。
  double get tint => _tint.value;

  @override
  void initState() {
    super.initState();
    _dots = widget.dots;
    if (_dots == null) {
      museLoadWorldDots().then((d) {
        if (mounted && d != null) setState(() => _dots = d);
      });
    }
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
    } else if (_level == MuseMotionLevel.off) {
      _finishAll();
    }
  }

  @override
  void didUpdateWidget(MuseRouteMap old) {
    super.didUpdateWidget(old);
    if (widget.dots != null && widget.dots != old.dots) _dots = widget.dots;
    if (widget.connected != old.connected) {
      final target = widget.connected ? 1.0 : 0.0;
      if (_level == MuseMotionLevel.off) {
        _tint.value = target;
      } else {
        _tint.duration = museScaleDuration(_level, MuseMotion.fast);
        _tint.animateTo(target, curve: MuseMotion.curve);
      }
    }
    final city = widget.exit.city?.point;
    if (!widget.connected || city == null) {
      _arc.value = 0;
      _dot.stop();
      _dot.value = 0;
      _slide.stop();
      _from = _to = city;
      return;
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
      if (_level == MuseMotionLevel.off) {
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
    switch (_level) {
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
  }

  MuseGeoPoint? _current() {
    final a = _from;
    final b = _to;
    if (a == null || b == null) return b;
    return museGeoLerp(a, b, MuseMotion.curve.transform(_slide.value));
  }

  @override
  void dispose() {
    _arc.dispose();
    _dot.dispose();
    _slide.dispose();
    _tint.dispose();
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
              final h = museRouteMapHeight(w, widget.aspectRatio, widget.maxHeight);
              return SizedBox(
                key: const ValueKey('muse_route_map_box'),
                width: w,
                height: h,
                child: Builder(
                  builder: (context) {
                    final size = Size(w, h);
                    final view = museMapView(size);
                    final dots = _dots;
                    final img = dots == null || size.isEmpty
                        ? null
                        : museDotMapImage(dots, size, dpr, museDotColor(scheme), view: view);
                    final bg = MuseSurfaceScope.of(context).color(scheme);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (img != null)
                          RepaintBoundary(
                            child: CustomPaint(key: const ValueKey('muse_route_base'), painter: _ImagePainter(img)),
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
                          ),
                        ),
                        // 1.19.1 A3: the two city names on the map (the exit fades in with the arc's tail)
                        if (!size.isEmpty) ..._labels(context, size, view, shown, bg),
                      ],
                    );
                  },
                ),
              );
            },
          ),
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
    final style = MuseTextLevel.footnote.style(context, weight: FontWeight.w600);
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
                above: false,
                child: label(widget.home.name, scheme.onSurface, const ValueKey('muse_route_label_home')),
              ),
              if (e != null && exitName != null && _arc.value > 0)
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
  }) : super(repaint: Listenable.merge([state._arc, state._dot, state._slide, state._tint]));

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

  Offset _p(MuseGeoPoint g, Size size, {bool wrap = false}) => museProject(g.lat, g.lon, size, wrap: wrap, view: view);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final h = _p(home, size, wrap: true);
    // 1.19.2: neutral → 已连接 colour in one short step when the connection comes up (and back)
    final t = state._tint.value;
    canvas.drawCircle(h, 3.5, Paint()..color = Color.lerp(homeColor.withValues(alpha: 0.8), color, t)!);
    final end = state._current();
    if (!shown || end == null) {
      canvas.restore();
      return;
    }
    final arcV = state._arc.value;
    if (arcV <= 0) {
      canvas.restore();
      return;
    }
    final pts = museGreatCircle(home, end);
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
    final alpha = fade ? arcV : 1.0;
    final line = Paint()
      ..color = color.withValues(alpha: 0.9 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final drawn = metric.extractPath(0, metric.length * progress);
    // 1.19.2: an arc that runs past the map's east / west edge comes back in on the other side
    for (final dx in [-size.width, 0.0, size.width]) {
      canvas.drawPath(dx == 0 ? drawn : drawn.shift(Offset(dx, 0)), line);
    }
    // 1.19.1：分类线与终点随弧线尾段淡入（精简档整体已在淡入，不再叠加）
    final tail = fade ? alpha : alpha * museRouteTailAlpha(arcV);
    if (tail > 0 && shares.isNotEmpty) {
      for (final dx in [-size.width, 0.0, size.width]) {
        canvas.save();
        canvas.translate(dx, 0);
        _paintShares(canvas, size, pts, tail);
        canvas.restore();
      }
    }
    if (tail > 0) {
      final e = _p(pts.last, size, wrap: true);
      canvas.drawCircle(e, 7, Paint()..color = color.withValues(alpha: 0.18 * tail));
      canvas.drawCircle(e, 3.5, Paint()..color = color.withValues(alpha: tail));
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
