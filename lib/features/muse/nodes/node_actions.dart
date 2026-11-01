// 穿云 - node list: copy-as, favourite order, 清除不可用, current node card. Split out of node_list.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'node_list.dart';

/// 1.6.0 #34: the sort menu's 「收藏排序…」 entry.
const _locateItem = '__locate';
const _favoriteOrderItem = '__favorites';

/// 1.6.0 #35: pick a format and copy the node in it; returns the format copied (null = cancelled).
/// A format that can't express the node is shown but greyed out.
Future<MuseNodeCopyFormat?> museCopyNodeAs(BuildContext context, {required String raw, required String tag, required String name}) async {
  final texts = {for (final f in MuseNodeCopyFormat.values) f: museNodeCopyText(raw, tag, f, name: name)};
  final f = await showDialog<MuseNodeCopyFormat>(
    context: context,
    builder: (c) => SimpleDialog(
      key: const ValueKey('node_copy_dialog'),
      title: const Text('复制节点'),
      children: [
        for (final f in MuseNodeCopyFormat.values)
          SimpleDialogOption(
            key: ValueKey('node_copy_${f.name}'),
            onPressed: texts[f] == null ? null : () => Navigator.of(c).pop(f),
            child: Text(
              texts[f] == null ? '${f.label}（此协议不支持）' : f.label,
              style: texts[f] == null ? MuseType.body(c).copyWith(color: MuseTheme.of(c).text2) : null,
            ),
          ),
      ],
    ),
  );
  if (f == null) return null;
  await Clipboard.setData(ClipboardData(text: texts[f]!));
  return f;
}

/// 1.6.0 #34: arrange favourites by dragging; 「按列表顺序」 goes back to the list's own order.
Future<void> showMuseFavoriteOrder(BuildContext context, WidgetRef ref, OutboundGroup group) async {
  final stored = museParseFavorites(ref.read(Preferences.museFavoriteNodes));
  final names = {for (final e in group.items) if (!e.isGroup) e.tag: museNodeName(e)};
  final metas = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
  final beautify = ref.read(MusePrefs.beautifyNames);
  final present = stored.where(names.containsKey).toList();
  if (present.length < 2) return;
  final result = await showDialog<List<String>>(
    context: context,
    builder: (c) => _MuseFavoriteOrderDialog(
      order: present,
      nameOf: (t) => metas.displayName(t, names[t] ?? t, beautify: beautify),
    ),
  );
  if (result == null) return;
  if (result.isEmpty) {
    await ref.read(MusePrefs.favoriteManualOrder.notifier).update(false);
    return;
  }
  // favourites of other subscriptions keep their place after this one's
  final next = [...result, ...stored.where((t) => !result.contains(t))];
  await ref.read(Preferences.museFavoriteNodes.notifier).update(next.join('\n'));
  await ref.read(MusePrefs.favoriteManualOrder.notifier).update(true);
}

class _MuseFavoriteOrderDialog extends StatefulWidget {
  const _MuseFavoriteOrderDialog({required this.order, required this.nameOf});

  final List<String> order;
  final String Function(String tag) nameOf;

  @override
  State<_MuseFavoriteOrderDialog> createState() => _MuseFavoriteOrderDialogState();
}

class _MuseFavoriteOrderDialogState extends State<_MuseFavoriteOrderDialog> {
  late List<String> _order = [...widget.order];

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('fav_order_dialog'),
    title: const Text('收藏排序'),
    content: SizedBox(
      width: MuseSize.dialogWidth,
      height: MuseSize.dialogList,
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: _order.length,
        onReorder: (from, to) => setState(() => _order = museReorderFavorites(_order, from, to)),
        itemBuilder: (context, i) => ListTile(
          key: ValueKey('fav_order_${_order[i]}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(widget.nameOf(_order[i]), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: ReorderableDragStartListener(
            index: i,
            child: Icon(Icons.drag_handle_outlined, key: ValueKey('fav_order_handle_${_order[i]}')),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(key: const ValueKey('fav_order_auto'), onPressed: () => Navigator.of(context).pop(const <String>[]), child: const Text('按列表顺序')),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      FilledButton(key: const ValueKey('fav_order_save'), onPressed: () => Navigator.of(context).pop(_order), child: const Text('保存')),
    ],
  );
}

/// 1.6.0 #40: 清除不可用 — preview the nodes that would go into 已隐藏 (the node in use and
/// favourites stay), then hide them; 撤销 in the bar that follows shows them again. Nothing is
/// removed from the subscription. Returns the undo (null when nothing was cleared).
Future<Future<void> Function()?> museClearUnavailable(
  BuildContext context,
  WidgetRef ref, {
  required List<String> tags,
  required Map<String, String> names,
  required Set<String> unavailable,
  required String selected,
  required Set<String> favorites,
}) async {
  final plan = museClearPlan(tags, unavailable: unavailable, selected: selected, favorites: favorites);
  if (plan.isEmpty) {
    try {
      ref.read(inAppNotificationControllerProvider).showInfoToast('没有可清除的节点（收藏和正在使用的节点会保留）');
    } catch (_) {}
    return null;
  }
  final kept = plan.keep.where(unavailable.contains).length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('clear_unavailable_dialog'),
      title: Text('清除 ${plan.remove.length} 个不可用节点'),
      content: SizedBox(
        width: MuseSize.dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '以下节点会移到「已隐藏」，随时可以恢复${kept > 0 ? '；收藏和正在使用的 $kept 个保留' : ''}。',
              style: MuseType.caption(c),
            ),
            const SizedBox(height: MuseSpace.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: MuseSize.dialogList),
              child: ListView(
                key: const ValueKey('clear_unavailable_preview'),
                shrinkWrap: true,
                children: [
                  for (final t in plan.remove)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4),
                      child: Text(names[t] ?? t, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.body(c)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
        FilledButton(key: const ValueKey('clear_unavailable_confirm'), onPressed: () => Navigator.of(c).pop(true), child: const Text('清除')),
      ],
    ),
  );
  if (ok != true) return null;
  final metas = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
  await ref.read(MusePrefs.nodeMeta.notifier).update(metas.setHidden(plan.remove, true).toRaw());
  Future<void> undo() async {
    final cur = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
    await ref.read(MusePrefs.nodeMeta.notifier).update(cur.setHidden(plan.remove, false).toRaw());
  }

  try {
    ref
        .read(inAppNotificationControllerProvider)
        .showSuccessToast('已清除 ${plan.remove.length} 个不可用节点', action: (label: '撤销', onPressed: () => unawaited(undo())));
  } catch (_) {}
  return undo;
}

/// 1.6.0 #38: the node in use, above the list (stays while it scrolls). Tap = its details.
class MuseCurrentNodeCard extends StatelessWidget {
  const MuseCurrentNodeCard({
    super.key = const ValueKey('node_current_card'),
    required this.proxy,
    required this.name,
    required this.delay,
    required this.running,
    required this.onTap,
    this.pick = '',
    this.region,
  });

  final OutboundInfo proxy;
  final String name;

  /// a group's pick (自动最快 → its node)
  final String pick;
  final String? region;
  final int delay;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final type = proxy.type.toLowerCase();
    final shown = proxy.isGroup || type == 'direct' || type == 'block' ? museGroupName(name) : name;
    final flag = region == null ? null : museCountryFlag(region!);
    final relay = proxy.isGroup ? null : museRelayInfo(name, nameRegion: region, exitCode: proxy.hasIpinfo() ? proxy.ipinfo.countryCode : '');
    final protocol = proxy.isGroup || museIsInvalidNodeType(proxy.type) ? '' : museProtocolShort(proxy.type);
    final line2 = [
      running ? '当前节点' : '下次连接使用',
      if (pick.isNotEmpty) pick,
      if (protocol.isNotEmpty) protocol,
      if (relay != null)
        '中转 ${relay.entry.isEmpty ? '?' : relay.entry} → ${relay.exit == null ? '?' : museCountryLabel(relay.exit!)}',
    ].join(' · ');
    final valid = ConnectionConst.isValidDelay(delay);
    final delayText = !running || delay == 0 ? '' : (valid ? '$delay ms' : '超时');
    return Material(
      color: mt.card,
      shape: mt.cardShape(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16, vertical: MuseSpace.s12),
          child: Row(
            children: [
              MuseFlagBox(flag: flag, icon: proxy.isGroup ? Icons.bolt_outlined : Icons.public_outlined, neutral: !proxy.isGroup),
              const SizedBox(width: MuseSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      flag == null ? shown : museStripFlags(shown),
                      key: const ValueKey('node_current_name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MuseType.body(context).copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(line2, key: const ValueKey('node_current_info'), maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.caption(context)),
                  ],
                ),
              ),
              if (delayText.isNotEmpty) ...[
                const SizedBox(width: MuseSpace.s8),
                Text(
                  delayText,
                  style: MuseType.body(context).copyWith(
                    color: valid ? MuseColors.delay(context, delay) : MusePalette.red,
                    fontFeatures: MuseType.tabular,
                  ),
                ),
              ],
              const SizedBox(width: MuseSpace.s4),
              Icon(Icons.chevron_right_outlined, color: mt.text3),
            ],
          ),
        ),
      ),
    );
  }
}
