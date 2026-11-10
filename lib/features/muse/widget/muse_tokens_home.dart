// 穿云 1.20.0 首页方向 A（连接卡 + 地图融合，留白）的设计令牌：圆角 20 / 12 / 8、4 / 8 间距、56 圆形连接钮、
// 数字与单位分开排、连接卡地图的点阵与取景取值。首页的连接卡、下方卡片与电脑版连接卡都只用这里的数。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';

abstract final class MuseHomeA {
  // ---- 圆角：卡片 / 面板 / 控件
  static const radiusCard = 20.0;
  static const radiusPanel = 12.0;
  static const radiusControl = 8.0;
  static const cardAll = BorderRadius.all(Radius.circular(radiusCard));

  // ---- 间距（4 / 8 网格）
  /// 卡片内边距：手机 20，电脑版连接卡 24
  static const pad = 20.0;
  static const padDesk = 24.0;

  /// 连接卡右侧比左侧少 4（圆钮视觉上已有留白）
  static const padEndTrim = 4.0;

  /// 卡片之间
  static const gap = 12.0;

  /// 节点行：上 4、下 16、右侧给箭头让 8
  static const nodeRowTop = 4.0;
  static const nodeRowBottom = 16.0;
  static const nodeRowEndTrim = 8.0;

  // ---- 连接卡
  /// 圆形连接钮（▶ 已连接色、❚❚ 正文色、中性底）
  static const button = 56.0;
  static const buttonGlyph = 28.0;

  /// 规则 / 全局模式胶囊
  static const pill = 28.0;
  static const pillIcon = 16.0;

  /// 节点旗帜圆框与旗帜字号
  static const flagBox = 36.0;
  static const flag = 18.0;

  /// 延迟前的小圆点
  static const delayDot = 6.0;

  // ---- 数字：数字大、单位小一号且是次要色（不换行空格连着）
  static const value = 26.0;
  static const valueTrack = -0.3;
  static const valueLine = 1.15;

  /// 1.20.1 细线 / 数字风格的小号状态字行高
  static const statusLine = 1.25;
  static const unit = 14.0;

  /// 节点行延迟数字（单位用 13）
  static const delay = 15.0;

  /// 1.20.1：节点行延迟数字随系统字号最多放大这么多倍（三种风格）
  static const delayMaxScale = 1.3;

  /// 1.20.1 细线风格：节点名那一栏至少这么宽（随字号放大）才在名字后面显示协议小标签
  static const tagRoom = 180.0;

  /// 1.20.1 细线风格：协议小标签左右内边距
  static const tagPadH = 6.0;

  /// 卡片高度里数值那一行（[value] × [valueLine]）与标题那一行（13 / 18）
  static const valueBox = value * valueLine;
  static const titleBox = 18.0;

  /// 下方卡片的最小高度（手机 / 宽于 600）——系统大字号时按内容长高，不固定
  static const tile = 124.0;
  static const tileDesk = 136.0;

  // ---- 连接卡地图
  /// 地图高度 = 卡宽 / [mapAspect]，夹在 [mapMin]–[mapMax]
  static const mapAspect = 2.6;
  static const mapMin = 148.0;
  static const mapMax = 220.0;

  /// 点阵透明度（正文色上）
  static const dotAlphaLight = 0.20;
  static const dotAlphaDark = 0.22;

  /// 点半径占格距的比例（1.19 路由卡为 0.32）与细点的下限
  static const dotShare = 0.24;
  /// 1.20.1：0.9 → 0.7（格距 ≥ 2.9 px 时不抽稀，新加坡、荷兰这类取景回到全密度）
  static const dotMinRadius = 0.7;

  /// 节点所在国家的点比底图点大这么多倍（底图点下限之上）；且至少占格距的 [highlightShare]，德国、日本这类
  /// 小国在大跨度取景里也连成一片看得清
  static const highlightScale = 1.18;
  static const highlightShare = 0.34;

  /// 节点所在国家的颜色与卡片底色的对比度至少这么多（不够时向正文色加深）
  static const highlightContrast = 3.6;

  static const arcWidth = 1.5;
  static const endDot = 3.0;
  static const endRing = 1.5;
  static const mapLabel = 13.0;

  /// 取景：内容最北端在地图高度的 26 % 处、内容最多占地图高度的 50 %、经度跨度至少 64°（日本、韩国这类近处
  /// 小国也放得够大，点阵看得清）
  static const fitTop = 0.26;
  static const fitFill = 0.5;
  static const fitMinSpan = 64.0;

  /// 未连接整幅世界的中央经线（东经 150°：中国、日本、美国本土连阿拉斯加、欧洲都在框内不被切）
  static const centerLon = 150.0;

  /// 底图上没有独立国土的地区（香港、新加坡、澳门……）：高亮出口城市这么多度以内的陆地点
  static const nearCityDeg = 3.5;

  /// 1.20.1：国家高亮在屏幕上至少要有这么多个点、外接框至少这么多像素，不够时点亮出口城市 [hlNearPx] 像素内的陆地点
  static const hlMinDots = 5;
  static const hlMinPx = 14.0;
  static const hlNearPx = 7.0;

  /// 1.20.1：小国改用 1:50m 细网格时点半径占细格距的比例
  static const fineShare = 0.42;

  /// 地图顶部、底部点阵淡出（只压底图点阵，弧线与端点不受影响）
  static const maskStops = [0.0, 0.24, 0.78, 1.0];
  static const maskAlpha = [0.0, 1.0, 1.0, 0.0];

  /// 遮罩只用透明度（颜色本身不显示）
  static const maskInk = Color(0xFF000000);
}

// ---------------------------------------------------------------- 1.20.1 三种首页风格

/// 1.20.1 外观 › 首页风格。留白 = 1.20.0 的首页（[MuseHomeA]）；细线 = 工具式（1 px 细线分层、高密度、下方卡片
/// 合成一块细线分格面板）；数字 = 金融式（大号已连接时长、带中文动词的药丸按钮、柔和投影）。三种风格结构相同：
/// 地图、节点行、卡片内容与顺序一样，只换表面、圆角、密度与字阶。
enum MuseHomeLookKind {
  airy('airy', '留白', '大留白，只靠表面分层'),
  line('line', '细线', '细分隔线，信息更密'),
  number('number', '数字', '大号时长，药丸按钮');

  const MuseHomeLookKind(this.key, this.title, this.describe);

  final String key;
  final String title;
  final String describe;

  static MuseHomeLookKind fromKey(String? key) =>
      values.firstWhere((e) => e.key == key, orElse: () => MuseHomeLookKind.airy);
}

/// 卡片怎么和页面分开：留白只靠底色；细线 1 px 细线；数字柔和投影（深色下投影看不见，靠底色）
enum MuseHomeEdge { fill, line, shadow }

/// 连接钮的形状：留白 56 圆形、细线 40 方钮（细线框）、数字 44 高药丸（图标 + 「连接 / 断开」）
enum MuseHomeButton { circle, square, pill }

@immutable
class MuseHomeLook {
  const MuseHomeLook({
    required this.kind,
    required this.radiusCard,
    required this.radiusControl,
    required this.edge,
    required this.pad,
    required this.padDesk,
    required this.headTop,
    required this.tilePadH,
    required this.tilePadV,
    required this.value,
    required this.valueTrack,
    required this.unit,
    required this.tile,
    required this.tileDesk,
    required this.titleWeight,
    required this.status,
    required this.statusWeight,
    required this.statusDot,
    required this.uptime,
    required this.uptimeWeight,
    required this.uptimeTrack,
    required this.button,
    required this.buttonSize,
    required this.buttonGlyph,
    required this.pill,
    required this.delay,
    required this.mergedGrid,
    required this.sparkBars,
  });

  final MuseHomeLookKind kind;

  /// 卡片 / 控件圆角
  final double radiusCard;
  final double radiusControl;
  final MuseHomeEdge edge;

  /// 连接卡左右内边距（手机 / 电脑）与顶部内边距
  final double pad;
  final double padDesk;
  final double headTop;

  /// 下方卡片内边距（横 / 竖）
  final double tilePadH;
  final double tilePadV;

  /// 卡片数值：数字字号、字距与单位字号
  final double value;
  final double valueTrack;
  final double unit;

  /// 下方卡片最小高度（手机 / 宽于 600），系统大字号时按内容长高
  final double tile;
  final double tileDesk;

  /// 下方卡片标题字重
  final FontWeight titleWeight;

  /// 连接卡状态字（「已连接」）字号、字重；状态前小圆点直径（0 = 不画）
  final double status;
  final FontWeight statusWeight;
  final double statusDot;

  /// 已连接时长字号、字重、字距
  final double uptime;
  final FontWeight uptimeWeight;
  final double uptimeTrack;

  final MuseHomeButton button;

  /// 圆形 / 方钮边长，药丸高度
  final double buttonSize;
  final double buttonGlyph;

  /// 规则 / 全局模式胶囊高度
  final double pill;

  /// 节点行延迟数字字号
  final double delay;

  /// 细线：下方卡片合成一块分格面板（格间 1 px 细线，没有卡片间距）
  final bool mergedGrid;

  /// 细线：网速图画成细柱
  final bool sparkBars;

  /// 卡片之间（三种风格相同）
  double get gap => MuseHomeA.gap;

  /// 卡片高度里数值那一行
  double get valueBox => value * MuseHomeA.valueLine;

  BorderRadius get cardAll => BorderRadius.all(Radius.circular(radiusCard));

  /// 卡片的外观：底色（留白，与 1.20.0 同一个 BoxDecoration）+ （细线）1 px 细线 / （数字，浅色）柔和投影
  Decoration card({required Color color, required Color line, required bool dark}) => edge == MuseHomeEdge.fill
      ? BoxDecoration(color: color, borderRadius: cardAll)
      : ShapeDecoration(
          color: color,
          shape: RoundedSuperellipseBorder(
            borderRadius: cardAll,
            side: edge == MuseHomeEdge.line ? BorderSide(color: line) : BorderSide.none,
          ),
          shadows: edge == MuseHomeEdge.shadow && !dark ? softShadow : null,
        );

  /// 数字风格的柔和投影：贴边 1 px + 远处 24 px 大模糊（都有偏移，不是零偏移光晕）
  static const softShadow = [
    BoxShadow(color: Color(0x0A101828), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0F101828), offset: Offset(0, 8), blurRadius: 24, spreadRadius: -4),
  ];

  /// 留白 = 1.20.0 的首页，取值就是 [MuseHomeA]
  static const airy = MuseHomeLook(
    kind: MuseHomeLookKind.airy,
    radiusCard: MuseHomeA.radiusCard,
    radiusControl: MuseHomeA.radiusControl,
    edge: MuseHomeEdge.fill,
    pad: MuseHomeA.pad,
    padDesk: MuseHomeA.padDesk,
    headTop: MuseHomeA.pad,
    tilePadH: MuseHomeA.pad,
    tilePadV: MuseHomeA.pad,
    value: MuseHomeA.value,
    valueTrack: MuseHomeA.valueTrack,
    unit: MuseHomeA.unit,
    tile: MuseHomeA.tile,
    tileDesk: MuseHomeA.tileDesk,
    titleWeight: FontWeight.w400,
    status: 28,
    statusWeight: FontWeight.w600,
    statusDot: 0,
    uptime: 15,
    uptimeWeight: FontWeight.w400,
    uptimeTrack: 0,
    button: MuseHomeButton.circle,
    buttonSize: MuseHomeA.button,
    buttonGlyph: MuseHomeA.buttonGlyph,
    pill: MuseHomeA.pill,
    delay: MuseHomeA.delay,
    mergedGrid: false,
    sparkBars: false,
  );

  /// 细线：圆角 12 / 6、内边距 16、单行状态头（点 + 状态 + 时长 + 模式 + 40 方钮）、数值 20、格高 96
  static const line = MuseHomeLook(
    kind: MuseHomeLookKind.line,
    radiusCard: 12,
    radiusControl: 6,
    edge: MuseHomeEdge.line,
    pad: 16,
    padDesk: 20,
    headTop: 12,
    tilePadH: 16,
    tilePadV: 12,
    value: 20,
    valueTrack: 0,
    unit: 13,
    tile: 96,
    tileDesk: 104,
    titleWeight: FontWeight.w600,
    status: 17,
    statusWeight: FontWeight.w600,
    statusDot: 8,
    uptime: 13,
    uptimeWeight: FontWeight.w400,
    uptimeTrack: 0,
    button: MuseHomeButton.square,
    buttonSize: 40,
    buttonGlyph: 22,
    pill: 28,
    delay: 13,
    mergedGrid: true,
    sparkBars: true,
  );

  /// 数字：圆角 24 / 全圆、内边距 20、40 号已连接时长、44 高药丸按钮、数值 30、格高 132
  static const number = MuseHomeLook(
    kind: MuseHomeLookKind.number,
    radiusCard: 24,
    radiusControl: 999, // = MuseRadius.full
    edge: MuseHomeEdge.shadow,
    pad: 20,
    padDesk: 24,
    headTop: 20,
    tilePadH: 20,
    tilePadV: 20,
    value: 30,
    valueTrack: -0.6,
    unit: 15,
    tile: 132,
    tileDesk: 140,
    titleWeight: FontWeight.w600,
    status: 13,
    statusWeight: FontWeight.w600,
    statusDot: 6,
    uptime: 40,
    uptimeWeight: FontWeight.w500,
    uptimeTrack: -1,
    button: MuseHomeButton.pill,
    buttonSize: 44,
    buttonGlyph: 20,
    pill: 32,
    delay: 20,
    mergedGrid: false,
    sparkBars: false,
  );

  static MuseHomeLook of(MuseHomeLookKind kind) => switch (kind) {
    MuseHomeLookKind.airy => airy,
    MuseHomeLookKind.line => line,
    MuseHomeLookKind.number => number,
  };

  static MuseHomeLook fromKey(String? key) => of(MuseHomeLookKind.fromKey(key));
}
