// 穿云 1.5.1 - the one pill segmented control (首页 去广告 关 / 温和 / 强力, 统计 日 / 周 / 月).
// Equal-width segments, label centred both ways (even leading, height 1 — no CJK baseline offset),
// the selected pill fills its segment with the same inset on every side, height scales with text.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

/// Key of segment [index] inside a [MuseSegmented] (for tests / smoke).
ValueKey<String> museSegmentKey(int index) => ValueKey('muse_seg_$index');

/// Line metrics for a segment label: the em box is centred in the line box.
const museSegmentTextHeight = TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even);

/// A small pill segmented control.
class MuseSegmented<T> extends StatelessWidget {
  const MuseSegmented({super.key, required this.values, required this.selected, required this.label, required this.onChanged});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  /// Height at [scaler]: never under [MuseSize.segmented], grows with the text.
  static double heightFor(TextScaler scaler) => scaler.scale(MuseSize.segmented);

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    return SizedBox(
      height: heightFor(MediaQuery.textScalerOf(context)),
      child: DecoratedBox(
        decoration: BoxDecoration(color: mt.inner, borderRadius: MuseRadius.fullAll),
        child: Padding(
          padding: const EdgeInsets.all(MuseSpace.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: _Segment(
                    key: museSegmentKey(i),
                    text: label(values[i]),
                    selected: values[i] == selected,
                    onTap: () => onChanged(values[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({super.key, required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: museMotion(context),
            curve: MuseMotion.curve,
            decoration: BoxDecoration(
              color: selected ? (mt.dark ? museBrandOf(context) : MusePalette.white) : MusePalette.transparent,
              borderRadius: MuseRadius.fullAll,
              boxShadow: selected && !mt.dark ? [BoxShadow(color: mt.shadowColor, blurRadius: MuseSpace.s4, offset: const Offset(0, 1))] : null,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s4),
                // a too-narrow segment shrinks the label instead of overflowing / clipping it
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    textHeightBehavior: museSegmentTextHeight,
                    style: MuseType.caption(context).copyWith(
                      height: 1,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? (mt.dark ? MusePalette.white : museBrandOf(context)) : mt.text2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
