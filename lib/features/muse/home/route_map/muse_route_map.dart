// 穿云 1.19.0 P1 - 首页「路由弧线图」：点阵世界底图 + 本机到出口城市的大圆弧。
// 连接成功时弧线 1100ms 画出，光点沿弧跑 2 趟后停；切节点终点 700ms 滑到新城市。
// 动效档位：标准=完整；精简=弧线直接淡入、无光点；关闭=静态。所有动画一次性，结束后不再出帧；
// 页面不可见（TickerMode 关）时 Ticker 静音即停；无循环、无轮询。底图只在尺寸/颜色变化时预渲染一次成 ui.Image。
// 只借鉴公开思路，不含任何第三方代码或素材。
// Part of 穿云 (GPLv3).

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/home/route_map/route_share.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';

/// 弧线图动效时长。
abstract final class MuseRouteMotion {
  /// 弧线画出
  static const draw = Duration(milliseconds: 1100);

  /// 光点每跑一趟
  static const lap = Duration(milliseconds: 900);

  /// 光点趟数（之后停）
  static const laps = 2;

  /// 切节点时终点滑动
  static const slide = Duration(milliseconds: 700);
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
ui.Image museDotMapImage(MuseWorldDots dots, Size size, double dpr, Color color) {
  final w = (size.width * dpr).round().clamp(1, 4096);
  final h = (size.height * dpr).round().clamp(1, 4096);
  final key = '${identityHashCode(dots)}:$w:$h:${color.toARGB32()}';
  final hit = _imageCache[key];
  if (hit != null) return hit;
  museDotImageRenders++;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final paint = Paint()..color = color;
  final px = Size(w.toDouble(), h.toDouble());
  final cell = w / 360 * dots.step;
  final r = (cell * 0.32).clamp(0.6, 6.0);
  for (var row = 0; row < dots.height; row++) {
    for (var col = 0; col < dots.width; col++) {
      if (!dots.isLand(row, col)) continue;
      final p = dots.cellCenter(row, col);
      if (p.lat > museMapNorth || p.lat < museMapSouth) continue;
      canvas.drawCircle(museProject(p.lat, p.lon, px), r, paint);
    }
  }
  final img = rec.endRecording().toImageSync(w, h);
  if (_imageCache.length >= 2) _imageCache.remove(_imageCache.keys.first);
  _imageCache[key] = img;
  return img;
}

int museDotImageRenders = 0;

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
  });

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

  MuseWorldDots? _dots;
  MuseMotionLevel _level = MuseMotionLevel.standard;
  bool _started = false;

  /// 终点滑动的起止（未滑动时 from == to）
  MuseGeoPoint? _from;
  MuseGeoPoint? _to;

  /// 测试用：当前是否有动画在跑。
  bool get animating => _arc.isAnimating || _dot.isAnimating || _slide.isAnimating;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final exit = widget.exit;
    final shown = widget.connected && exit.known;
    final caption = !widget.connected
        ? (widget.connecting ? '连接中…' : '未连接')
        : exit.known
        ? '${widget.home.name} → ${exit.city!.name} · ${exit.source.label}'
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
          AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: LayoutBuilder(
              builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                final dots = _dots;
                final img = dots == null || size.isEmpty
                    ? null
                    : museDotMapImage(dots, size, dpr, scheme.onSurface.withValues(alpha: 0.16));
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
                        fade: _level == MuseMotionLevel.reduced,
                        color: scheme.primary,
                        homeColor: scheme.onSurface,
                        shares: widget.shares,
                        shareColors: museRouteKindColors(scheme),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            key: const ValueKey('muse_route_caption'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
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
    this.shares = const [],
    this.shareColors = const {},
  }) : super(repaint: Listenable.merge([state._arc, state._dot, state._slide]));

  final MuseRouteMapState state;
  final MuseGeoPoint home;
  final bool shown;
  final bool fade;
  final Color color;
  final Color homeColor;
  final List<(MuseRouteKind, double)> shares;
  final Map<MuseRouteKind, Color> shareColors;

  @override
  void paint(Canvas canvas, Size size) {
    final h = museProject(home.lat, home.lon, size);
    canvas.drawCircle(h, 3, Paint()..color = homeColor.withValues(alpha: 0.7));
    final end = state._current();
    if (!shown || end == null) return;
    final arcV = state._arc.value;
    if (arcV <= 0) return;
    final pts = museGreatCircle(home, end);
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = museProject(pts[i].lat, pts[i].lon, size, wrap: false);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final metric = path.computeMetrics().firstOrNull;
    if (metric == null) return;
    final progress = fade ? 1.0 : MuseMotion.curve.transform(arcV);
    final alpha = fade ? arcV : 1.0;
    final line = Paint()
      ..color = color.withValues(alpha: 0.85 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(metric.extractPath(0, metric.length * progress), line);
    if (progress >= 1 && shares.isNotEmpty) _paintShares(canvas, size, pts, alpha);
    if (progress >= 1) {
      final e = museProject(pts.last.lat, pts.last.lon, size, wrap: false);
      canvas.drawCircle(e, 7, Paint()..color = color.withValues(alpha: 0.18 * alpha));
      canvas.drawCircle(e, 3.5, Paint()..color = color.withValues(alpha: alpha));
    }
    final d = state._dot;
    if (d.isAnimating && d.value > 0 && d.value < 1) {
      final lapT = (d.value * MuseRouteMotion.laps) % 1.0;
      final tan = metric.getTangentForOffset(metric.length * lapT);
      if (tan != null) {
        canvas.drawCircle(tan.position, 5, Paint()..color = color.withValues(alpha: 0.25));
        canvas.drawCircle(tan.position, 2.5, Paint()..color = Colors.white);
      }
    }
  }

  /// 分类线：走代理的类别画成主弧线两侧微微鼓起的细弧，直连画成本机周围的一圈；线宽随占比。
  void _paintShares(Canvas canvas, Size size, List<MuseGeoPoint> pts, double alpha) {
    final screen = [for (final p in pts) museProject(p.lat, p.lon, size, wrap: false)];
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
