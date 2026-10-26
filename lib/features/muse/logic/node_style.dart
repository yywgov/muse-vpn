// 穿云 1.6.0 C5 - 节点 page style: 列表 / 卡片 layout, 紧凑 / 标准 / 宽松 density, card columns.
// Part of 穿云 (GPLv3).

import 'dart:math' as math;

import 'package:hiddify/features/muse/widget/muse_tokens.dart';

enum MuseNodeLayout {
  list('list', '列表'),
  grid('grid', '卡片');

  const MuseNodeLayout(this.key, this.title);

  final String key;
  final String title;

  static MuseNodeLayout fromKey(String k) => values.where((e) => e.key == k).firstOrNull ?? list;
}

enum MuseNodeDensity {
  compact('compact', '紧凑', MuseSpace.s8),
  standard('standard', '标准', MuseSpace.s12),
  loose('loose', '宽松', MuseSpace.s16);

  const MuseNodeDensity(this.key, this.title, this.padV);

  final String key;
  final String title;

  /// vertical padding of a node row / card
  final double padV;

  static MuseNodeDensity fromKey(String k) => values.where((e) => e.key == k).firstOrNull ?? standard;
}

/// A card is at least this wide (at 1× text).
const museNodeCardMinWidth = 150.0;

/// Card columns for a content [width]: one per 250 px (at least 2), one more when 紧凑, one less when
/// 宽松, never narrower than [museNodeCardMinWidth] × [textScale].
int museNodeColumns(double width, MuseNodeDensity density, {double textScale = 1, double gap = MuseSpace.s8}) {
  var c = math.max((width / 250).ceil(), 2);
  c += switch (density) {
    MuseNodeDensity.compact => 1,
    MuseNodeDensity.standard => 0,
    MuseNodeDensity.loose => -1,
  };
  c = math.max(c, 1);
  while (c > 1 && (width - gap * (c - 1)) / c < museNodeCardMinWidth * textScale) {
    c--;
  }
  return c;
}

/// Height of one node card: two text lines (name 15, caption 12, line height 1.3) or the flag box,
/// whichever is taller, plus the density's padding.
double museNodeCardExtent(MuseNodeDensity density, double Function(double) scale) =>
    math.max(MuseSize.flagBox, scale((15 + 12) * 1.3)) + density.padV * 2 + MuseSpace.s4;
