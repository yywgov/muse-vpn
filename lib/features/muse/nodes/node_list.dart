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
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    } else {
      final profileId = ref.read(museActiveProfileIdProvider);
      if (profileId == null) return;
      final raw = ref.read(Preferences.museLastNodes);
      await ref.read(Preferences.museLastNodes.notifier).update(museRememberNode(raw, profileId, tag));
    }
  } catch (_) {
    try {
      ref.read(inAppNotificationControllerProvider).showErrorToast('切换节点失败，请重试');
    } catch (_) {}
  }
}

String museNodeName(OutboundInfo e) => e.tagDisplay.isNotEmpty ? e.tagDisplay : e.tag;

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
    final showHidden = useState(false);
    final hidden = running ? ref.watch(museHiddenNodesProvider) : const <String>{};
    final searching = useState(false);
    final query = useState('');
    final searchController = useTextEditingController();
    final sortMode = MuseNodeSort.fromKey(ref.watch(Preferences.museNodeSort));
    final favorites = museParseFavorites(ref.watch(Preferences.museFavoriteNodes));
    // 1.4.1: 多选 (测速 / 收藏 / 隐藏 / 复制名称 for several nodes at once)
    final selecting = useState(false);
    final picked = useState<Set<String>>(const {});
    // 1.4.0: rename / note / hide, name filters, duplicates, collapsible regions
    final metas = MuseNodeMetas.parse(ref.watch(MusePrefs.nodeMeta));
    final beautify = ref.watch(MusePrefs.beautifyNames);
    final includeRe = ref.watch(MusePrefs.includeRegex);
    final excludeRe = ref.watch(MusePrefs.excludeRegex);
    final hideDuplicates = ref.watch(MusePrefs.hideDuplicates);
    final collapsedRaw = ref.watch(MusePrefs.collapsedRegions);
    final collapsed = collapsedRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final showUserHidden = useState(false);
    String shownName(OutboundInfo e) => metas.displayName(e.tag, museNodeName(e), beautify: beautify);

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
              group == null ? '' : (selecting.value ? '已选 ${picked.value.length} 个' : '$nodeTotal 个节点'),
              key: const ValueKey('node_count_label'),
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
          if (nodeTotal > 1)
            PopupMenuButton<MuseNodeSort>(
              key: const ValueKey('node_sort_button'),
              tooltip: '排序：${sortMode.title}',
              icon: const Icon(Icons.sort_outlined, size: MuseIconSize.small),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              initialValue: sortMode,
              onSelected: (m) => ref.read(Preferences.museNodeSort.notifier).update(m.key),
              itemBuilder: (context) => [
                for (final m in MuseNodeSort.values)
                  CheckedPopupMenuItem<MuseNodeSort>(
                    key: ValueKey('node_sort_${m.key}'),
                    value: m,
                    checked: m == sortMode,
                    child: Text(m.title),
                  ),
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
              title: proxies.hasError ? '读取节点失败' : (hasProfile ? '暂无节点' : '还没有订阅'),
            ),
          ],
        ),
      );
    } else {
      final duplicates = hideDuplicates
          ? museDuplicateTags<OutboundInfo>(
              group.items.where((e) => !e.isGroup).toList(),
              tag: (e) => e.tag,
              type: (e) => e.type,
              host: (e) => e.host,
              port: (e) => e.port,
            )
          : const <String>{};
      final listed = group.items
          .where(
            (e) =>
                e.isGroup ||
                e.tag == group.selected ||
                (!museIsInfoNode(museNodeName(e)) &&
                    !duplicates.contains(e.tag) &&
                    museNodeNamePasses(museNodeName(e), include: includeRe, exclude: excludeRe)),
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
          region: (e) => museRegionCode(museNodeName(e)),
        ),
        isGroup: (e) => e.isGroup,
        tag: (e) => e.tag,
        favorites: favorites,
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
        note: proxy.isGroup ? '' : metas.of(proxy.tag).note,
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

      Future<void> toggleRegion(String code) async {
        final next = {...collapsed};
        if (!next.remove(code)) next.add(code);
        await ref.read(MusePrefs.collapsedRegions.notifier).update(next.join(','));
      }

      Widget foldToggle({required Key key, required IconData icon, required String label, required bool open, required VoidCallback onTap}) =>
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
        for (final s in museRegionSections<OutboundInfo>(
          nodes.where((e) => !favorites.contains(e.tag)).toList(),
          isGroup: (e) => e.isGroup,
          region: (e) => museRegionCode(museNodeName(e)),
        )) {
          final code = s.region;
          final label = code == null ? '其他' : '${museCountryFlag(code) ?? ''} ${museCountryLabel(code)}'.trim();
          // 1.4.0: the header shows the group's best delay; tap folds the group
          final best = s.items
              .map((e) => museFreshDelay(e, since))
              .where(ConnectionConst.isValidDelay)
              .fold<int>(0, (a, b) => a == 0 || b < a ? b : a);
          final key = code ?? 'other';
          children.add(
            section(
              '$label · ${s.items.length}${best > 0 ? ' · $best ms' : ''}',
              s.items,
              key: ValueKey('region_header_$key'),
              isCollapsed: !filtering && collapsed.contains(key),
              onHeaderTap: () => toggleRegion(key),
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

    final list = ListView(
      key: listKey,
      controller: controller,
      padding: EdgeInsets.only(top: MuseSpace.s4, bottom: embedded ? MuseSpace.s16 : MuseSpace.s32),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: children,
    );
    if (embedded) return list;
    final refresh = RefreshIndicator(
      key: const ValueKey('nodes_pull_refresh'),
      onRefresh: () => museNodePull(ref),
      color: MusePalette.brand,
      notificationPredicate: (n) => hasProfile && n.depth == 0 && !selecting.value,
      child: list,
    );
    if (!selecting.value || group == null) return refresh;
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
        Expanded(child: refresh),
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
  });

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
    final subtitle = proxy.isGroup
        ? museGroupSubtitle(type: proxy.type, name: rawName, selectedDisplay: proxy.groupSelectedTagDisplay, nodeCount: nodeCount)
        : museIsInvalidNodeType(proxy.type)
        ? museInvalidNodeSubtitle(proxy.type)
        : note.isNotEmpty
        ? '${museProtocolName(proxy.type)} · $note'
        : museProtocolName(proxy.type);
    final groupIcon = proxy.isGroup
        ? switch (museGroupIconKind(type: proxy.type, name: rawName, selectedDisplay: proxy.groupSelectedTagDisplay)) {
            MuseGroupIcon.autoFastest => Icons.bolt_outlined,
            MuseGroupIcon.loadBalance => Icons.balance_outlined,
            MuseGroupIcon.manual => Icons.touch_app_outlined,
            MuseGroupIcon.fallback => Icons.alt_route_outlined,
            MuseGroupIcon.other => Icons.folder_outlined,
          }
        : Icons.public_outlined;
    final flag = proxy.isGroup ? null : (museFlagEmoji(name) ?? museFlagEmoji(museNodeName(proxy)));

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
                    MuseFlagBox(flag: flag, icon: groupIcon),
                  const SizedBox(width: MuseSpace.s12),
                  Expanded(
                    child: Column(
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
                          ],
                        ),
                        if (subtitle.isNotEmpty)
                          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.caption(context)),
                      ],
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

/// 32 dp rounded square with a flag emoji (or an icon for groups).
class MuseFlagBox extends StatelessWidget {
  const MuseFlagBox({super.key, this.flag, this.icon = Icons.public_outlined, this.onBrand = false});

  final String? flag;
  final IconData icon;

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
          : Icon(icon, size: MuseIconSize.small, color: onBrand ? MusePalette.white : MusePalette.brand),
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
  final region = museRegionCode(name);
  // 1.4.0: address, landing IP, health from the recent 测速 results
  final metas = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
  final meta = metas.of(proxy.tag);
  final history = MuseDelayHistories.parse(ref.read(MusePrefs.delayHistory)).of(proxy.tag);
  final health = museHealthScore(history);
  final exitCode = proxy.hasIpinfo() ? proxy.ipinfo.countryCode : '';
  final mismatch = museRegionMismatch(nameRegion: region, exitRegion: exitCode);
  final invalidError = proxy.isGroup ? '' : museInvalidNodeError(proxy.type);
  final rows = <(String, String)>[
    (
      '类型',
      proxy.isGroup
          ? (museGroupTypeLabel(proxy.type) ?? '分组')
          : invalidError.isNotEmpty
          ? museInvalidNodeSubtitle(proxy.type)
          : museProtocolName(proxy.type),
    ),
    if (region != null) ('地区', '${museCountryFlag(region) ?? ''} ${museCountryLabel(region)}'.trim()),
    ('延迟', delayText),
    if (testedAt != null && delay != 0) ('测速时间', museUpdatedAgo(testedAt, now: DateTime.now()).replaceAll('更新', '')),
    if (!proxy.isGroup && proxy.host.isNotEmpty) ('地址', '${proxy.host}${proxy.port > 0 ? ':${proxy.port}' : ''}'),
    if (proxy.hasIpinfo() && proxy.ipinfo.ip.isNotEmpty)
      ('落地', '${proxy.ipinfo.ip} ${museCountryFlag(exitCode) ?? exitCode}${mismatch ? ' · 名不符实' : ''}'.trim()),
    if (history.samples.length >= 2)
      (
        '健康',
        '${museHealthLabel(health)} $health · 丢包 ${(history.loss * 100).round()}% · 抖动 ${history.jitter.round()} ms',
      ),
    if (meta.note.isNotEmpty) ('备注', meta.note),
  ];
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
        child: Padding(
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
