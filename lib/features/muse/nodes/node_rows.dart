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
  const _NodeSection({
    super.key,
    this.header,
    required this.margin,
    required this.children,
    this.collapsed,
    this.onHeaderTap,
    this.asList = false,
    this.selfDecorated = false,
  });

  /// 1.11.0: always one column of rows (groups that do not fit the mode bar)
  final bool asList;

  /// 1.11.0 (A): each child draws its own card (selected fill / outline), no card box around it
  final bool selfDecorated;

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
    final cols = asList ? 1 : columns;
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
    if ((cols > 1 || selfDecorated) && children.isNotEmpty) {
      return SliverPadding(
        key: key,
        padding: EdgeInsets.fromLTRB(margin, MuseSpace.s8, margin, 0),
        sliver: SliverMainAxisGroup(
          slivers: [
            if (header != null) SliverToBoxAdapter(child: _header(context)),
            SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisExtent: extent,
                crossAxisSpacing: MuseSpace.s8,
                mainAxisSpacing: MuseSpace.s8,
              ),
              itemCount: children.length,
              findChildIndexCallback: findSlot,
              itemBuilder: (context, i) => selfDecorated
                  ? slot(i, children[i])
                  : slot(
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

/// One node: flag | name + protocol | latency (right-aligned, tabular, coloured by speed; 1.10.0: no
/// status dot).
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
      reason: proxy.urlTestError,
    );
    final delayText = view.text;
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
                                    style: MuseType.body(context).copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400, fontFamily: MuseFont.family),
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
                  // 1.10.0: no status dot; the number itself is coloured by speed (超时 in red)
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
                        style: MuseType.body(context).copyWith(color: delayColor, fontFeatures: MuseType.tabular, fontFamily: MuseFont.family),
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

/// 1.5.3: the protocol as a small grey tag (instead of a whole second line). 1.10.0: plain tertiary text.
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
    // 1.10.0: weaker — plain small text in the secondary grey, no filled box (the tertiary grey is
    // for icons only: too little contrast for text, #83)
    return Padding(
      key: const ValueKey('node_protocol_tag'),
      padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s4),
      child: Text(text, maxLines: 1, softWrap: false, style: MuseType.caption(context).copyWith(color: mt.text2)),
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

// ======================================================================= 1.11.0 节点 A 双列卡片

/// 1.11.0: height of a [MuseNodeCard] at [scale] (padding + region line + name + bottom row; the
/// text parts grow with the system font size).
double museNodeCardExtentA(double Function(double) scale) => MuseSpace.s12 * 2 + MuseSpace.s4 * 2 + scale(16 + 20 + 18);

/// 1.11.0: columns of cards for a list [width] wide (two on a phone; one only when very narrow).
int museNodeColumnsA(double width, {double textScale = 1}) {
  final min = MuseSize.nodeCardMinWidth * textScale.clamp(1.0, 1.6);
  final n = ((width + MuseSpace.s8) / (min + MuseSpace.s8)).floor();
  return n.clamp(1, 6);
}

/// 1.11.0: a delay split for the card: the number (coloured) and its unit, or a word (测速中 / 超时 / —).
({String number, String unit}) museDelayParts(MuseDelayView view) => switch (view.kind) {
  MuseDelayKind.live || MuseDelayKind.cached => (number: '${view.delay}', unit: 'ms'),
  _ => (number: view.text, unit: ''),
};

/// 1.11.0 (A): one node as a card — flag + region (small), the name (bold), the protocol as a
/// small tag and the delay bottom right (number coloured by speed, small grey 「ms」). Selected =
/// tonal accent fill + accent outline + a round tick top right. [inUse] = the node a group (自动最快 /
/// 负载均衡) is using right now: outline only.
class MuseNodeCard extends StatelessWidget {
  const MuseNodeCard({
    super.key,
    required this.proxy,
    required this.since,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.testStarted,
    this.cachedDelay,
    this.dimmed = false,
    this.favorite = false,
    this.inUse = false,
    this.displayName,
    this.note = '',
    this.checked,
    this.region,
  });

  final OutboundInfo proxy;
  final DateTime? since;
  final DateTime? testStarted;
  final int? cachedDelay;
  final bool selected;
  final bool inUse;
  final bool dimmed;
  final bool favorite;
  final String? displayName;
  final String note;
  final String? region;

  /// 多选: null = not selecting, else whether this card is picked
  final bool? checked;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    MuseNodeRow.debugBuilds++;
    final mt = MuseTheme.of(context);
    final brand = museBrandOf(context);
    final view = museDelayView(
      delay: proxy.urlTestDelay,
      testedAt: proxy.hasUrlTestTime() ? proxy.urlTestTime.toDateTime() : null,
      since: since,
      testStarted: testStarted,
      cached: cachedDelay,
      reason: proxy.urlTestError,
    );
    final delayColor = switch (view.kind) {
      MuseDelayKind.live => MuseColors.delay(context, view.delay),
      MuseDelayKind.timeout => MusePalette.red,
      _ => mt.text2,
    };
    final parts = museDelayParts(view);
    final name = displayName ?? museNodeName(proxy);
    final invalid = museIsInvalidNodeType(proxy.type);
    final type = proxy.type.toLowerCase();
    final protocol = invalid || type == 'direct' || type == 'block' ? '' : museProtocolShort(proxy.type);
    final own = region ?? '';
    final code = own.isNotEmpty ? own : museRegionCode(name) ?? museRegionCode(museNodeName(proxy));
    final flag = own.isNotEmpty ? museCountryFlag(own) : (museFlagEmoji(name) ?? museFlagEmoji(museNodeName(proxy)));
    final regionText = invalid ? museInvalidNodeSubtitle(proxy.type) : (note.isNotEmpty ? note : (code == null ? '' : museCountryLabel(code)));
    final highlighted = selected || (checked ?? false);

    final Widget corner = checked != null
        ? Icon(
            checked! ? Icons.check_circle_outlined : Icons.radio_button_unchecked_outlined,
            key: ValueKey('node_check_${proxy.tag}'),
            size: MuseSize.nodeCardCheck,
            color: checked! ? brand : mt.text3,
          )
        : selected
        ? Container(
            key: const ValueKey('node_card_tick'),
            width: MuseSize.nodeCardCheck,
            height: MuseSize.nodeCardCheck,
            decoration: BoxDecoration(color: brand, shape: BoxShape.circle),
            child: Icon(Icons.check_outlined, size: MuseIconSize.tiny, color: museOnColor(brand)),
          )
        : favorite
        ? const Icon(Icons.star_rounded, size: MuseIconSize.tiny, color: MusePalette.star, key: ValueKey('node_star'))
        : const SizedBox.shrink();

    final card = Material(
      key: ValueKey(highlighted ? 'node_card_selected' : 'node_card'),
      color: highlighted ? mt.selected : mt.card,
      shape: RoundedSuperellipseBorder(
        borderRadius: MuseRadius.cardAll,
        side: highlighted || inUse ? BorderSide(color: brand, width: MuseSize.nodeCardBorder) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (flag != null) ...[
                    Text(flag, style: const TextStyle(fontSize: MuseIconSize.flag, height: 1)),
                    const SizedBox(width: MuseSpace.s8),
                  ],
                  Expanded(
                    child: Text(regionText, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.caption(context)),
                  ),
                  corner,
                ],
              ),
              Text(
                flag == null ? name : museStripFlags(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MuseTextLevel.subheadline.style(context, color: mt.text1, weight: highlighted ? FontWeight.w700 : FontWeight.w600).copyWith(fontFamily: MuseFont.family),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (protocol.isNotEmpty)
                    Flexible(
                      child: Container(
                        key: const ValueKey('node_protocol_tag'),
                        padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s4),
                        decoration: BoxDecoration(color: highlighted ? brand.withValues(alpha: 0.16) : mt.inner, borderRadius: MuseRadius.smallAll),
                        child: Text(
                          protocol,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: MuseTextLevel.caption2.style(context, color: highlighted ? brand : mt.text2),
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  const SizedBox(width: MuseSpace.s4),
                  AnimatedSwitcher(
                    duration: museMotion(context),
                    transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                    child: Text.rich(
                      key: ValueKey(view.text),
                      TextSpan(
                        children: [
                          TextSpan(
                            text: parts.number,
                            style: MuseTextLevel.subheadline.style(context, color: delayColor, weight: parts.unit.isEmpty ? FontWeight.w500 : FontWeight.w700).copyWith(fontFamily: MuseFont.family),
                          ),
                          if (parts.unit.isNotEmpty)
                            TextSpan(text: ' ${parts.unit}', style: MuseTextLevel.caption2.style(context, color: mt.text2)),
                        ],
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // 1.16.0 B11: 读屏读「节点 名称，延迟」，并说明点按的作用
    return Semantics(
      button: true,
      selected: selected,
      label: museNodeSemanticsLabel(museStripFlags(name), view.text, selected: selected),
      hint: selected ? null : '点按切换到这个节点',
      child: dimmed ? Opacity(opacity: 0.55, child: card) : card,
    );
  }
}

/// 1.11.0 (A): one mode of the 节点 page's top bar — 手动选择, or a group of the main selector.
class MuseNodeMode {
  const MuseNodeMode({required this.key, required this.label, this.groupTag});

  /// 'manual' or the group's tag
  final String key;
  final String label;

  /// null = 手动选择
  final String? groupTag;
}

/// 1.11.0: the modes for the bar: 手动选择 first, then each group of [groups] (自动最快 with its
/// delay, 负载均衡, …). Empty when there is no group to choose (the bar is hidden then).
List<MuseNodeMode> museNodeModes(List<OutboundInfo> groups, {required int Function(OutboundInfo) delayOf}) {
  if (groups.isEmpty) return const [];
  return [
    const MuseNodeMode(key: 'manual', label: '手动选择'),
    for (final g in groups)
      MuseNodeMode(
        key: g.tag,
        groupTag: g.tag,
        label: switch (museGroupIconKind(type: g.type, name: museNodeName(g).split(' → ').first.trim(), selectedDisplay: g.groupSelectedTagDisplay)) {
          MuseGroupIcon.autoFastest => delayOf(g) > 0 ? '自动最快 ${delayOf(g)}' : '自动最快',
          MuseGroupIcon.loadBalance => '负载均衡',
          _ => museGroupName(museNodeName(g).split(' → ').first.trim()),
        },
      ),
  ];
}

/// 1.11.0: which mode the main group is in ([selected] = its pick).
String museNodeModeOf(List<MuseNodeMode> modes, String selected) =>
    modes.where((m) => m.groupTag != null && m.groupTag == selected).firstOrNull?.key ?? 'manual';

/// 1.11.0: the node 「手动选择」 switches to from a group: the most recent node still in the list,
/// else the fastest one that passed its test, else the first node; null when there is none.
String? museManualPick({required List<String> recent, required List<OutboundInfo> nodes, required int Function(OutboundInfo) delayOf}) {
  final present = {for (final n in nodes) n.tag};
  for (final r in recent) {
    if (present.contains(r)) return r;
  }
  final tested = [for (final n in nodes) if (museIsValidDelayMs(delayOf(n))) n]..sort((a, b) => delayOf(a).compareTo(delayOf(b)));
  return tested.firstOrNull?.tag ?? nodes.firstOrNull?.tag;
}

/// 1.11.0 (A): 手动选择 / 自动最快 184 / 负载均衡 — the selected mode is a filled accent pill.
class MuseNodeModeBar extends StatelessWidget {
  const MuseNodeModeBar({super.key, required this.modes, required this.selected, required this.onChanged});

  final List<MuseNodeMode> modes;
  final String selected;
  final ValueChanged<MuseNodeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final brand = museBrandOf(context);
    return SizedBox(
      key: const ValueKey('node_mode_bar'),
      height: MediaQuery.textScalerOf(context).scale(MuseSize.nodeModeBar),
      child: DecoratedBox(
        decoration: BoxDecoration(color: mt.card, borderRadius: MuseRadius.fullAll),
        child: Padding(
          padding: const EdgeInsets.all(MuseSpace.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < modes.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: modes[i].key == selected,
                    child: InkWell(
                      key: ValueKey('node_mode_$i'),
                      borderRadius: MuseRadius.fullAll,
                      onTap: () => onChanged(modes[i]),
                      child: AnimatedContainer(
                        duration: museMotion(context),
                        curve: MuseMotion.curve,
                        decoration: BoxDecoration(color: modes[i].key == selected ? brand : MusePalette.transparent, borderRadius: MuseRadius.fullAll),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            modes[i].label,
                            maxLines: 1,
                            style: MuseType.body(context).copyWith(
                              fontWeight: modes[i].key == selected ? FontWeight.w600 : FontWeight.w500,
                              color: modes[i].key == selected ? museOnColor(brand) : mt.text2,
                              fontFeatures: MuseType.tabular,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1.16.0 B11: what the screen reader says for a node card (Chinese, the latency text included).
String museNodeSemanticsLabel(String name, String latency, {required bool selected}) {
  final l = latency.trim();
  return [if (selected) '当前节点', '节点 $name', if (l.isNotEmpty) '延迟 $l'].join('，');
}
