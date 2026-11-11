// 穿云 1.20.1 外观 › 首页风格：留白 / 细线 / 数字，三张小预览图并排（1.20.3：加「经典」共四张，
// 去掉说明长句和勾，选中只换边框；卡片 [MuseChoiceCard] 也用于「配色」），点一下即时生效（首页直接换，
// 不重启、无动画循环）。预览图按当前主题的颜色与各风格的令牌（[MuseHomeLook]）现画，不是截图。
// Part of 穿云 (GPLv3).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart' show museLinkedColor;
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 1.20.3 首页风格的四个选项：留白 / 细线 / 数字 = 新首页（muse_home_style = new）+ 对应 muse_home_look；
/// 经典 = 1.18 的首页（muse_home_style = classic），原来单独一行「首页样式」并到这里。
enum MuseHomeChoice {
  airy('airy', '留白'),
  line('line', '细线'),
  number('number', '数字'),
  classic('classic', '经典');

  const MuseHomeChoice(this.key, this.title);

  final String key;
  final String title;

  /// 从两个旧键读出当前选项（经典优先）
  static MuseHomeChoice read({required String homeStyle, required String homeLook}) {
    if (homeStyle == 'classic') return classic;
    return switch (MuseHomeLookKind.fromKey(homeLook)) {
      MuseHomeLookKind.airy => airy,
      MuseHomeLookKind.line => line,
      MuseHomeLookKind.number => number,
    };
  }

  /// 选中后写的值：（muse_home_style, muse_home_look）。经典的风格令牌是留白（1.18 的首页本来就是留白的样子），
  /// 所以经典也写 airy，预览和首页一致。
  (String homeStyle, String homeLook) get target => switch (this) {
    airy || line || number => ('new', key),
    classic => ('classic', MuseHomeLookKind.airy.key),
  };

  MuseHomeLook get look => MuseHomeLook.of(this == classic ? MuseHomeLookKind.airy : MuseHomeLookKind.fromKey(key));
}

/// 外观页最上面的「首页风格」：四张预览并排（每张最宽 [MuseHomeLookPreview.maxWidth]），点一下即时生效。
class MuseHomeLookPicker extends ConsumerWidget {
  const MuseHomeLookPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = MuseHomeChoice.read(homeStyle: ref.watch(MusePrefs.homeStyle), homeLook: ref.watch(MusePrefs.homeLook));
    Future<void> pick(MuseHomeChoice c) async {
      final (style, look) = c.target;
      await ref.read(MusePrefs.homeLook.notifier).update(look);
      await ref.read(MusePrefs.homeStyle.notifier).update(style);
    }

    // 1.20.3: full width, so the group is as wide as the others on a wide window
    return Container(
      key: const ValueKey('appearance_home_look'),
      width: double.infinity,
      padding: const EdgeInsets.all(MuseSpace.s16),
      child: MuseChoiceRow(
        maxWidth: MuseHomeLookPreview.maxWidth,
        children: [
          for (final c in MuseHomeChoice.values)
            MuseChoiceCard(
              tapKey: ValueKey('home_look_${c.key}'),
              label: c.title,
              semantics: '首页风格 ${c.title}',
              selected: c == current,
              aspect: MuseHomeLookPreview.aspect,
              onTap: (_) => pick(c),
              child: MuseHomeLookPreview(look: c.look, map: c != MuseHomeChoice.classic),
            ),
        ],
      ),
    );
  }
}

/// 一行等宽的选项卡片（每张最宽 [maxWidth]，间距 12），放不下就折成多行、每行列数相同。
class MuseChoiceRow extends StatelessWidget {
  const MuseChoiceRow({super.key, required this.children, required this.maxWidth, this.columns});

  final List<Widget> children;
  final double maxWidth;

  /// 每行几张；null = 一行放下全部
  final int Function(double width)? columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = MuseSpace.s12;
      final n = columns?.call(c.maxWidth) ?? children.length;
      final w = math.min((c.maxWidth - gap * (n - 1)) / n, maxWidth);
      return Wrap(
        spacing: gap,
        runSpacing: MuseSpace.s16,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    },
  );
}

/// 外观页的选项卡片：一张现画的预览图，选中时只换边框（主题强调色、加粗），名字在下面。
/// [onTap] 带按下位置（全局坐标），配色切换的揭开从那里开始。
class MuseChoiceCard extends StatelessWidget {
  const MuseChoiceCard({
    super.key,
    this.tapKey,
    required this.label,
    required this.semantics,
    required this.selected,
    required this.aspect,
    required this.onTap,
    required this.child,
  });

  /// key of the tappable part (inside the card's Semantics, as the 1.20.1 cards had it)
  final Key? tapKey;
  final String label;
  final String semantics;
  final bool selected;
  final double aspect;
  final void Function(Offset? at) onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final brand = museBrandOf(context);
    const ring = MuseHomeLookPreview.ring;
    final frame = MuseShape.of(
      MuseRadiusScale.md,
      side: BorderSide(color: selected ? brand : mt.hairline, width: selected ? ring : 1),
    );
    Offset? down;
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: tapKey,
          customBorder: MuseShape.of(MuseRadiusScale.md),
          onTapDown: (d) => down = d.globalPosition,
          onTap: () => onTap(down),
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(shape: frame),
                  child: Padding(
                    // the same inset selected or not, so the preview never shifts
                    padding: const EdgeInsets.all(ring),
                    child: ClipRSuperellipse(
                      borderRadius: MuseShape.all(MuseRadiusScale.md - ring),
                      child: AspectRatio(aspectRatio: aspect, child: child),
                    ),
                  ),
                ),
                const SizedBox(height: MuseSpace.s8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MuseTextLevel.subheadline.style(
                    context,
                    color: selected ? mt.text1 : mt.text2,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一张首页风格的缩略图：页面底 + 已连接的连接卡（状态、连接钮、点阵地图、节点行）+ 下方 2 × 2 卡片，按
/// [look] 的圆角、表面（底色 / 细线 / 投影）、连接钮形状与密度画出来，颜色取当前主题。
class MuseHomeLookPreview extends StatelessWidget {
  const MuseHomeLookPreview({super.key, required this.look, this.map = true});

  final MuseHomeLook look;

  /// 1.20.3: false = 经典首页（连接卡里没有路由图）
  final bool map;

  /// 每张预览最宽
  static const maxWidth = 132.0;

  /// 宽 : 高
  static const aspect = 0.72;

  /// 选中框粗细
  static const ring = 2.0;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: MuseHomeLookPainter(
        look: look,
        map: map,
        page: mt.bgBottom,
        card: mt.card,
        inner: mt.inner,
        line: mt.hairline,
        text1: mt.text1,
        text2: mt.text2,
        linked: museLinkedColor(scheme, mt.card),
        dark: mt.dark,
      ),
    );
  }
}

/// 缩略图画法（一个画布单位 = 预览宽 / [unitsWide]）。只在主题或风格变化时重画。
class MuseHomeLookPainter extends CustomPainter {
  MuseHomeLookPainter({
    required this.look,
    this.map = true,
    required this.page,
    required this.card,
    required this.inner,
    required this.line,
    required this.text1,
    required this.text2,
    required this.linked,
    required this.dark,
  });

  final MuseHomeLook look;
  final bool map;
  final Color page;
  final Color card;
  final Color inner;
  final Color line;
  final Color text1;
  final Color text2;
  final Color linked;
  final bool dark;

  /// 画布按 180 个单位宽来画（约等于把 412 宽的手机首页缩小 2.3 倍）
  static const unitsWide = 180.0;

  /// 细线风格的模式框、方钮、旗帜框圆角（画布单位）
  static const _pillR = 3.0;
  static const _btnR = 4.0;
  static const _flagR = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / unitsWide;
    canvas.drawRect(Offset.zero & size, Paint()..color = page);
    canvas.save();
    canvas.scale(k);
    final h = size.height / k;
    const m = 10.0;
    final r = look.radiusCard * 0.5;
    final lined = look.edge == MuseHomeEdge.line;
    final number = look.kind == MuseHomeLookKind.number;

    void surface(Rect rect, double radius) {
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      if (look.edge == MuseHomeEdge.shadow && !dark) {
        canvas.drawRRect(
          rr.shift(const Offset(0, 2)),
          Paint()
            ..color = text1.withValues(alpha: 0.08)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawRRect(rr, Paint()..color = card);
      if (lined) {
        canvas.drawRRect(
          rr.deflate(0.5),
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / k,
        );
      }
    }

    void bar(double x, double y, double w, double hh, Color c) =>
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, hh), Radius.circular(hh / 2)), Paint()..color = c);

    // ---- 连接卡
    final heroH = !map ? 66.0 : (number ? 124.0 : (lined ? 104.0 : 116.0));
    final hero = Rect.fromLTWH(m, m, unitsWide - m * 2, heroH);
    surface(hero, r);
    final p = look.pad * 0.5;
    final x0 = hero.left + p;
    final x1 = hero.right - p;
    final ink1 = text1.withValues(alpha: 0.85);
    final ink2 = text2.withValues(alpha: 0.55);
    double mapTop;
    switch (look.kind) {
      case MuseHomeLookKind.airy:
        bar(x0, hero.top + p, 48, 10, ink1); // 已连接
        bar(x0, hero.top + p + 16, 26, 5, ink2); // 时长
        bar(x0 + 31, hero.top + p + 14.5, 26, 8, inner); // 模式
        canvas.drawCircle(Offset(x1 - 12, hero.top + p + 12), 12, Paint()..color = inner);
        _pause(canvas, Offset(x1 - 12, hero.top + p + 12), 5, ink1);
        mapTop = hero.top + p + 30;
      case MuseHomeLookKind.line:
        final cy = hero.top + 6 + 8;
        canvas.drawCircle(Offset(x0 + 2.5, cy), 2.5, Paint()..color = linked);
        bar(x0 + 8, cy - 3.5, 30, 7, ink1);
        bar(x0 + 42, cy - 2.5, 18, 5, ink2);
        final pill = RRect.fromRectAndRadius(Rect.fromLTWH(x1 - 50, cy - 5, 28, 10), const Radius.circular(_pillR));
        canvas.drawRRect(
          pill,
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / k,
        );
        final btn = RRect.fromRectAndRadius(Rect.fromLTWH(x1 - 18, cy - 9, 18, 18), const Radius.circular(_btnR));
        canvas.drawRRect(
          btn,
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / k,
        );
        _pause(canvas, btn.center, 4, ink1);
        mapTop = cy + 12;
      case MuseHomeLookKind.number:
        canvas.drawCircle(Offset(x0 + 2, hero.top + p + 3), 2, Paint()..color = linked);
        bar(x0 + 7, hero.top + p, 22, 6, ink2);
        bar(x0 + 33, hero.top + p - 1, 26, 8, inner);
        bar(x0, hero.top + p + 14, 80, 18, ink1); // 大号时长
        bar(x1 - 36, hero.top + p + 14, 36, 18, inner); // 药丸「断开」
        _pause(canvas, Offset(x1 - 26, hero.top + p + 23), 4, ink1);
        bar(x1 - 19, hero.top + p + 20.5, 13, 5, ink2);
        mapTop = hero.top + p + 40;
    }
    // 点阵地图（中间一块节点国家用已连接色）+ 一条弧线；经典首页没有
    if (map) _map(canvas, hero, mapTop, lined);
    _rest(canvas, size, k, h, m, r, hero, x0, x1, ink1, ink2, lined, number, surface, bar);
    canvas.restore();
  }

  void _map(Canvas canvas, Rect hero, double mapTop, bool lined) {
    final mapH = hero.bottom - mapTop - (lined ? 22 : 26);
    final dot = Paint()..color = text1.withValues(alpha: dark ? 0.22 : 0.2);
    final hi = Paint()..color = linked;
    const step = 5.0;
    final hl = Rect.fromLTWH(hero.left + hero.width * 0.62, mapTop + mapH * 0.38, hero.width * 0.2, mapH * 0.34);
    for (var y = mapTop + step / 2; y < mapTop + mapH; y += step) {
      for (var x = hero.left + step / 2; x < hero.right; x += step) {
        // a rough land shape: two blobs
        final u = (x - hero.left) / hero.width;
        final v = (y - mapTop) / mapH;
        final land = (math.pow((u - 0.28) / 0.24, 2) + math.pow((v - 0.45) / 0.42, 2) < 1) ||
            (math.pow((u - 0.72) / 0.2, 2) + math.pow((v - 0.55) / 0.4, 2) < 1);
        if (!land) continue;
        canvas.drawCircle(Offset(x, y), 1.1, hl.contains(Offset(x, y)) ? hi : dot);
      }
    }
    final from = Offset(hero.left + hero.width * 0.3, mapTop + mapH * 0.62);
    final to = hl.center;
    final arc = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo((from.dx + to.dx) / 2, mapTop, to.dx, to.dy);
    canvas.drawPath(
      arc,
      Paint()
        ..color = linked
        ..style = PaintingStyle.stroke
        ..strokeWidth = look.kind == MuseHomeLookKind.line ? 1.0 : 1.4,
    );
  }

  void _rest(
    Canvas canvas,
    Size size,
    double k,
    double h,
    double m,
    double r,
    Rect hero,
    double x0,
    double x1,
    Color ink1,
    Color ink2,
    bool lined,
    bool number,
    void Function(Rect, double) surface,
    void Function(double, double, double, double, Color) bar,
  ) {
    // 节点行
    final rowY = hero.bottom - (lined ? 11 : 13);
    if (lined) {
      canvas.drawLine(Offset(hero.left, rowY - 10), Offset(hero.right, rowY - 10), Paint()..color = line..strokeWidth = 1 / k);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x0 + 6, rowY), width: 12, height: 9), const Radius.circular(_flagR)), Paint()..color = inner);
    } else {
      canvas.drawCircle(Offset(x0 + 7, rowY), 7, Paint()..color = inner);
    }
    bar(x0 + 18, rowY - 3.5, 56, 7, ink1);
    bar(x1 - (number ? 26 : 20), rowY - (number ? 4.5 : 3), number ? 22 : 16, number ? 9 : 6, ink2);

    // ---- 下方 2 × 2 卡片
    final top = hero.bottom + (lined ? 6 : 8);
    final gap = look.mergedGrid ? 0.0 : 6.0;
    // 经典首页连接卡矮，下面多画一排卡片
    final rows = map ? 2 : 3;
    final tileH = math.max(24.0, math.min((h - top - m - gap * (rows - 1)) / rows, look.tile * 0.4));
    final tileW = (hero.width - gap) / 2;
    if (look.mergedGrid) {
      surface(Rect.fromLTWH(hero.left, top, hero.width, tileH * 2), r);
      final rule = Paint()
        ..color = line
        ..strokeWidth = 1 / k;
      canvas.drawLine(Offset(hero.left, top + tileH), Offset(hero.right, top + tileH), rule);
      canvas.drawLine(Offset(hero.left + tileW, top), Offset(hero.left + tileW, top + tileH * 2), rule);
    }
    for (var i = 0; i < rows * 2; i++) {
      final rect = Rect.fromLTWH(hero.left + (i % 2) * (tileW + gap), top + (i ~/ 2) * (tileH + gap), tileW, tileH);
      if (!look.mergedGrid) surface(rect, r);
      final tp = look.tilePadH * 0.5;
      bar(rect.left + tp, rect.top + tp * 0.8, 18, 4, ink2);
      final vh = look.value * 0.36;
      bar(rect.left + tp, rect.top + tileH * 0.42, 22 + look.value * 0.6, vh, ink1);
      if (i == 0) {
        // 网速图：细线 = 细柱，其余 = 折线
        final y = rect.bottom - tp * 0.8;
        if (look.sparkBars) {
          for (var j = 0; j < 9; j++) {
            final bh = 1.5 + (j * 37 % 11) / 11 * 5;
            canvas.drawRect(Rect.fromLTWH(rect.left + tp + j * 5, y - bh, 3, bh), Paint()..color = linked.withValues(alpha: 0.7));
          }
        } else {
          canvas.drawLine(
            Offset(rect.left + tp, y),
            Offset(rect.right - tp, y - 5),
            Paint()
              ..color = linked
              ..strokeWidth = 1.2,
          );
        }
      }
    }
  }

  void _pause(Canvas canvas, Offset c, double s, Color color) {
    final p = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(c.dx - s * 0.6, c.dy - s * 0.7, s * 0.4, s * 1.4), p);
    canvas.drawRect(Rect.fromLTWH(c.dx + s * 0.2, c.dy - s * 0.7, s * 0.4, s * 1.4), p);
  }

  @override
  bool shouldRepaint(MuseHomeLookPainter old) =>
      old.look != look ||
      old.map != map ||
      old.page != page ||
      old.card != card ||
      old.inner != inner ||
      old.line != line ||
      old.text1 != text1 ||
      old.text2 != text2 ||
      old.linked != linked ||
      old.dark != dark;
}
