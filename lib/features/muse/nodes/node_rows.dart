// 穿云 - node list: node rows (lazily built sections, row reuse by input, protocol tag, flag box). Split out of node_list.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'node_list.dart';

/// 1.6.0 C11: the slot of one row in a lazily built section (found again after the order changes).
class _NodeSlotKey extends LocalKey {
  const _NodeSlotKey(this.row);
  final Key row;

  @override
  bool operator ==(Object other) => other is _NodeSlotKey && other.row == row;

  @override
  int get hashCode => Object.hash(_NodeSlotKey, row);
}

/// 1.6.0 C11: the rows built for one set of list-wide inputs, by node tag.
class _NodeRowMemo {
  _NodeRowMemo(this.scope);
  final Object? scope;
  final rows = <String, (Object, Widget)>{};
}

/// One card of node rows with an optional caption above.
class _NodeSection extends StatelessWidget {
  const _NodeSection({super.key, this.header, required this.margin, required this.children, this.collapsed, this.onHeaderTap});

  final String? header;
  final double margin;
  final List<Widget> children;

  /// null = not foldable
  final bool? collapsed;
  final VoidCallback? onHeaderTap;

  Widget _header(BuildContext context) {
    final mt = MuseTheme.of(context);
    return InkWell(
      onTap: onHeaderTap,
      borderRadius: MuseRadius.smallAll,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s4, MuseSpace.s16, MuseSpace.s8),
        child: Row(
          children: [
            Expanded(child: Text(header!, style: MuseType.caption(context))),
            if (collapsed != null)
              Icon(
                collapsed! ? Icons.expand_more_outlined : Icons.expand_less_outlined,
                size: MuseIconSize.tiny,
                color: mt.text3,
              ),
          ],
        ),
      ),
    );
  }

  /// 1.5.0 #22: the same section as a sliver whose rows are built only when scrolled into view.
  Widget buildSliver(BuildContext context, {int columns = 1, double extent = 0}) {
    final mt = MuseTheme.of(context);
    final last = children.length - 1;
    // 1.6.0 C11: when the order changes (a new delay under 按延迟), a row keeps its element and moves
    // instead of every row after it being rebuilt in its new slot
    final slots = <Key, int>{for (var i = 0; i < children.length; i++) ?children[i].key: i};
    // (a key seen twice would clash: then the rows stay in plain index slots)
    final unique = slots.length == children.where((c) => c.key != null).length;
    int? findSlot(Key key) => key is _NodeSlotKey ? slots[key.row] : null;
    Widget slot(int i, Widget child) {
      final k = children[i].key;
      return k == null || !unique ? child : KeyedSubtree(key: _NodeSlotKey(k), child: child);
    }
    if (columns > 1 && children.isNotEmpty) {
      return SliverPadding(
        key: key,
        padding: EdgeInsets.fromLTRB(margin, MuseSpace.s8, margin, 0),
        sliver: SliverMainAxisGroup(
          slivers: [
            if (header != null) SliverToBoxAdapter(child: _header(context)),
            SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: extent,
                crossAxisSpacing: MuseSpace.s8,
                mainAxisSpacing: MuseSpace.s8,
              ),
              itemCount: children.length,
              findChildIndexCallback: findSlot,
              itemBuilder: (context, i) => slot(
                i,
                DecoratedBox(
                  key: const ValueKey('node_card'),
                  decoration: mt.cardDecoration(),
                  child: ClipRSuperellipse(
                    borderRadius: MuseRadius.cardAll,
                    child: Material(type: MaterialType.transparency, child: Center(child: children[i])),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    const top = BorderRadius.vertical(top: Radius.circular(MuseRadius.card));
    const bottom = BorderRadius.vertical(bottom: Radius.circular(MuseRadius.card));
    return SliverPadding(
      key: key,
      padding: EdgeInsets.fromLTRB(margin, MuseSpace.s8, margin, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          if (header != null) SliverToBoxAdapter(child: _header(context)),
          if (children.isNotEmpty)
            DecoratedSliver(
              decoration: mt.cardDecoration(),
              sliver: SliverList.builder(
                itemCount: children.length,
                findChildIndexCallback: findSlot,
                itemBuilder: (context, i) {
                  Widget row = Material(
                    type: MaterialType.transparency,
                    child: i == last
                        ? children[i]
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              children[i],
                              Divider(height: MuseSize.hairline, thickness: MuseSize.hairline, indent: MuseSize.rowIndent, color: mt.hairline),
                            ],
                          ),
                  );
                  // the first / last row keeps the card's rounded corners (selected background, splash)
                  if (i == 0 || i == last) {
                    row = ClipRSuperellipse(borderRadius: i == 0 && i == last ? MuseRadius.cardAll : (i == 0 ? top : bottom), child: row);
                  }
                  return slot(i, row);
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) items.add(Divider(height: MuseSize.hairline, thickness: MuseSize.hairline, indent: MuseSize.rowIndent, color: mt.hairline));
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, MuseSpace.s8, margin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            InkWell(
              onTap: onHeaderTap,
              borderRadius: MuseRadius.smallAll,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s4, MuseSpace.s16, MuseSpace.s8),
                child: Row(
                  children: [
                    Expanded(child: Text(header!, style: MuseType.caption(context))),
                    if (collapsed != null)
                      Icon(
                        collapsed! ? Icons.expand_more_outlined : Icons.expand_less_outlined,
                        size: MuseIconSize.tiny,
                        color: mt.text3,
                      ),
                  ],
                ),
              ),
            ),
          if (items.isNotEmpty)
          DecoratedBox(
            decoration: mt.cardDecoration(),
            child: ClipRSuperellipse(
              borderRadius: MuseRadius.cardAll,
              child: Material(type: MaterialType.transparency, child: Column(children: items)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One node: flag | name + protocol | status dot + latency (right-aligned, tabular).
/// Selected = light-blue background with a 4 px blue bar on the left.
class MuseNodeRow extends StatelessWidget {
  const MuseNodeRow({
    super.key,
    required this.proxy,
    required this.since,
    required this.nodeCount,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.testStarted,
    this.cachedDelay,
    this.dimmed = false,
    this.favorite = false,
    this.displayName,
    this.note = '',
    this.checked,
    this.shownPick,
    this.region,
    this.padV = MuseSpace.s12,
  });

  /// 1.6.0 C5: vertical padding (紧凑 / 标准 / 宽松)
  final double padV;

  /// 1.6.0 #32: region set by hand (ISO code; null / '' = from the name)
  final String? region;

  /// 1.5.3: a group's pick as its row shows it
  final String Function(String raw)? shownPick;

  /// 1.4.0: the user's own name (or the tidied one) instead of the subscription's
  final String? displayName;
  final String note;

  /// 1.4.1 多选: null = not selecting, else whether this row is picked
  final bool? checked;
  final OutboundInfo proxy;
  final DateTime? since;
  final DateTime? testStarted;
  final int? cachedDelay;
  final bool dimmed;
  final int nodeCount;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 1.6.0 C11: how many times a row was built (the rebuild-count test reads it).
  @visibleForTesting
  static int debugBuilds = 0;

  @override
  Widget build(BuildContext context) {
    debugBuilds++;
    final mt = MuseTheme.of(context);
    final view = museDelayView(
      delay: proxy.urlTestDelay,
      testedAt: proxy.hasUrlTestTime() ? proxy.urlTestTime.toDateTime() : null,
      since: since,
      testStarted: proxy.isGroup ? null : testStarted,
      cached: cachedDelay,
    );
    final delayText = view.text;
    final stale = view.kind != MuseDelayKind.live && view.kind != MuseDelayKind.timeout;
    final Color delayColor = switch (view.kind) {
      MuseDelayKind.live => MuseColors.delay(context, view.delay),
      MuseDelayKind.timeout => MusePalette.red,
      // 1.5.0: untested / cached delays in the secondary grey (tertiary is for icons only)
      _ => mt.text2,
    };
    final fullName = displayName ?? museNodeName(proxy);
    final rawName = proxy.isGroup ? fullName.split(' → ').first.trim() : fullName;
    final type = proxy.type.toLowerCase();
    final name = proxy.isGroup || type == 'direct' || type == 'block' ? museGroupName(rawName) : rawName;
    final invalid = !proxy.isGroup && museIsInvalidNodeType(proxy.type);
    // 1.5.3: the protocol is a small tag after the name; the second line only says something new
    final protocolTag = proxy.isGroup || invalid || type == 'direct' || type == 'block' ? null : museProtocolShort(proxy.type);
    final subtitle = proxy.isGroup
        ? museGroupSubtitle(
            type: proxy.type,
            name: rawName,
            selectedDisplay: proxy.groupSelectedTagDisplay,
            nodeCount: nodeCount,
            shown: shownPick == null ? null : (raw) => museStripFlags(shownPick!(raw)),
          )
        : invalid
        ? museInvalidNodeSubtitle(proxy.type)
        : note;
    final groupIcon = proxy.isGroup
        ? switch (museGroupIconKind(type: proxy.type, name: rawName, selectedDisplay: proxy.groupSelectedTagDisplay)) {
            MuseGroupIcon.autoFastest => Icons.bolt_outlined,
            MuseGroupIcon.loadBalance => Icons.balance_outlined,
            MuseGroupIcon.manual => Icons.touch_app_outlined,
            MuseGroupIcon.fallback => Icons.alt_route_outlined,
            MuseGroupIcon.other => Icons.folder_outlined,
          }
        : Icons.public_outlined;
    final own = region ?? '';
    final flag = proxy.isGroup
        ? null
        : own.isNotEmpty
        ? museCountryFlag(own)
        : (museFlagEmoji(name) ?? museFlagEmoji(museNodeName(proxy)));

    final row = Material(
      color: selected ? mt.selected : MusePalette.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: MuseSpace.s16, vertical: padV),
              child: Row(
                children: [
                  if (checked != null)
                    SizedBox(
                      key: ValueKey('node_check_${proxy.tag}'),
                      width: MuseSize.flagBox,
                      height: MuseSize.flagBox,
                      child: Icon(
                        checked! ? Icons.check_circle_outlined : Icons.radio_button_unchecked_outlined,
                        color: checked! ? museBrandOf(context) : mt.text3,
                      ),
                    )
                  else
                    MuseFlagBox(flag: flag, icon: groupIcon, neutral: !proxy.isGroup),
                  const SizedBox(width: MuseSpace.s12),
                  Expanded(
                    // 1.5.3: the tag only when the name keeps most of the row (narrow + large
                    // text: the protocol goes back to the second line)
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final tagWidth = protocolTag == null ? 0.0 : MuseProtocolTag.widthOf(context, protocolTag);
                        final showTag = protocolTag != null && tagWidth <= box.maxWidth * MuseSize.protocolTagShare;
                        final line2 = protocolTag != null && !showTag
                            ? (subtitle.isEmpty ? protocolTag : '$protocolTag · $subtitle')
                            : subtitle;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (favorite)
                                  const Padding(
                                    padding: EdgeInsets.only(right: MuseSpace.s4),
                                    child: Icon(Icons.star_rounded, size: MuseIconSize.tiny, color: MusePalette.star, key: ValueKey('node_star')),
                                  ),
                                Flexible(
                                  child: Text(
                                    flag == null ? name : museStripFlags(name),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MuseType.body(context).copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                                  ),
                                ),
                                if (showTag) ...[
                                  const SizedBox(width: MuseSpace.s8),
                                  MuseProtocolTag(text: protocolTag),
                                ],
                              ],
                            ),
                            if (line2.isNotEmpty)
                              Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.caption(context)),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: MuseSpace.s8),
                  AnimatedContainer(
                    duration: museMotion(context),
                    width: MuseSize.dot,
                    height: MuseSize.dot,
                    decoration: BoxDecoration(color: delayColor, shape: BoxShape.circle),
                  ),
                  SizedBox(
                    width: MuseSize.latencyColumn,
                    child: AnimatedSwitcher(
                      duration: museMotion(context),
                      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.centerRight, children: [...previous, ?current]),
                      child: Text(
                        delayText,
                        key: ValueKey(delayText),
                        textAlign: TextAlign.right,
                        style: MuseType.body(context).copyWith(color: stale ? mt.text2 : mt.text1, fontFeatures: MuseType.tabular),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 1.6.1: a short rounded accent mark (the row itself is filled with the tonal
            // selected colour) instead of a full-height bar
            if (selected)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SizedBox(
                    width: MuseSize.selectedBar,
                    height: MuseSize.selectedMark,
                    child: DecoratedBox(
                      key: const ValueKey('node_selected_bar'),
                      decoration: ShapeDecoration(color: museBrandOf(context), shape: MuseShape.full),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return dimmed ? Opacity(opacity: 0.55, child: row) : row;
  }
}

/// 1.5.3: the protocol as a small grey tag (instead of a whole second line).
class MuseProtocolTag extends StatelessWidget {
  const MuseProtocolTag({super.key, required this.text});

  final String text;

  /// laid-out width at the current text scale
  static double widthOf(BuildContext context, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: MuseType.caption(context)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width + MuseSpace.s4 * 2 + MuseSpace.s8;
    tp.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    return Container(
      key: const ValueKey('node_protocol_tag'),
      padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s4),
      decoration: BoxDecoration(color: mt.inner, borderRadius: MuseRadius.smallAll),
      child: Text(text, maxLines: 1, softWrap: false, style: MuseType.caption(context)),
    );
  }
}

/// 32 dp rounded square with a flag emoji (or an icon for groups).
class MuseFlagBox extends StatelessWidget {
  const MuseFlagBox({super.key, this.flag, this.icon = Icons.public_outlined, this.onBrand = false, this.neutral = false});

  final String? flag;
  final IconData icon;

  /// 1.5.3: a node without a known region: grey icon (the brand colour is for groups)
  final bool neutral;

  /// on the blue hero card
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    return Container(
      width: MuseSize.flagBox,
      height: MuseSize.flagBox,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onBrand ? mt.onHero.withValues(alpha: 0.1) : mt.inner,
        borderRadius: MuseRadius.smallAll,
      ),
      child: flag != null
          ? Text(flag!, style: const TextStyle(fontSize: MuseIconSize.flag, height: 1.1))
          : Icon(
              icon,
              key: neutral ? const ValueKey('flag_box_neutral') : null,
              size: MuseIconSize.small,
              color: onBrand ? mt.onHero : (neutral ? mt.text3 : museBrandOf(context)),
            ),
    );
  }
}
