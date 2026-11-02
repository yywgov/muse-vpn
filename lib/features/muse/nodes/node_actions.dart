// 穿云 - node list: copy-as, favourite order. Split out of node_list.dart in 1.9.0 (same library, behaviour unchanged).
// 1.10.0: 清除不可用 and the 当前节点 card were removed (no 「不可用」 group, no card on the 节点 page).
// Part of 穿云 (GPLv3).

part of 'node_list.dart';

/// 1.6.0 #34: the sort menu's 「收藏排序…」 entry.
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
