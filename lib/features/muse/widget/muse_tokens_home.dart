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
  static const unit = 14.0;

  /// 节点行延迟数字（单位用 13）
  static const delay = 15.0;

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
