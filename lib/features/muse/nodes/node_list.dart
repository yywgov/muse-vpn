// 穿云 1.3.0 - the node list: the 节点 tab, the 首页 node picker sheet and the right-hand column on
// wide Windows windows all use this widget. Search, sort (按延迟 / 订阅顺序 / 按地区), favourites,
// region headers, long-press detail, single-node test.
// 1.11.0: the 节点 page is the A 双列卡片 design (docs: 节点页定稿) — a 手动选择 / 自动最快 / 负载均衡 bar
// above two columns of node cards (more on a wide window); the sheet and the side column keep rows.
// 1.10.0: no 「不可用」 group — timed-out nodes sort to the end and show 「超时」; no 当前节点 card on
// the 节点 page (the row is highlighted and the page scrolls to it once); the toolbar is 搜索, 测速 and
// one ⋯ menu (筛选 / 排序 / 布局 / 多选 / 滚动到当前节点 / 节点设置).
// Works while disconnected from the cached list (picking then only remembers the node).
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:math' as math;

import 'package:hiddify/features/muse/nodes/auto_region_chip.dart';
import 'package:hiddify/features/muse/home/auto_fastest.dart' show museAutoFastestTag;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/home/node_memory.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/logic/node_style.dart';
import 'package:hiddify/features/muse/logic/node_share.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
import 'package:hiddify/features/muse/widget/qr_view.dart';
import 'package:hiddify/features/muse/data/speed_test.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show MuseNodeSettingsPage, musePushPage;
import 'package:hiddify/features/muse/settings/sub_filter_dialog.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

part 'node_rows.dart';
part 'node_details.dart';
part 'node_actions.dart';
part 'node_dialogs.dart';

/// 1.5.0 #26: the active subscription's saved config (sing-box JSON) for the node detail sheet.
final museActiveConfigProvider = FutureProvider<String>((ref) async {
  final id = ref.watch(museActiveProfileIdProvider);
  if (id == null) return '';
  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.getRawConfig(id).getOrElse((_) => '').run();
});

/// When the running 测速 started (null = none). Shared by the 测速 button, pull-to-test and the
/// 首页 pull-down, so the list keeps its order while results stream in wherever it was started.
final museNodeTestStartedProvider = StateProvider<DateTime?>((ref) => null);

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

/// The node list. [embedded] = inside a sheet or side column (no pull-to-test, no outer padding
/// for a page). [onPicked] runs after a node was tapped.
class MuseNodeList extends HookConsumerWidget {
  const MuseNodeList({super.key, this.controller, this.embedded = false, this.onPicked, this.listKey});

  final ScrollController? controller;
  final bool embedded;
  final VoidCallback? onPicked;
  final Key? listKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final margin = embedded ? MuseSpace.s16 : MuseSpace.page(context);
    final running = ref.watch(museRunningProvider);
    final hasProfile = ref.watch(museHasProfileProvider) ?? false;
    final proxies = ref.watch(museNodeGroupProvider);
    final group = proxies.valueOrNull;
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;
    final testStarted = ref.watch(museNodeTestStartedProvider);
    final testing = testStarted != null;
    final frozenOrder = useRef<List<String>>(const []);
    final frozenSort = useRef<MuseNodeSort>(MuseNodeSort.delay);
    final searching = useState(false);
    final query = useState('');
    final searchController = useTextEditingController();
    final sortMode = MuseNodeSort.fromKey(ref.watch(Preferences.museNodeSort));
    final favorites = museParseFavorites(ref.watch(Preferences.museFavoriteNodes));
    // 1.6.0 #34: favourites in the user's own order (the stored order) once they arranged them
    final favoriteManual = ref.watch(MusePrefs.favoriteManualOrder);
    // 1.4.1: 多选 (测速 / 收藏 / 隐藏 / 复制名称 for several nodes at once)
    final selecting = useState(false);
    final picked = useState<Set<String>>(const {});
    // 1.4.0: rename / note / hide, name filters, duplicates, collapsible regions
    final metas = MuseNodeMetas.parse(ref.watch(MusePrefs.nodeMeta));
    final beautify = ref.watch(MusePrefs.beautifyNames);
    final includeRe = ref.watch(MusePrefs.includeRegex);
    final excludeRe = ref.watch(MusePrefs.excludeRegex);
    // 1.5.0 #43: the active subscription's own 只显示 / 排除
    final subFilter = museSubFilterOf(ref.watch(MusePrefs.subFilters), ref.watch(museActiveProfileIdProvider));
    final hideDuplicates = ref.watch(MusePrefs.hideDuplicates);
    // 1.6.0 #31: protocol + address + port (default) / address + port / every setting
    final dedupMode = ref.watch(MusePrefs.dedupMode);
    final dedupConfig = hideDuplicates && dedupMode == 'full' ? ref.watch(museActiveConfigProvider).valueOrNull ?? '' : '';
    final collapsedRaw = ref.watch(MusePrefs.collapsedRegions);
    final collapsed = collapsedRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final showUserHidden = useState(false);
    String shownName(OutboundInfo e) => metas.displayName(e.tag, museNodeName(e), beautify: beautify);
    final shownPick = ref.watch(museShownPickProvider);
    // 1.6.0 #32: a region set by hand wins over the one in the name
    String? regionOf(OutboundInfo e) => metas.regionOf(e.tag, museRegionCode(museNodeName(e)));
    // 1.6.0 #28 / #33: narrow to one protocol or one of the user's tags
    final protocols = museProtocolsPresent([
      for (final e in group?.items ?? const <OutboundInfo>[]) museNodeProtocolShort(e),
    ]);
    final nodeTags = metas.allTags;
    final nodeFilter = MuseNodeFilter.parse(ref.watch(MusePrefs.protocolFilter)).within(protocols: protocols, tags: nodeTags);
    final recent = museRecentFromRaw(ref.watch(MusePrefs.recentNodes));
    final profileName = ref.watch(museActiveProfileNameProvider)?.trim() ?? '';
    // 1.6.0 C5: 列表 / 卡片 and 紧凑 / 标准 / 宽松 (the embedded lists stay a plain list)
    // 1.11.0: the 节点 page is always the A 双列卡片 layout; the sheet and the side column stay a list
    final cardsA = !embedded;
    final layout = embedded ? MuseNodeLayout.list : MuseNodeLayout.grid;
    final density = MuseNodeDensity.fromKey(ref.watch(MusePrefs.nodeDensity));
    final ownScroll = useScrollController();
    final scroll = controller ?? ownScroll;
    final selectedKey = useMemoized(GlobalKey.new);
    final rowMemo = useRef(_NodeRowMemo(null));
    var selectedKeyUsed = false;

    // every node answered (or timed out) since 测速 started: end the test
    if (testing && group != null) {
      final nodes = group.items.where((e) => !e.isGroup);
      // 1.10.3: a node at 0 is being re-tested once by the core (not answered yet)
      final done = nodes.isNotEmpty &&
          nodes.every((e) => museAnsweredTest(delay: e.urlTestDelay, testedAt: e.hasUrlTestTime() ? e.urlTestTime.toDateTime() : null, testStarted: testStarted));
      final minShown = DateTime.now().difference(testStarted) > const Duration(milliseconds: 800);
      if (done && minShown) {
        Future.microtask(() {
          if (ref.read(museNodeTestStartedProvider) == testStarted) ref.read(museNodeTestStartedProvider.notifier).state = null;
        });
      }
    }

    final nodeTotal = group?.items.where((e) => !e.isGroup).length ?? 0;
    final progress = testing && running && group != null
        ? museTestProgress([
            for (final e in group.items)
              if (!e.isGroup) e.hasUrlTestTime() && e.urlTestDelay != 0 ? e.urlTestTime.toDateTime() : null,
          ], testStarted)
        : null;
    bool matches(OutboundInfo e) {
      final q = query.value;
      if (!searching.value || q.trim().isEmpty) return true;
      return museNodeMatches(museNodeName(e), q, regionOf: museRegionCode) ||
          museNodeMatches(shownName(e), q, regionOf: museRegionCode) ||
          metas.of(e.tag).note.toLowerCase().contains(q.trim().toLowerCase());
    }

    // 1.10.0: one ⋯ menu instead of the 多选 / 筛选 / 布局 / 排序 icons
    final canFilter = nodeTotal > 1 && (protocols.length > 1 || nodeTags.isNotEmpty);
    final moreItems = <(String, String)>[
      if (canFilter) ('filter', '筛选：${nodeFilter.label}'),
      if (nodeTotal > 1) ('sort', '排序：${sortMode.title}'),
      if (!embedded && nodeTotal > 1) ('select', '多选'),
      if (group != null && group.selected.isNotEmpty) ('locate', '滚动到当前节点'),
      if (!embedded) ('settings', '节点设置'),
    ];
    Future<void> onMore(String v) async {
      switch (v) {
        case 'filter':
          final raw = await _museNodeChoice<String>(context, '筛选', [
            ('node_filter_all', '', '全部', nodeFilter.isNone),
            for (final p in protocols)
              if (protocols.length > 1) ('node_filter_p_$p', MuseNodeFilter.protocol(p).toRaw(), p, nodeFilter == MuseNodeFilter.protocol(p)),
            for (final t in nodeTags) ('node_filter_t_$t', MuseNodeFilter.tag(t).toRaw(), '标签：$t', nodeFilter == MuseNodeFilter.tag(t)),
          ]);
          if (raw != null) await ref.read(MusePrefs.protocolFilter.notifier).update(raw);
        case 'sort':
          final favCount = group == null ? 0 : group.items.where((e) => !e.isGroup && favorites.contains(e.tag)).length;
          final picked = await _museNodeChoice<String>(context, '排序', [
            for (final m in MuseNodeSort.values) ('node_sort_${m.key}', m.key, m.title, m == sortMode),
            // 1.6.0 #34: arrange favourites by dragging
            if (favCount > 1) ('node_sort_favorites', _favoriteOrderItem, '收藏排序…', false),
          ]);
          if (picked == null) return;
          if (picked != _favoriteOrderItem) return ref.read(Preferences.museNodeSort.notifier).update(picked);
          if (group != null && context.mounted) await showMuseFavoriteOrder(context, ref, group);
        case 'layout':
          final picked = await _museNodeChoice<String>(context, '布局', [
            for (final l in MuseNodeLayout.values) ('node_layout_${l.key}', 'layout_${l.key}', l.title, l == layout),
            for (final d in MuseNodeDensity.values) ('node_density_${d.key}', 'density_${d.key}', d.title, d == density),
          ], dividerAfter: MuseNodeLayout.values.length);
          if (picked == null) return;
          final l = MuseNodeLayout.values.where((e) => 'layout_${e.key}' == picked).firstOrNull;
          if (l != null) return ref.read(MusePrefs.nodeLayout.notifier).update(l.key);
          final d = MuseNodeDensity.values.where((e) => 'density_${e.key}' == picked).firstOrNull;
          if (d != null) return ref.read(MusePrefs.nodeDensity.notifier).update(d.key);
        case 'select':
          selecting.value = true;
          picked.value = const {};
        case 'locate':
          final found = await museScrollToKey(scroll, selectedKey);
          if (!found) {
            try {
              ref.read(inAppNotificationControllerProvider).showInfoToast('当前节点不在列表里（可能已折叠或被筛选）');
            } catch (_) {}
          }
        case 'settings':
          await musePushPage(context, const MuseNodeSettingsPage());
      }
    }

    // 1.10.0: the 节点 page opens at the node in use (the row is highlighted).
    // 1.10.2: every time the page comes into view (the tab stays alive in the shell, so this follows
    // TickerMode, no polling) and only when the node in use changed since the last time, e.g. after
    // picking another node on 首页; a node picked on this page does not make the list jump.
    final visible = TickerMode.valuesOf(context).enabled;
    final selectedTag = group?.selected ?? '';
    final scrolledFor = useRef<String?>(null);
    useEffect(() {
      if (embedded || !visible || selectedTag.isEmpty || scrolledFor.value == selectedTag) return null;
      scrolledFor.value = selectedTag;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted || !scroll.hasClients) return;
        final found = await museScrollToKey(scroll, selectedKey);
        if (!found && context.mounted && scroll.hasClients) scroll.jumpTo(scroll.position.minScrollExtent);
      });
      return null;
    }, [visible, selectedTag.isEmpty]);

    final toolbar = Padding(
      padding: EdgeInsets.fromLTRB(margin + MuseSpace.s4, 0, margin - MuseSpace.s8, MuseSpace.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group == null
                  ? ''
                  : selecting.value
                  ? '已选 ${picked.value.length} 个'
                  : progress != null
                  // 1.5.0 #25: 测速 progress (stop with the button next to it)
                  ? '已测 ${progress.done} / ${progress.total}'
                  : '${profileName.isEmpty ? '' : '$profileName · '}$nodeTotal 个节点${nodeFilter.isNone ? '' : ' · 仅${nodeFilter.label}'}',
              key: const ValueKey('node_count_label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MuseType.caption(context),
            ),
          ),
          if (selecting.value)
            IconButton(
              key: const ValueKey('node_select_button'),
              tooltip: '完成',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_outlined, size: MuseIconSize.small),
              onPressed: () {
                selecting.value = false;
                picked.value = const {};
              },
            )
          else ...[
            if (nodeTotal > 6)
              IconButton(
                key: const ValueKey('node_search_button'),
                tooltip: searching.value ? '关闭搜索' : '搜索节点',
                visualDensity: VisualDensity.compact,
                icon: Icon(searching.value ? Icons.search_off_outlined : Icons.search_outlined, size: MuseIconSize.small),
                onPressed: () {
                  searching.value = !searching.value;
                  if (!searching.value) {
                    searchController.clear();
                    query.value = '';
                  }
                },
              ),
            FilledButton.tonal(
              key: const ValueKey('node_test_button'),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16)),
              onPressed: group == null || !running ? null : () => testing ? museStopNodeTest(ref) : museRunNodeTest(ref),
              child: testing
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: MuseSpace.s12,
                          height: MuseSpace.s12,
                          child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                        ),
                        const SizedBox(width: MuseSpace.s8),
                        Text('停止', style: MuseType.body(context).copyWith(color: museBrandOf(context))),
                      ],
                    )
                  : const Text('测速'),
            ),
            if (moreItems.isNotEmpty)
              PopupMenuButton<String>(
                key: const ValueKey('node_more_button'),
                tooltip: '更多',
                icon: Badge(
                  isLabelVisible: !nodeFilter.isNone,
                  smallSize: MuseSize.dot,
                  backgroundColor: museBrandOf(context),
                  child: const Icon(Icons.more_horiz_outlined, size: MuseIconSize.small),
                ),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelected: onMore,
                itemBuilder: (context) => [
                  for (final (value, label) in moreItems)
                    PopupMenuItem<String>(key: ValueKey('node_more_$value'), value: value, child: Text(label)),
                ],
              ),
          ],
        ],
      ),
    );

    // 1.10.2: on the 节点 page the toolbar (搜索 / 测速 / ⋯) and the search field stay above the list
    // instead of scrolling with it: the page opens scrolled to the node in use, which used to push
    // 测速 and ⋯ out of sight. The sheet and the side column keep them in the list.
    final showSearch = searching.value && nodeTotal > 6;
    final children = <Widget>[if (embedded) toolbar];
    Widget? searchField;
    if (showSearch) {
      searchField = Padding(
          padding: EdgeInsets.fromLTRB(margin, 0, margin, MuseSpace.s8),
          child: TextField(
            key: const ValueKey('node_search_field'),
            controller: searchController,
            autofocus: true,
            onChanged: (v) => query.value = v,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索节点，如 日本、HK、IPLC',
              prefixIcon: const Icon(Icons.search_outlined, size: MuseIconSize.small),
              filled: true,
              fillColor: mt.card,
              border: const OutlineInputBorder(borderRadius: MuseRadius.fullAll, borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: MuseSpace.s12),
            ),
          ),
        );
      if (embedded) children.add(searchField);
    }

    if (proxies.isLoading && group == null) {
      // 1.5.0: skeleton rows instead of a spinner
      children.add(MuseSection(dividerIndent: MuseSize.rowIndent, children: [MuseSkeleton.rows()]));
    } else if (group == null || group.items.isEmpty) {
      children.add(
        MuseSection(
          dividerIndent: MuseSpace.s16,
          children: [
            MuseTile(
              // 1.5.3: a subscription never connected has no saved list yet
              title: proxies.hasError ? '读取节点失败' : (!hasProfile ? '还没有订阅' : (running ? '暂无节点' : '连接后显示节点')),
            ),
          ],
        ),
      );
    } else {
      // 1.6.0 #37: 最近使用 — tap to switch back
      final byTagAll = {for (final e in group.items) if (!e.isGroup) e.tag: e};
      final offers = selecting.value ? const <String>[] : museRecentToOffer(recent, present: byTagAll.keys, selected: group.selected);
      if (offers.isNotEmpty) {
        children.add(
          SingleChildScrollView(
            key: const ValueKey('node_recent_row'),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(margin, 0, margin, MuseSpace.s8),
            child: Row(
              children: [
                Text('最近', style: MuseType.caption(context)),
                for (final t in offers) ...[
                  const SizedBox(width: MuseSpace.s8),
                  ActionChip(
                    key: ValueKey('node_recent_$t'),
                    visualDensity: VisualDensity.compact,
                    label: Text(shownName(byTagAll[t]!), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: () async {
                      await musePickNode(ref, group.tag, t);
                      onPicked?.call();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      }
      final dedupParams = dedupConfig.isEmpty ? const <String, String>{} : museOutboundParamsByTag(dedupConfig);
      final duplicates = !hideDuplicates
          ? const <String>{}
          : dedupMode == 'address' || (dedupMode == 'full' && dedupParams.isNotEmpty)
          ? museDuplicateTagsBy<OutboundInfo>(
              group.items.where((e) => !e.isGroup).toList(),
              mode: dedupMode == 'address' ? MuseDedupMode.addressPort : MuseDedupMode.fullParams,
              tag: (e) => e.tag,
              host: (e) => e.host,
              port: (e) => e.port,
              // a node missing from the saved config is compared by protocol + address + port
              params: (e) => dedupParams[e.tag] ?? e.type.toLowerCase(),
            )
          : museDuplicateTags<OutboundInfo>(
              group.items.where((e) => !e.isGroup).toList(),
              tag: (e) => e.tag,
              type: (e) => e.type,
              host: (e) => e.host,
              port: (e) => e.port,
            );
      final listed = group.items
          .where(
            (e) =>
                e.isGroup ||
                e.tag == group.selected ||
                (!museIsInfoNode(museNodeName(e)) &&
                    !duplicates.contains(e.tag) &&
                    museNodeNamePasses(museNodeName(e), include: includeRe, exclude: excludeRe) &&
                    museNodeNamePasses(museNodeName(e), include: subFilter.include, exclude: subFilter.exclude) &&
                    nodeFilter.passes(protocolShort: museNodeProtocolShort(e), tags: metas.of(e.tag).tags)),
          )
          .toList();
      final userHidden = {for (final t in metas.hiddenTags) if (t != group.selected) t};
      final favoredOrder = museFavoritesFirst<OutboundInfo>(
        museOrderNodes<OutboundInfo>(
          listed,
          sort: sortMode,
          isGroup: (e) => e.isGroup,
          delay: (e) => museFreshDelay(e, since),
          isValidDelay: ConnectionConst.isValidDelay,
          region: regionOf,
        ),
        isGroup: (e) => e.isGroup,
        tag: (e) => e.tag,
        favorites: favorites,
        favoriteOrder: favoriteManual ? favorites.toList() : null,
      );
      // 1.10.0: timed-out nodes at the end (按地区 already orders each region by delay)
      final sorted = sortMode == MuseNodeSort.region
          ? favoredOrder
          : museTimeoutsLast<OutboundInfo>(
              favoredOrder,
              isGroup: (e) => e.isGroup,
              delay: (e) => museFreshDelay(e, since),
              isValidDelay: ConnectionConst.isValidDelay,
            );
      final List<OutboundInfo> ordered;
      if (testing && frozenOrder.value.isNotEmpty && frozenSort.value == sortMode) {
        // keep the order from before 测速 while its results arrive
        final byTag = {for (final e in group.items) e.tag: e};
        final known = frozenOrder.value.toSet();
        ordered = [for (final t in frozenOrder.value) ?byTag[t], ...sorted.where((e) => !known.contains(e.tag))];
      } else {
        ordered = sorted;
        frozenOrder.value = [for (final e in sorted) e.tag];
        frozenSort.value = sortMode;
      }
      final filtering = searching.value && query.value.trim().isNotEmpty;
      final visible = ordered.where((e) => !userHidden.contains(e.tag) && matches(e)).toList();
      final hiddenByUser = ordered.where((e) => userHidden.contains(e.tag) && matches(e)).toList();
      final nodeCount = listed.where((e) => !e.isGroup).length;
      final latencyCache = ref.watch(museLatencyCacheProvider);

      // 1.6.0 C11: a delay update for one node rebuilds only that node's row. A row whose inputs did
      // not change is handed back as the same widget instance, so Flutter skips its build.
      final rowScope = (since, nodeCount, running ? testStarted : null, selecting.value, group.tag, group.selected, density, onPicked);
      if (rowMemo.value.scope != rowScope) rowMemo.value = _NodeRowMemo(rowScope);
      final memo = rowMemo.value;
      if (memo.rows.length > 2 * group.items.length + 16) memo.rows.clear();

      // 1.11.0 (A): the node a group (自动最快 / 负载均衡) is using right now
      final inUseTag = group.items.where((e) => e.isGroup && e.tag == group.selected).firstOrNull?.groupSelectedTag ?? '';
      Widget rowWidget(OutboundInfo proxy, {bool dimmed = false}) => cardsA && !proxy.isGroup
          ? MuseNodeCard(
              key: ValueKey(proxy.tag),
              proxy: proxy,
              since: since,
              testStarted: running ? testStarted : null,
              cachedDelay: latencyCache.delayOf(proxy.tag),
              dimmed: dimmed,
              selected: group.selected == proxy.tag,
              inUse: inUseTag.isNotEmpty && inUseTag == proxy.tag,
              favorite: favorites.contains(proxy.tag),
              displayName: shownName(proxy),
              region: metas.of(proxy.tag).region,
              note: metas.of(proxy.tag).note,
              checked: selecting.value ? picked.value.contains(proxy.tag) : null,
              onLongPress: selecting.value ? null : () => showMuseNodeDetails(context, ref, proxy, since: since, groupTag: group.tag),
              onTap: selecting.value
                  ? () {
                      final next = {...picked.value};
                      if (!next.remove(proxy.tag)) next.add(proxy.tag);
                      picked.value = next;
                    }
                  : () async {
                      await musePickNode(ref, group.tag, proxy.tag);
                      onPicked?.call();
                    },
            )
          : MuseNodeRow(
        key: ValueKey(proxy.tag),
        padV: density.padV,
        proxy: proxy,
        since: since,
        nodeCount: nodeCount,
        testStarted: running ? testStarted : null,
        cachedDelay: latencyCache.delayOf(proxy.tag),
        dimmed: dimmed,
        selected: group.selected == proxy.tag,
        favorite: favorites.contains(proxy.tag),
        displayName: proxy.isGroup ? null : shownName(proxy),
        region: proxy.isGroup ? null : metas.of(proxy.tag).region,
        note: proxy.isGroup ? '' : metas.of(proxy.tag).note,
        shownPick: shownPick,
        checked: selecting.value && !proxy.isGroup ? picked.value.contains(proxy.tag) : null,
        onLongPress: selecting.value ? null : () => showMuseNodeDetails(context, ref, proxy, since: since, groupTag: group.tag),
        onTap: selecting.value
            ? () {
                if (proxy.isGroup) return;
                final next = {...picked.value};
                if (!next.remove(proxy.tag)) next.add(proxy.tag);
                picked.value = next;
              }
            : () async {
          await musePickNode(ref, group.tag, proxy.tag);
          onPicked?.call();
        },
      );

      Widget rowOf(OutboundInfo proxy, {bool dimmed = false}) {
        final inputs = (
          proxy,
          latencyCache.delayOf(proxy.tag),
          dimmed,
          favorites.contains(proxy.tag),
          proxy.isGroup ? null : shownName(proxy),
          proxy.isGroup ? null : metas.of(proxy.tag).region,
          proxy.isGroup ? '' : metas.of(proxy.tag).note,
          // only a group row shows its pick
          proxy.isGroup ? shownPick : null,
          selecting.value && !proxy.isGroup ? picked.value.contains(proxy.tag) : null,
          cardsA && inUseTag == proxy.tag,
        );
        final hit = memo.rows[proxy.tag];
        if (hit != null && hit.$1 == inputs) return hit.$2;
        final built = rowWidget(proxy, dimmed: dimmed);
        memo.rows[proxy.tag] = (inputs, built);
        return built;
      }

      Widget row(OutboundInfo proxy, {bool dimmed = false}) {
        final r = rowOf(proxy, dimmed: dimmed);
        // 1.6.0 C5: 滚动到当前节点 finds the first row of the node in use
        if (group.selected != proxy.tag || selectedKeyUsed) return r;
        selectedKeyUsed = true;
        return KeyedSubtree(key: selectedKey, child: r);
      }

      Widget section(
        String? header,
        List<OutboundInfo> items, {
        Key? key,
        bool dimmed = false,
        bool? isCollapsed,
        VoidCallback? onHeaderTap,
        bool asList = false,
      }) => _NodeSection(
        key: key,
        asList: asList,
        selfDecorated: cardsA && !asList,
        header: header,
        margin: margin,
        collapsed: isCollapsed,
        onHeaderTap: onHeaderTap,
        children: isCollapsed ?? false ? const [] : [for (final p in items) row(p, dimmed: dimmed)],
      );

      // 1.6.0 #39: uncommon regions start folded; the user's own fold / unfold is remembered
      Future<void> toggleRegion(String code, {required bool folded}) async {
        await ref.read(MusePrefs.collapsedRegions.notifier).update(museToggleRegionFold(collapsed, code, folded: folded).join(','));
      }

      Widget foldToggle({
        required Key key,
        required IconData icon,
        required String label,
        required bool open,
        required VoidCallback onTap,
        Widget? action,
      }) =>
          Padding(
            padding: EdgeInsets.fromLTRB(margin, MuseSpace.s8, margin, 0),
            child: Material(
              color: mt.card,
              shape: mt.cardShape(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: key,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16, vertical: MuseSpace.s12),
                  child: Row(
                    children: [
                      Icon(icon, size: MuseIconSize.small, color: mt.text3),
                      const SizedBox(width: MuseSpace.s12),
                      Expanded(child: Text(label, style: MuseType.body(context).copyWith(color: mt.text2))),
                      ?action,
                      Icon(open ? Icons.expand_less_outlined : Icons.expand_more_outlined, color: mt.text3),
                    ],
                  ),
                ),
              ),
            ),
          );

      if (filtering && visible.isEmpty) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: margin + MuseSpace.s4, vertical: MuseSpace.s16),
            child: Text('没有匹配的节点', style: MuseType.body(context).copyWith(color: mt.text2)),
          ),
        );
      }
      final groups = visible.where((e) => e.isGroup).toList();
      final nodes = visible.where((e) => !e.isGroup).toList();
      // 1.11.0 (A): the groups are the 手动选择 / 自动最快 / 负载均衡 bar above the cards
      final modes = cardsA && groups.length <= 3
          ? museNodeModes(groups, delayOf: (g) {
              final d = museFreshDelay(g, since);
              return ConnectionConst.isValidDelay(d) ? d : 0;
            })
          : const <MuseNodeMode>[];
      if (modes.isNotEmpty && !selecting.value && !filtering) {
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(margin, MuseSpace.s4, margin, MuseSpace.s4),
            child: MuseNodeModeBar(
              modes: modes,
              selected: museNodeModeOf(modes, group.selected),
              onChanged: (m) async {
                final String? target;
                if (m.groupTag != null) {
                  target = m.groupTag;
                } else if (museNodeModeOf(modes, group.selected) == 'manual') {
                  return;
                } else {
                  target = museManualPick(
                    recent: recent,
                    nodes: nodes,
                    delayOf: (e) => museFreshDelay(e, since),
                  );
                }
                if (target == null || target == group.selected) return;
                await musePickNode(ref, group.tag, target);
              },
            ),
          ),
        );
        // 1.12.0: 自动最快 can be limited to one region (shown only while 自动最快 is in use)
        if (group.selected == museAutoFastestTag) {
          children.add(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: margin),
              child: MuseAutoRegionRow(regions: [for (final e in nodes) regionOf(e)]),
            ),
          );
        }
      } else if (groups.isNotEmpty && modes.isEmpty) {
        children.add(section(null, groups, asList: true));
      }
      if (sortMode == MuseNodeSort.region) {
        final favs = nodes.where((e) => favorites.contains(e.tag)).toList();
        if (favs.isNotEmpty) children.add(section('⭐ 收藏', favs, key: const ValueKey('region_header_favorites')));
        final regionSections = museRegionSections<OutboundInfo>(
          nodes.where((e) => !favorites.contains(e.tag)).toList(),
          isGroup: (e) => e.isGroup,
          region: regionOf,
        );
        final inUse = group.items.where((e) => e.tag == group.selected && !e.isGroup).firstOrNull;
        final inUseRegion = inUse == null ? null : (regionOf(inUse) ?? 'other');
        for (final s in regionSections) {
          final code = s.region;
          final label = code == null ? '其他' : '${museCountryFlag(code) ?? ''} ${museCountryLabel(code)}'.trim();
          // 1.4.0: the header shows the group's best delay; tap folds the group
          final best = s.items
              .map((e) => museFreshDelay(e, since))
              .where(ConnectionConst.isValidDelay)
              .fold<int>(0, (a, b) => a == 0 || b < a ? b : a);
          final key = code ?? 'other';
          final folded = !filtering &&
              museRegionFolded(key, collapsed, regionCount: regionSections.length, selectedRegion: inUseRegion);
          children.add(
            section(
              '$label · ${s.items.length}${best > 0 ? ' · $best ms' : ''}',
              s.items,
              key: ValueKey('region_header_$key'),
              isCollapsed: folded,
              onHeaderTap: () => toggleRegion(key, folded: folded),
            ),
          );
        }
      } else if (nodes.isNotEmpty) {
        children.add(section(null, nodes));
      }
      if (hiddenByUser.isNotEmpty) {
        children.add(
          foldToggle(
            key: const ValueKey('user_hidden_nodes_toggle'),
            icon: Icons.visibility_off_outlined,
            label: '已隐藏 · ${hiddenByUser.length}',
            open: showUserHidden.value,
            onTap: () => showUserHidden.value = !showUserHidden.value,
          ),
        );
        if (showUserHidden.value || filtering) children.add(section(null, hiddenByUser, dimmed: true));
      }
    }

    // 1.5.0 #22: rows are built lazily (a subscription with a thousand nodes scrolls smoothly);
    // each section is one sliver, its card painted behind the rows
    // 1.6.0 C5: 卡片 = the same rows as cards in a grid (fixed height, built lazily)
    final scaler = MediaQuery.textScalerOf(context);
    final list = LayoutBuilder(
      builder: (context, box) {
        final textScale = scaler.scale(MuseType.numberSize) / MuseType.numberSize;
        final columns = cardsA
            ? museNodeColumnsA(box.maxWidth - margin * 2, textScale: textScale)
            : layout == MuseNodeLayout.grid
            ? museNodeColumns(box.maxWidth - margin * 2, density, textScale: textScale)
            : 1;
        final extent = cardsA ? museNodeCardExtentA(scaler.scale) : museNodeCardExtent(density, scaler.scale);
        return CustomScrollView(
          key: listKey,
          controller: scroll,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(top: MuseSpace.s4, bottom: museScrollEndGap(context, embedded ? MuseSpace.s16 : MuseSpace.s32)),
              sliver: SliverMainAxisGroup(
                slivers: [
                  for (final c in children)
                    c is _NodeSection ? c.buildSliver(context, columns: columns, extent: extent) : SliverToBoxAdapter(child: c),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (embedded) return list;
    final refresh = RefreshIndicator(
      key: const ValueKey('nodes_pull_refresh'),
      onRefresh: () => museNodePull(ref),
      color: museBrandOf(context),
      notificationPredicate: (n) => hasProfile && n.depth == 0 && !selecting.value,
      child: list,
    );
    final framed = Column(
      children: [
        toolbar,
        ?searchField,
        Expanded(child: refresh),
      ],
    );
    if (!selecting.value || group == null) return framed;
    final sel = picked.value;
    final allNodes = [for (final e in group.items) if (!e.isGroup) e.tag];
    void toast(String t) {
      try {
        ref.read(inAppNotificationControllerProvider).showSuccessToast(t);
      } catch (_) {}
    }

    Future<void> done(String msg) async {
      toast(msg);
      selecting.value = false;
      picked.value = const {};
    }

    Widget action(String key, IconData icon, String label, Future<void> Function()? onTap) => Expanded(
      child: TextButton.icon(
        key: ValueKey('node_batch_$key'),
        onPressed: sel.isEmpty || onTap == null ? null : onTap,
        icon: Icon(icon, size: MuseIconSize.small),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );

    return Column(
      children: [
        Expanded(child: framed),
        Material(
          color: mt.card,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: margin, vertical: MuseSpace.s4),
              child: Row(
                key: const ValueKey('node_batch_bar'),
                children: [
                  TextButton(
                    key: const ValueKey('node_batch_all'),
                    onPressed: () => picked.value = sel.length == allNodes.length ? const {} : allNodes.toSet(),
                    child: Text(sel.length == allNodes.length ? '全不选' : '全选'),
                  ),
                  action('test', Icons.speed_outlined, '测速', running ? () async {
                    await museTestNodes(ref, sel);
                    await done('已开始测速 ${sel.length} 个节点');
                  } : null),
                  action('favorite', Icons.star_outlined, '收藏', () async {
                    var raw = ref.read(Preferences.museFavoriteNodes);
                    for (final t in sel) {
                      if (!museParseFavorites(raw).contains(t)) raw = museToggleFavorite(raw, t);
                    }
                    await ref.read(Preferences.museFavoriteNodes.notifier).update(raw);
                    await done('已收藏 ${sel.length} 个');
                  }),
                  action('hide', Icons.visibility_off_outlined, '隐藏', () async {
                    final metas = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
                    await ref.read(MusePrefs.nodeMeta.notifier).update(metas.setHidden(sel.where((t) => t != group.selected), true).toRaw());
                    await done(sel.contains(group.selected) ? '已隐藏（正在使用的节点除外）' : '已隐藏 ${sel.length} 个');
                  }),
                  action('copy', Icons.copy_outlined, '复制', () async {
                    final names = [for (final e in group.items) if (sel.contains(e.tag)) museNodeName(e)];
                    await Clipboard.setData(ClipboardData(text: names.join('\n')));
                    await done('已复制 ${names.length} 个名称');
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 1.10.0: a choice from the ⋯ menu as a dialog (the current entries checked); null when dismissed.
/// Each option: (key, value, label, checked).
Future<T?> _museNodeChoice<T>(BuildContext context, String title, List<(String, T, String, bool)> options, {int? dividerAfter}) =>
    showDialog<T>(
      context: context,
      builder: (c) => SimpleDialog(
        key: ValueKey('node_choice_$title'),
        title: Text(title),
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (dividerAfter != null && i == dividerAfter) const Divider(),
            ListTile(
              key: ValueKey(options[i].$1),
              title: Text(options[i].$3),
              trailing: options[i].$4 ? Icon(Icons.check_outlined, color: museBrandOf(c), size: MuseIconSize.small) : null,
              onTap: () => Navigator.of(c).pop(options[i].$2),
            ),
          ],
        ],
      ),
    );
