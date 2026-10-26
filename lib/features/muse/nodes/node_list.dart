// 穿云 1.3.0 - the node list: the 节点 tab, the 首页 node picker sheet and the right-hand column on
// wide Windows windows all use this widget. Search, sort (按延迟 / 订阅顺序 / 按地区), favourites,
// region headers, long-press detail, single-node test, timed-out nodes folded into 「不可用」.
// Works while disconnected from the cached list (picking then only remembers the node).
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/bad_nodes.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/home/node_memory.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/logic/node_share.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
import 'package:hiddify/features/muse/widget/qr_view.dart';
import 'package:hiddify/features/muse/data/speed_test.dart';
import 'package:hiddify/features/muse/settings/sub_filter_dialog.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
  const MuseNodeList({super.key, this.controller, this.embedded = false, this.onPicked, this.listKey, this.pinCurrent = false});

  /// 1.6.0 #38: the node in use as a card above the list that stays while it scrolls (节点 page)
  final bool pinCurrent;
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
    final showHidden = useState(false);
    final hidden = running ? ref.watch(museHiddenNodesProvider) : const <String>{};
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

    // every node answered (or timed out) since 测速 started: end the test
    if (testing && group != null) {
      final started = testStarted.subtract(const Duration(seconds: 1));
      final nodes = group.items.where((e) => !e.isGroup);
      final done = nodes.isNotEmpty && nodes.every((e) => e.hasUrlTestTime() && e.urlTestTime.toDateTime().isAfter(started));
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
              if (!e.isGroup) e.hasUrlTestTime() ? e.urlTestTime.toDateTime() : null,
          ], testStarted)
        : null;
    bool matches(OutboundInfo e) {
      final q = query.value;
      if (!searching.value || q.trim().isEmpty) return true;
      return museNodeMatches(museNodeName(e), q, regionOf: museRegionCode) ||
          museNodeMatches(shownName(e), q, regionOf: museRegionCode) ||
          metas.of(e.tag).note.toLowerCase().contains(q.trim().toLowerCase());
    }

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
          if (!embedded && nodeTotal > 1)
            IconButton(
              key: const ValueKey('node_select_button'),
              tooltip: selecting.value ? '完成' : '多选',
              visualDensity: VisualDensity.compact,
              icon: Icon(selecting.value ? Icons.close_outlined : Icons.checklist_outlined, size: MuseIconSize.small),
              onPressed: () {
                selecting.value = !selecting.value;
                picked.value = const {};
              },
            ),
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
          if (nodeTotal > 1 && (protocols.length > 1 || nodeTags.isNotEmpty))
            PopupMenuButton<String>(
              key: const ValueKey('node_filter_button'),
              tooltip: '筛选：${nodeFilter.label}',
              icon: Icon(
                Icons.filter_list_outlined,
                size: MuseIconSize.small,
                color: nodeFilter.isNone ? null : MusePalette.brand,
              ),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelected: (raw) => ref.read(MusePrefs.protocolFilter.notifier).update(raw),
              itemBuilder: (context) => [
                CheckedPopupMenuItem<String>(
                  key: const ValueKey('node_filter_all'),
                  value: '',
                  checked: nodeFilter.isNone,
                  child: const Text('全部'),
                ),
                if (protocols.length > 1) ...[
                  const PopupMenuDivider(),
                  for (final p in protocols)
                    CheckedPopupMenuItem<String>(
                      key: ValueKey('node_filter_p_$p'),
                      value: MuseNodeFilter.protocol(p).toRaw(),
                      checked: nodeFilter == MuseNodeFilter.protocol(p),
                      child: Text(p),
                    ),
                ],
                if (nodeTags.isNotEmpty) ...[
                  const PopupMenuDivider(),
                  for (final t in nodeTags)
                    CheckedPopupMenuItem<String>(
                      key: ValueKey('node_filter_t_$t'),
                      value: MuseNodeFilter.tag(t).toRaw(),
                      checked: nodeFilter == MuseNodeFilter.tag(t),
                      child: Text('标签：$t'),
                    ),
                ],
              ],
            ),
          if (nodeTotal > 1)
            PopupMenuButton<String>(
              key: const ValueKey('node_sort_button'),
              tooltip: '排序：${sortMode.title}',
              icon: const Icon(Icons.sort_outlined, size: MuseIconSize.small),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              initialValue: sortMode.key,
              onSelected: (v) async {
                if (v != _favoriteOrderItem) return ref.read(Preferences.museNodeSort.notifier).update(v);
                if (group != null) await showMuseFavoriteOrder(context, ref, group);
              },
              itemBuilder: (context) => [
                for (final m in MuseNodeSort.values)
                  CheckedPopupMenuItem<String>(
                    key: ValueKey('node_sort_${m.key}'),
                    value: m.key,
                    checked: m == sortMode,
                    child: Text(m.title),
                  ),
                // 1.6.0 #34: arrange favourites by dragging
                if (group != null && group.items.where((e) => !e.isGroup && favorites.contains(e.tag)).length > 1) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    key: ValueKey('node_sort_favorites'),
                    value: _favoriteOrderItem,
                    child: Text('收藏排序…'),
                  ),
                ],
              ],
            ),
          TextButton(
            key: const ValueKey('node_test_button'),
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
                      Text('停止', style: MuseType.body(context).copyWith(color: MusePalette.brand)),
                    ],
                  )
                : const Text('测速'),
          ),
        ],
      ),
    );

    final children = <Widget>[toolbar];
    if (searching.value && nodeTotal > 6) {
      children.add(
        Padding(
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
        ),
      );
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
      final sorted = museFavoritesFirst<OutboundInfo>(
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
      final visible = ordered.where((e) => !hidden.contains(e.tag) && !userHidden.contains(e.tag) && matches(e)).toList();
      final folded = ordered.where((e) => hidden.contains(e.tag) && !userHidden.contains(e.tag) && matches(e)).toList();
      final hiddenByUser = ordered.where((e) => userHidden.contains(e.tag) && matches(e)).toList();
      final nodeCount = listed.where((e) => !e.isGroup).length;
      final latencyCache = ref.watch(museLatencyCacheProvider);

      Widget row(OutboundInfo proxy, {bool dimmed = false}) => MuseNodeRow(
        key: ValueKey(proxy.tag),
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

      Widget section(
        String? header,
        List<OutboundInfo> items, {
        Key? key,
        bool dimmed = false,
        bool? isCollapsed,
        VoidCallback? onHeaderTap,
      }) => _NodeSection(
        key: key,
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

      if (filtering && visible.isEmpty && folded.isEmpty) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: margin + MuseSpace.s4, vertical: MuseSpace.s16),
            child: Text('没有匹配的节点', style: MuseType.body(context).copyWith(color: mt.text2)),
          ),
        );
      }
      final groups = visible.where((e) => e.isGroup).toList();
      final nodes = visible.where((e) => !e.isGroup).toList();
      if (groups.isNotEmpty) children.add(section(null, groups));
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
      if (folded.isNotEmpty) {
        children.add(
          foldToggle(
            key: const ValueKey('hidden_nodes_toggle'),
            icon: Icons.block_outlined,
            label: '不可用 · ${folded.length}',
            open: showHidden.value,
            onTap: () => showHidden.value = !showHidden.value,
            // 1.6.0 #40: hide them all after a preview; 撤销 brings them back
            action: selecting.value
                ? null
                : TextButton(
                    key: const ValueKey('clear_unavailable'),
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    onPressed: () => museClearUnavailable(
                      context,
                      ref,
                      tags: [for (final e in folded) if (!e.isGroup) e.tag],
                      names: {for (final e in folded) e.tag: shownName(e)},
                      unavailable: hidden,
                      selected: group.selected,
                      favorites: favorites,
                    ),
                    child: const Text('清除…'),
                  ),
          ),
        );
        if (showHidden.value || filtering) children.add(section(null, folded, dimmed: true));
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
    final list = CustomScrollView(
      key: listKey,
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: MuseSpace.s4, bottom: embedded ? MuseSpace.s16 : MuseSpace.s32),
          sliver: SliverMainAxisGroup(
            slivers: [for (final c in children) c is _NodeSection ? c.buildSliver(context) : SliverToBoxAdapter(child: c)],
          ),
        ),
      ],
    );
    if (embedded) return list;
    // 1.6.0 #38: the node in use stays on top while the list scrolls
    final inUseNode = pinCurrent && group != null ? group.items.where((e) => e.tag == group.selected).firstOrNull : null;
    Widget pinned(Widget body) => inUseNode == null
        ? body
        : Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(margin, MuseSpace.s4, margin, MuseSpace.s4),
                child: MuseCurrentNodeCard(
                  proxy: inUseNode,
                  name: inUseNode.isGroup ? museNodeName(inUseNode) : shownName(inUseNode),
                  pick: inUseNode.isGroup && inUseNode.groupSelectedTagDisplay.isNotEmpty ? museStripFlags(shownPick(inUseNode.groupSelectedTagDisplay)) : '',
                  region: inUseNode.isGroup ? null : regionOf(inUseNode),
                  delay: museFreshDelay(inUseNode, since),
                  running: running,
                  onTap: () => showMuseNodeDetails(context, ref, inUseNode, since: since, groupTag: group!.tag),
                ),
              ),
              Expanded(child: body),
            ],
          );
    final refresh = RefreshIndicator(
      key: const ValueKey('nodes_pull_refresh'),
      onRefresh: () => museNodePull(ref),
      color: MusePalette.brand,
      notificationPredicate: (n) => hasProfile && n.depth == 0 && !selecting.value,
      child: list,
    );
    if (!selecting.value || group == null) return pinned(refresh);
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
        Expanded(child: pinned(refresh)),
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
  Widget buildSliver(BuildContext context) {
    final mt = MuseTheme.of(context);
    final last = children.length - 1;
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
                    row = ClipRRect(borderRadius: i == 0 && i == last ? MuseRadius.cardAll : (i == 0 ? top : bottom), child: row);
                  }
                  return row;
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
            child: ClipRRect(
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
  });

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

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16, vertical: MuseSpace.s12),
              child: Row(
                children: [
                  if (checked != null)
                    SizedBox(
                      key: ValueKey('node_check_${proxy.tag}'),
                      width: MuseSize.flagBox,
                      height: MuseSize.flagBox,
                      child: Icon(
                        checked! ? Icons.check_circle_outlined : Icons.radio_button_unchecked_outlined,
                        color: checked! ? MusePalette.brand : mt.text3,
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
            if (selected)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(width: MuseSize.selectedBar, child: ColoredBox(color: MusePalette.brand, key: const ValueKey('node_selected_bar'))),
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
        color: onBrand ? MusePalette.white.withValues(alpha: 0.18) : mt.inner,
        borderRadius: MuseRadius.smallAll,
      ),
      child: flag != null
          ? Text(flag!, style: const TextStyle(fontSize: MuseIconSize.flag, height: 1.1))
          : Icon(
              icon,
              key: neutral ? const ValueKey('flag_box_neutral') : null,
              size: MuseIconSize.small,
              color: onBrand ? MusePalette.white : (neutral ? mt.text3 : MusePalette.brand),
            ),
    );
  }
}

/// Long-press a node: full name, protocol, latency and when it was measured, with
/// 收藏 / 只测这个节点 / 复制名称 / 使用此节点.
Future<void> showMuseNodeDetails(
  BuildContext context,
  WidgetRef ref,
  OutboundInfo proxy, {
  required DateTime? since,
  required String groupTag,
}) async {
  final name = museNodeName(proxy);
  final running = ref.read(museRunningProvider);
  final isFavorite = museParseFavorites(ref.read(Preferences.museFavoriteNodes)).contains(proxy.tag);
  final delay = museFreshDelay(proxy, since);
  final testedAt = proxy.hasUrlTestTime() ? proxy.urlTestTime.toDateTime() : null;
  final String delayText;
  if (delay == 0) {
    delayText = '未测速';
  } else if (ConnectionConst.isValidDelay(delay)) {
    delayText = '$delay ms';
  } else {
    delayText = '超时';
  }
  // 1.4.0: address, landing IP, health from the recent 测速 results
  final metas = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
  final meta = metas.of(proxy.tag);
  final region = metas.regionOf(proxy.tag, museRegionCode(name));
  final history = MuseDelayHistories.parse(ref.read(MusePrefs.delayHistory)).of(proxy.tag);
  final health = museHealthScore(history);
  final exitCode = proxy.hasIpinfo() ? proxy.ipinfo.countryCode : '';
  final mismatch = museRegionMismatch(nameRegion: region, exitRegion: exitCode);
  final invalidError = proxy.isGroup ? '' : museInvalidNodeError(proxy.type);
  // 1.5.0 #26 / #10: transport, TLS, ALPN, fingerprint, port hopping from the saved config
  MuseOutboundDetail? detail;
  var configRaw = '';
  if (!proxy.isGroup && invalidError.isEmpty) {
    try {
      configRaw = await ref.refresh(museActiveConfigProvider.future).timeout(const Duration(seconds: 2));
      detail = museOutboundDetail(configRaw, proxy.tag, host: proxy.host, port: proxy.port);
    } catch (_) {}
  }
  // 1.6.0 #30 / #35: share link (二维码) and the copy formats, named as the row shows the node
  final shownName = metas.displayName(proxy.tag, name, beautify: ref.read(MusePrefs.beautifyNames));
  final shareLink = configRaw.isEmpty ? null : museNodeShareLink(configRaw, proxy.tag, name: shownName);
  // 1.6.0 #36: a relay shows where traffic enters and where it leaves
  final relay = proxy.isGroup ? null : museRelayInfo(name, nameRegion: region, exitCode: exitCode);
  // 1.5.0 #24: 下载测速 for the node (or group) in use
  final inUse = running && ref.read(museNodeGroupProvider).valueOrNull?.selected == proxy.tag;
  final mixedPort = ref.read(ConfigOptions.mixedPort);
  if (!context.mounted) return;
  final rows = <(String, String)>[
    (
      '类型',
      proxy.isGroup
          ? (museGroupTypeLabel(proxy.type) ?? '分组')
          : invalidError.isNotEmpty
          ? museInvalidNodeSubtitle(proxy.type)
          : museProtocolName(proxy.type),
    ),
    if (relay != null) ...[
      ('入口', relay.entry.isEmpty ? '中转（入口未知）' : '${relay.entry}（中转）'),
      if (relay.exit != null)
        ('出口', '${museCountryFlag(relay.exit!) ?? ''} ${museCountryLabel(relay.exit!)}${relay.exitFromLanding ? '（落地）' : ''}'.trim()),
    ],
    if (region != null)
      ('地区', '${museCountryFlag(region) ?? ''} ${museCountryLabel(region)}${meta.region.isNotEmpty ? '（手动）' : ''}'.trim()),
    ('延迟', delayText),
    if (testedAt != null && delay != 0) ('测速时间', museUpdatedAgo(testedAt, now: DateTime.now()).replaceAll('更新', '')),
    if (!proxy.isGroup && proxy.host.isNotEmpty) ('地址', '${proxy.host}${proxy.port > 0 ? ':${proxy.port}' : ''}'),
    ...?detail?.rows,
    if (proxy.hasIpinfo() && proxy.ipinfo.ip.isNotEmpty)
      ('落地', '${proxy.ipinfo.ip} ${museCountryFlag(exitCode) ?? exitCode}${mismatch ? ' · 名不符实' : ''}'.trim()),
    if (history.samples.length >= 2)
      (
        '健康',
        '${museHealthLabel(health)} $health · 丢包 ${(history.loss * 100).round()}% · 抖动 ${history.jitter.round()} ms',
      ),
    if (meta.note.isNotEmpty) ('备注', meta.note),
    if (meta.tags.isNotEmpty) ('标签', meta.tags.join('、')),
  ];
  // 1.6.0 #29: the last 10 delays as a mini line
  final spark = museSparkline(history.samples);
  Future<void> saveMeta(MuseNodeMeta next) async {
    final cur = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
    await ref.read(MusePrefs.nodeMeta.notifier).update(cur.set(proxy.tag, next).toRaw());
  }

  void toast(String text, {bool error = false}) {
    try {
      final n = ref.read(inAppNotificationControllerProvider);
      error ? n.showErrorToast(text) : n.showSuccessToast(text);
    } catch (_) {}
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: MuseColors.card(context),
    builder: (sheetContext) {
      final mt = MuseTheme.of(sheetContext);
      return SafeArea(
        // 1.5.0: scrolls when the rows don't fit (small phones, large text)
        child: SingleChildScrollView(
          key: const ValueKey('node_detail_sheet'),
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(name, style: MuseType.title(sheetContext)),
              const SizedBox(height: MuseSpace.s12),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: MuseSize.labelColumn, child: Text(k, style: MuseType.body(sheetContext).copyWith(color: mt.text2))),
                      Expanded(child: Text(v, style: MuseType.body(sheetContext))),
                    ],
                  ),
                ),
              // full core error of a node that could not start, selectable and copyable
              if (invalidError.isNotEmpty) ...[
                const SizedBox(height: MuseSpace.s8),
                Container(
                  key: const ValueKey('node_error_box'),
                  padding: const EdgeInsets.all(MuseSpace.s12),
                  decoration: BoxDecoration(color: MusePalette.red.withValues(alpha: 0.08), borderRadius: MuseRadius.smallAll),
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(child: SelectableText(invalidError, style: MuseType.caption(sheetContext))),
                ),
                const SizedBox(height: MuseSpace.s8),
                OutlinedButton.icon(
                  key: const ValueKey('node_copy_error'),
                  icon: const Icon(Icons.copy_all_outlined, size: MuseIconSize.small),
                  label: const Text('复制错误详情'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: '$name\n$invalidError'));
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                    toast('已复制');
                  },
                ),
              ],
              if (spark.length >= 2) ...[
                const SizedBox(height: MuseSpace.s8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: MuseSize.labelColumn,
                      child: Text('最近 ${spark.length} 次', style: MuseType.body(sheetContext).copyWith(color: mt.text2)),
                    ),
                    Expanded(child: MuseSparkline(points: spark)),
                  ],
                ),
              ],
              if (inUse) ...[
                const SizedBox(height: MuseSpace.s8),
                MuseDownloadTestRow(port: mixedPort),
              ],
              const SizedBox(height: MuseSpace.s16),
              if (!proxy.isGroup) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_favorite'),
                        icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outlined, size: MuseIconSize.small),
                        label: Text(isFavorite ? '取消收藏' : '收藏'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final raw = ref.read(Preferences.museFavoriteNodes);
                          await ref.read(Preferences.museFavoriteNodes.notifier).update(museToggleFavorite(raw, proxy.tag));
                        },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_test_one'),
                        icon: const Icon(Icons.speed_outlined, size: MuseIconSize.small),
                        label: const Text('只测这个节点'),
                        onPressed: !running
                            ? null
                            : () async {
                                Navigator.of(sheetContext).pop();
                                try {
                                  // the core tests a single outbound when given its tag
                                  await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(proxy.tag);
                                } catch (_) {
                                  toast('测速失败，请重试', error: true);
                                }
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_rename'),
                        icon: const Icon(Icons.edit_outlined, size: MuseIconSize.small),
                        label: const Text('重命名'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final v = await museAskText(context, '重命名', initial: meta.rename.isEmpty ? name : meta.rename);
                          if (v != null) await saveMeta(meta.copyWith(rename: v == museNodeName(proxy) ? '' : v));
                        },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_note'),
                        icon: const Icon(Icons.sticky_note_2_outlined, size: MuseIconSize.small),
                        label: const Text('备注'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final v = await museAskText(context, '备注', initial: meta.note);
                          if (v != null) await saveMeta(meta.copyWith(note: v));
                        },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_hide'),
                        icon: Icon(meta.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: MuseIconSize.small),
                        label: Text(meta.hidden ? '显示' : '隐藏'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await saveMeta(meta.copyWith(hidden: !meta.hidden));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_set_region'),
                        icon: const Icon(Icons.flag_outlined, size: MuseIconSize.small),
                        label: const Text('指定地区'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final v = await museAskRegion(context, current: meta.region);
                          if (v != null) await saveMeta(meta.copyWith(region: v));
                        },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_set_tags'),
                        icon: const Icon(Icons.sell_outlined, size: MuseIconSize.small),
                        label: const Text('标签'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final v = await museAskNodeTags(context, current: meta.tags, known: metas.allTags);
                          if (v != null) await saveMeta(meta.copyWith(tags: v));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s12),
              ],
              if (!proxy.isGroup && invalidError.isEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_qr'),
                        icon: const Icon(Icons.qr_code_2_outlined, size: MuseIconSize.small),
                        label: const Text('二维码'),
                        onPressed: shareLink == null
                            ? null
                            : () async {
                                Navigator.of(sheetContext).pop();
                                await showMuseQrDialog(context, title: shownName, data: shareLink);
                              },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_copy_as'),
                        icon: const Icon(Icons.ios_share_outlined, size: MuseIconSize.small),
                        label: const Text('复制节点'),
                        onPressed: configRaw.isEmpty
                            ? null
                            : () async {
                                Navigator.of(sheetContext).pop();
                                final copied = await museCopyNodeAs(context, raw: configRaw, tag: proxy.tag, name: shownName);
                                if (copied != null) toast('已复制${copied.label}');
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('node_copy_name'),
                      icon: const Icon(Icons.copy_outlined, size: MuseIconSize.small),
                      label: const Text('复制名称'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: name));
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        toast('已复制');
                      },
                    ),
                  ),
                  const SizedBox(width: MuseSpace.s12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('node_use'),
                      icon: const Icon(Icons.check_outlined, size: MuseIconSize.small),
                      label: const Text('使用此节点'),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await musePickNode(ref, groupTag, proxy.tag);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The node picker opened from the 首页 hero card (works while disconnected too).
Future<void> showMuseNodePicker(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: MuseTheme.of(context).bgBottom,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    builder: (_, controller) => Column(
      key: const ValueKey('node_picker_sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s8),
          child: Text('选择节点', style: MuseType.title(sheetContext)),
        ),
        Expanded(
          child: MuseNodeList(
            controller: controller,
            embedded: true,
            onPicked: () {
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
          ),
        ),
      ],
    ),
  ),
);

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

/// A one-line text prompt; null when cancelled, '' allowed (clears the value).
/// 1.4.1: the dialog owns (and disposes) its text controller; [obscure] hides a password.
Future<String?> museAskText(
  BuildContext context,
  String title, {
  String initial = '',
  String? hint,
  int maxLines = 1,
  bool obscure = false,
}) => showDialog<String>(
  context: context,
  builder: (c) => _MuseAskTextDialog(title: title, initial: initial, hint: hint, maxLines: obscure ? 1 : maxLines, obscure: obscure),
);

class _MuseAskTextDialog extends StatefulWidget {
  const _MuseAskTextDialog({required this.title, required this.initial, this.hint, required this.maxLines, required this.obscure});

  final String title;
  final String initial;
  final String? hint;
  final int maxLines;
  final bool obscure;

  @override
  State<_MuseAskTextDialog> createState() => _MuseAskTextDialogState();
}

class _MuseAskTextDialogState extends State<_MuseAskTextDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  late bool _hidden = widget.obscure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: MuseSize.dialogText,
      child: TextField(
        key: const ValueKey('ask_text_field'),
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        obscureText: _hidden,
        autocorrect: !widget.obscure,
        enableSuggestions: !widget.obscure,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: widget.obscure
              ? IconButton(
                  key: const ValueKey('ask_text_reveal'),
                  icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidden = !_hidden),
                )
              : null,
        ),
        onSubmitted: widget.maxLines == 1 ? (v) => Navigator.of(context).pop(v.trim()) : null,
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      FilledButton(
        key: const ValueKey('ask_text_ok'),
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('确定'),
      ),
    ],
  );
}

/// 1.5.0 #24: 下载测速 (5 MB through the node in use) inside the node detail sheet; closing the
/// sheet stops it.
class MuseDownloadTestRow extends StatefulWidget {
  const MuseDownloadTestRow({super.key, required this.port});

  final int port;

  @override
  State<MuseDownloadTestRow> createState() => _MuseDownloadTestRowState();
}

class _MuseDownloadTestRowState extends State<MuseDownloadTestRow> {
  MuseSpeedTest? _test;
  String? _result;
  bool _failed = false;

  Future<void> _run() async {
    final test = MuseSpeedTest(port: widget.port);
    setState(() {
      _test = test;
      _result = null;
      _failed = false;
    });
    try {
      final bps = await test.run();
      if (!mounted) return;
      setState(() => _result = museSpeedText(bps));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _result = '下载测速失败：$e';
      });
    } finally {
      if (mounted) setState(() => _test = null);
    }
  }

  @override
  void dispose() {
    _test?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final running = _test != null;
    return Row(
      key: const ValueKey('node_download_test'),
      children: [
        Expanded(
          child: Text(
            running ? '正在下载 5 MB…' : (_result ?? '下载测速（约 5 MB 流量）'),
            style: MuseType.body(context).copyWith(
              color: _failed ? MusePalette.red : (_result == null || running ? mt.text2 : null),
              fontFeatures: MuseType.tabular,
            ),
          ),
        ),
        const SizedBox(width: MuseSpace.s8),
        TextButton(
          key: const ValueKey('node_download_test_button'),
          onPressed: running ? () => _test?.cancel() : _run,
          child: Text(running ? '停止' : (_result == null ? '开始' : '再测')),
        ),
      ],
    );
  }
}

/// 1.6.0 #29: the last delays of a node as a small line (gaps where a test got no answer).
class MuseSparkline extends StatelessWidget {
  const MuseSparkline({super.key, required this.points});

  /// heights 0–1 (1 = slowest), null = no answer (logic/node_tools.dart museSparkline)
  final List<double?> points;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('node_sparkline'),
    height: MuseSize.sparkHeight,
    child: CustomPaint(painter: _SparkPainter(points, MusePalette.brand, MusePalette.red), size: Size.infinite),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color, this.missColor);

  final List<double?> points;
  final Color color;
  final Color missColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final line = Paint()
      ..color = color
      ..strokeWidth = MuseSize.sparkStroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color;
    final miss = Paint()..color = missColor;
    final step = size.width / (points.length - 1);
    final pad = MuseSize.sparkDot;
    final h = size.height - pad * 2;
    Offset? prev;
    for (var i = 0; i < points.length; i++) {
      final v = points[i];
      final x = i * step;
      if (v == null) {
        canvas.drawCircle(Offset(x.clamp(pad, size.width - pad), size.height - pad), pad, miss);
        prev = null;
        continue;
      }
      // faster = higher on the line
      final p = Offset(x, pad + h * v);
      if (prev != null) canvas.drawLine(prev, p, line);
      canvas.drawCircle(Offset(x.clamp(pad, size.width - pad), p.dy), pad, dot);
      prev = p;
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.points.join(',') != points.join(',') || old.color != color;
}

/// 1.6.0 #32: pick a node's region by hand; '' = 按名称自动识别, null = cancelled.
Future<String?> museAskRegion(BuildContext context, {String current = ''}) => showDialog<String>(
  context: context,
  builder: (c) => SimpleDialog(
    key: const ValueKey('node_region_dialog'),
    title: const Text('指定地区'),
    children: [
      SimpleDialogOption(
        key: const ValueKey('node_region_auto'),
        onPressed: () => Navigator.of(c).pop(''),
        child: Text('按名称自动识别${current.isEmpty ? '（当前）' : ''}'),
      ),
      for (final e in museCountryNames.entries)
        SimpleDialogOption(
          key: ValueKey('node_region_${e.key}'),
          onPressed: () => Navigator.of(c).pop(e.key),
          child: Text('${museCountryFlag(e.key) ?? ''} ${e.value}${current == e.key ? '（当前）' : ''}'.trim()),
        ),
    ],
  ),
);

/// 1.6.0 #33: choose a node's tags (presets + ones already used + a new one); null = cancelled.
Future<List<String>?> museAskNodeTags(BuildContext context, {required List<String> current, required List<String> known}) =>
    showDialog<List<String>>(
      context: context,
      builder: (c) => _MuseTagDialog(current: current, known: known),
    );

class _MuseTagDialog extends StatefulWidget {
  const _MuseTagDialog({required this.current, required this.known});

  final List<String> current;
  final List<String> known;

  @override
  State<_MuseTagDialog> createState() => _MuseTagDialogState();
}

class _MuseTagDialogState extends State<_MuseTagDialog> {
  late final List<String> _all = [...museCleanNodeTags([...museNodeTagPresets, ...widget.known, ...widget.current], max: 64)];
  late final Set<String> _on = {...widget.current};
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final v = museCleanNodeTags([_text.text]);
    if (v.isEmpty) return;
    setState(() {
      if (!_all.contains(v.first)) _all.add(v.first);
      _on.add(v.first);
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('node_tags_dialog'),
    title: const Text('标签'),
    content: SizedBox(
      width: MuseSize.dialogText,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: MuseSpace.s8,
            runSpacing: MuseSpace.s8,
            children: [
              for (final t in _all)
                FilterChip(
                  key: ValueKey('node_tag_$t'),
                  label: Text(t),
                  selected: _on.contains(t),
                  onSelected: (v) => setState(() => v ? _on.add(t) : _on.remove(t)),
                ),
            ],
          ),
          const SizedBox(height: MuseSpace.s12),
          TextField(
            key: const ValueKey('node_tag_new'),
            controller: _text,
            maxLength: 12,
            decoration: InputDecoration(
              isDense: true,
              hintText: '新标签，如 低倍率',
              suffixIcon: IconButton(key: const ValueKey('node_tag_add'), icon: const Icon(Icons.add_outlined), onPressed: _add),
            ),
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      FilledButton(
        key: const ValueKey('node_tags_save'),
        onPressed: () => Navigator.of(context).pop([for (final t in _all) if (_on.contains(t)) t]),
        child: const Text('保存'),
      ),
    ],
  );
}
