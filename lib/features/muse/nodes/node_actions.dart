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

// 1.20.1：以下节点测速 / 选择 / 名称工具函数从 node_list.dart 移来（该文件超过 1000 行上限）。
final museActiveConfigProvider = FutureProvider<String>((ref) async {
  final id = ref.watch(museActiveProfileIdProvider);
  if (id == null) return '';
  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.getRawConfig(id).getOrElse((_) => '').run();
});

/// When the running 测速 started (null = none). Shared by the 测速 button, pull-to-test and the
/// 首页 pull-down, so the list keeps its order while results stream in wherever it was started.
final museNodeTestStartedProvider = StateProvider<DateTime?>((ref) => null);

/// 1.18.0 P3: the 测速 button's sweep stops after this (the 已测 x / y count keeps going).
const museNodeTestSweepTimeout = Duration(seconds: 90);

/// Runs 测速 over the main group (no-op while one runs or when not connected).
Future<void> museRunNodeTest(WidgetRef ref) async {
  if (!ref.read(museRunningProvider) || ref.read(museNodeTestStartedProvider) != null) return;
  final group = ref.read(museNodeGroupProvider).valueOrNull;
  if (group == null) return;
  final started = DateTime.now();
  ref.read(museNodeTestStartedProvider.notifier).state = started;
  try {
    await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group.tag);
  } catch (_) {
    // the notifier already logs the failure
  }
  // results stream in over the next seconds; the list ends the test once every node answered,
  // at the latest after the cap for this many nodes (1.4.0: was a fixed 15 s that left dozens of
  // rows at 「测速中」)
  final nodes = group.items.where((e) => !e.isGroup).length;
  final cap = museTestCap(
    nodes: nodes,
    workers: ref.read(MusePrefs.testWorkers),
    timeoutSec: ref.read(MusePrefs.testTimeoutSec),
  );
  Timer(cap, () {
    try {
      if (ref.read(museNodeTestStartedProvider) == started) ref.read(museNodeTestStartedProvider.notifier).state = null;
    } catch (_) {}
  });
}

/// 1.4.1 多选 › 测速: the chosen nodes one after another (the core queues them on its own
/// bounded workers); the list shows them as 测速中 until they answer.
Future<void> museTestNodes(WidgetRef ref, Set<String> tags) async {
  final notifier = ref.read(proxiesOverviewNotifierProvider.notifier);
  for (final t in tags.take(200)) {
    try {
      await notifier.urlTest(t);
    } catch (_) {}
  }
}

/// Ends the running 测速 in the list (results that still arrive are shown as they come).
void museStopNodeTest(WidgetRef ref) => ref.read(museNodeTestStartedProvider.notifier).state = null;

/// Pull-down on 首页 / 节点: 测速 while connected, otherwise update the subscriptions.
Future<void> museNodePull(WidgetRef ref) async {
  if (ref.read(museRunningProvider)) {
    unawaited(museRunNodeTest(ref));
    await Future<void>.delayed(const Duration(milliseconds: 900));
  } else {
    try {
      await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
    } catch (_) {}
  }
}

/// Picks [tag]: switches the live group, or (disconnected) remembers it for the next connect.
Future<void> musePickNode(WidgetRef ref, String groupTag, String tag) async {
  try {
    if (ref.read(museRunningProvider)) {
      await museSelectNode(ref, groupTag, tag);
      await museRememberRecent(ref, tag);
    } else {
      final profileId = ref.read(museActiveProfileIdProvider);
      if (profileId == null) return;
      final raw = ref.read(Preferences.museLastNodes);
      await ref.read(Preferences.museLastNodes.notifier).update(museRememberNode(raw, profileId, tag));
      await museRememberRecent(ref, tag);
    }
  } catch (_) {
    try {
      ref.read(inAppNotificationControllerProvider).showErrorToast('切换节点失败，请重试');
    } catch (_) {}
  }
}

/// 1.6.0 #37: [tag] goes to the front of 最近使用.
Future<void> museRememberRecent(WidgetRef ref, String tag) async {
  try {
    final recent = museRecentFromRaw(ref.read(MusePrefs.recentNodes));
    await ref.read(MusePrefs.recentNodes.notifier).update(museRecentToRaw(museAddRecent(recent, tag, keep: 8)));
  } catch (_) {}
}

/// 1.6.0 #28: a node's protocol as its tag shows it ('' for groups, 直连 / 拦截 and broken nodes).
String museNodeProtocolShort(OutboundInfo e) {
  final t = e.type.toLowerCase();
  if (e.isGroup || t == 'direct' || t == 'block' || museIsInvalidNodeType(e.type)) return '';
  return museProtocolShort(e.type);
}

String museNodeName(OutboundInfo e) => e.tagDisplay.isNotEmpty ? e.tagDisplay : e.tag;

/// 1.5.3: a group's pick (raw name from the core) as its own row shows it (renamed / tidied),
/// so 自动最快, the 首页 and the list never disagree.
final museShownPickProvider = Provider<String Function(String raw)>((ref) {
  final metas = MuseNodeMetas.parse(ref.watch(MusePrefs.nodeMeta));
  final beautify = ref.watch(MusePrefs.beautifyNames);
  final items = [
    for (final e in ref.watch(museNodeGroupProvider).valueOrNull?.items ?? const <OutboundInfo>[])
      if (!e.isGroup) (e.tag, museNodeName(e)),
  ];
  return (raw) => metas.pickName(raw, items, beautify: beautify);
});

final _flagRun = RegExp('[\u{1F1E6}-\u{1F1FF}]{2}\\s*', unicode: true);

/// [name] without flag emoji (the flag is shown in its own box next to it).
String museStripFlags(String name) {
  final s = name.replaceAll(_flagRun, '').trim();
  return s.isEmpty ? name : s;
}

/// A node's delay for sorting: results from before this connection count as not tested yet.
int museFreshDelay(OutboundInfo proxy, DateTime? since) {
  final delay = proxy.urlTestDelay;
  if (delay == 0) return 0;
  final testedAt = proxy.hasUrlTestTime() ? proxy.urlTestTime.toDateTime() : null;
  if (since != null && testedAt != null && testedAt.isBefore(since.subtract(const Duration(seconds: 2)))) return 0;
  return delay;
}
