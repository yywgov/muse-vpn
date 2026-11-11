// 穿云 1.6.0 C3 - 连接: live connections (search, sort, close one / all, details, 屏蔽此域名) and
// 请求 (connections that ended, newest first). Lists are lazy with a fixed row height; a frame
// only rebuilds the list, rows are cheap. A local API failure shows 「暂不可用」 and never touches
// the connection state.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/connections/conn_app.dart';
import 'package:hiddify/features/muse/logic/route_why.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/data/quick_rules_provider.dart';
import 'package:hiddify/features/muse/logic/quick_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart' show museSpeedText;
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_card.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart' show museFormatDuration;
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Row height of a connection (fixed: the list uses itemExtent).
const museConnRowHeight = MuseSize.rowMin + MuseSpace.s16;

final museConnSortProvider = StateProvider<MuseConnSort>((ref) => MuseConnSort.speed);

class MuseConnectionsPage extends HookConsumerWidget {
  const MuseConnectionsPage({super.key, this.header});

  /// 1.8.0: inside 活动 the tab switch sits on top and the page is titled 活动
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = useState(0);
    final query = useState('');
    final sort = ref.watch(museConnSortProvider);
    final state = ref.watch(museConnectionsProvider).valueOrNull ?? const MuseConnState(loading: true);
    final history = ref.watch(museRequestHistoryProvider);
    final api = ref.watch(museLocalApiProvider);
    final live = museSortConns(state.connections, sort, query: query.value);
    final ended = tab.value == 1 ? museSortConns(history.items, MuseConnSort.duration, query: query.value).reversed.toList() : const <MuseConn>[];
    final list = tab.value == 0 ? live : ended;
    final scheme = Theme.of(context).colorScheme;

    Future<void> closeAll() async {
      if (api == null) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('关闭全部连接？'),
          content: const Text('正在进行的下载、视频和网页会中断，应用会自动重新连接。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('关闭全部', style: TextStyle(color: scheme.destructive))),
          ],
        ),
      );
      if (ok == true) await api.closeAll();
    }

    return MuseScaffold(
      title: header == null ? '连接' : '活动',
      actions: [
        PopupMenuButton<MuseConnSort>(
          key: const ValueKey('conn_sort'),
          tooltip: '排序',
          icon: const Icon(Icons.sort_outlined),
          initialValue: sort,
          onSelected: (s) => ref.read(museConnSortProvider.notifier).state = s,
          itemBuilder: (_) => [for (final s in MuseConnSort.values) PopupMenuItem(value: s, child: Text('按${s.title}'))],
        ),
        if (tab.value == 0)
          IconButton(key: const ValueKey('conn_close_all'), tooltip: '关闭全部', icon: const Icon(Icons.clear_all_outlined), onPressed: live.isEmpty ? null : closeAll)
        else
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: history.length == 0
                ? null
                : () {
                    history.clear();
                    ref.invalidate(museRequestHistoryProvider);
                  },
          ),
      ],
      // 1.10.2: on a short screen (a phone held sideways) the 活动 tabs, the summary, 进行中 / 请求
      // and the search field did not fit above the list (overflowed by a few pixels); there they now
      // scroll together with the list. Taller screens keep them fixed above it as before.
      body: LayoutBuilder(
        builder: (context, box) {
          final pad = MuseSpace.page(context);
          final top = Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, MuseSpace.s8),
            child: Column(
              children: [
                _Summary(state: state, ended: history.length),
                const SizedBox(height: MuseSpace.s8),
                SegmentedButton<int>(
                  key: const ValueKey('conn_tabs'),
                  segments: [
                    ButtonSegment(value: 0, label: Text('进行中 ${state.connections.length}')),
                    ButtonSegment(value: 1, label: Text('请求 ${history.length}')),
                  ],
                  selected: {tab.value},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => tab.value = s.first,
                ),
                const SizedBox(height: MuseSpace.s8),
                TextField(
                  key: const ValueKey('conn_search'),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_outlined), hintText: '搜索主机、规则、节点或进程', isDense: true),
                  onChanged: (v) => query.value = v,
                ),
              ],
            ),
          );
          final empty = state.error != null && tab.value == 0
              ? _Empty(icon: Icons.cloud_off_outlined, text: state.error == '未连接' ? '连接后可查看实时连接' : '暂不可用（${state.error}）')
              : list.isEmpty
              ? _Empty(icon: Icons.swap_vert_outlined, text: state.loading && tab.value == 0 ? '正在读取…' : (query.value.isEmpty ? '暂无连接' : '没有匹配的连接'))
              : null;
          final listPad = EdgeInsets.fromLTRB(pad, 0, pad, museScrollEndGap(context, MuseSize.fabClearance));
          final wide = MediaQuery.sizeOf(context).width > MuseBreak.laptop;
          if (museConnCompactHeight(box.maxHeight)) {
            return CustomScrollView(
              key: const ValueKey('conn_list'),
              slivers: [
                if (header case final h?) SliverToBoxAdapter(child: h),
                SliverToBoxAdapter(child: top),
                if (empty != null)
                  SliverFillRemaining(hasScrollBody: false, child: empty)
                else
                  SliverPadding(
                    padding: listPad,
                    sliver: SliverFixedExtentList(
                      itemExtent: museConnRowHeight,
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => MuseConnRow(conn: list[i], ended: tab.value == 1, wide: wide),
                        childCount: list.length,
                      ),
                    ),
                  ),
              ],
            );
          }
          return Column(
            children: [
              ?header,
              top,
              Expanded(
                child: empty ??
                    ListView.builder(
                      key: const ValueKey('conn_list'),
                      itemExtent: museConnRowHeight,
                      padding: listPad,
                      itemCount: list.length,
                      itemBuilder: (_, i) => MuseConnRow(conn: list[i], ended: tab.value == 1, wide: wide),
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 1.10.2: below this height (a phone held sideways) the 连接 page scrolls its header with the list.
bool museConnCompactHeight(double height) => height < 400;

class _Summary extends StatelessWidget {
  const _Summary({required this.state, required this.ended});

  final MuseConnState state;
  final int ended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final up = state.connections.fold<int>(0, (a, c) => a + c.upSpeed);
    final down = state.connections.fold<int>(0, (a, c) => a + c.downSpeed);
    Widget cell(String k, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: MuseTextLevel.caption1.style(context, color: scheme.onSurfaceVariant)),
          Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseTextLevel.headline.style(context)),
        ],
      ),
    );
    return MuseCard(
      key: const ValueKey('conn_summary'),
      child: Row(
        children: [
          cell('进行中', '${state.connections.length}'),
          cell('↑ 上传', museSpeedText(up)),
          cell('↓ 下载', museSpeedText(down)),
          cell('本次合计', (state.frame.uploadTotal + state.frame.downloadTotal).size()),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: MuseSize.emptyIcon, color: scheme.onSurfaceVariant),
          const SizedBox(height: MuseSpace.s8),
          Text(text, textAlign: TextAlign.center, style: MuseTextLevel.subheadline.style(context, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// One connection: host, chain · rule, speed / total, duration.
class MuseConnRow extends ConsumerWidget {
  const MuseConnRow({super.key, required this.conn, this.ended = false, this.wide = false});

  final MuseConn conn;
  final bool ended;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dur = (conn.end ?? DateTime.now()).difference(conn.start);
    // 1.15.0 R16: 发起的应用（内核报告了进程时）——图标 + 名称
    final app = conn.process.isEmpty ? null : museConnApp(conn.process, ref.watch(museAppLabelsProvider).valueOrNull ?? const {});
    final sub = [if (app != null) app.name, if (conn.node.isNotEmpty) conn.node, if (conn.rule.isNotEmpty) conn.rule].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: MuseSpace.s4),
      child: MuseCard(
        padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s8),
        radius: MuseRadiusScale.md,
        onTap: () => showMuseConnDetail(context, ref, conn, ended: ended),
        child: Row(
          children: [
            if (app != null) ...[MuseConnAppIcon(app: app), const SizedBox(width: MuseSpace.s8)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(conn.host.isEmpty ? conn.destination : conn.host, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseTextLevel.callout.style(context, weight: FontWeight.w600)),
                  Text(sub.isEmpty ? conn.network : sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseTextLevel.caption1.style(context, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: MuseSpace.s8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(ended ? conn.total.size() : (conn.speed > 0 ? museSpeedText(conn.speed) : conn.total.size()), style: MuseTextLevel.footnote.style(context)),
                Text(museFormatDuration(dur), style: MuseTextLevel.caption1.style(context, color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showMuseConnDetail(BuildContext context, WidgetRef ref, MuseConn c, {bool ended = false}) {
  final n = ref.read(inAppNotificationControllerProvider);
  return showMuseSnapSheet<void>(
    context,
    title: '连接详情',
    builder: (ctx, controller) {
      final scheme = Theme.of(ctx).colorScheme;
      final why = museRouteWhy(c);
      Widget kv(String k, String v) => v.isEmpty
          ? const SizedBox.shrink()
          : MuseTile(
              title: k,
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: MuseSize.sideColumn - MuseSize.labelColumnWide),
                child: SelectableText(v, textAlign: TextAlign.end, style: MuseTextLevel.subheadline.style(ctx)),
              ),
            );
      return ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, museScrollEndGap(ctx, MuseSpace.s24)),
        children: [
          if (c.host.isNotEmpty)
            FilledButton.icon(
              key: const ValueKey('conn_block'),
              style: FilledButton.styleFrom(backgroundColor: scheme.destructive, foregroundColor: MusePalette.white),
              icon: const Icon(Icons.block_outlined),
              label: Text('屏蔽 ${museBlockTarget(c.host)}'),
              onPressed: () async {
                await museBlockHost(ref, c.host);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          // 1.12.0: 一键加规则 — 直连 / 走代理 / 走指定节点，可选仅本次
          if (c.host.isNotEmpty) ...[
            const SizedBox(height: MuseSpace.s8),
            MuseConnRuleButtons(host: c.host, onDone: () => Navigator.pop(ctx)),
          ],
          const SizedBox(height: MuseSpace.s8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制主机'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: c.host));
                    n.showSuccessToast('已复制');
                  },
                ),
              ),
              if (!ended) ...[
                const SizedBox(width: MuseSpace.s8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('conn_close_one'),
                    icon: const Icon(Icons.link_off_outlined),
                    label: const Text('关闭连接'),
                    onPressed: () async {
                      final api = ref.read(museLocalApiProvider);
                      final ok = await api?.closeConnection(c.id).catchError((_) => false) ?? false;
                      if (ctx.mounted) Navigator.pop(ctx);
                      ok ? n.showSuccessToast('已关闭') : n.showErrorToast('暂不可用');
                    },
                  ),
                ),
              ],
            ],
          ),
          // 1.15.0 R24: 为什么走这条 — 命中的规则 → 出站 → 节点
          MuseSectionGroup(
            key: const ValueKey('conn_why'),
            title: '为什么走这条',
            summary: why.summary,
            children: [
              kv('命中规则', why.rule),
              kv('出站', why.outbound),
              kv('节点', why.node),
            ],
          ),
          MuseSectionGroup(
            title: '详情',
            children: [
              kv('主机', c.host),
              kv('目标', c.destination),
              kv('协议', c.network),
              kv('入站', c.inbound),
              kv('链路', c.chains.reversed.join(' → ')),
              kv('规则', c.rule),
              kv('应用', museConnApp(c.process, ref.read(museAppLabelsProvider).valueOrNull ?? const {})?.name ?? ''),
              kv('进程', c.process),
              kv('上传', c.upload.size()),
              kv('下载', c.download.size()),
              kv('开始', _time(c.start)),
              if (c.end != null) kv('结束', _time(c.end!)),
            ],
          ),
        ],
      );
    },
  );
}

String _time(DateTime t) =>
    '${t.month}-${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// What 屏蔽 adds for [host]: the host itself (sub-domains included).
String museBlockTarget(String host) => host.trim().toLowerCase();

/// Adds a 拦截 rule for [host] (hot-reloaded while connected); the toast can undo it.
Future<void> museBlockHost(WidgetRef ref, String host) async {
  final notifier = ref.read(MusePrefs.blockedHosts.notifier);
  final before = museParseBlockedHosts(ref.read(MusePrefs.blockedHosts));
  final after = museAddBlockedHost(before, museBlockTarget(host));
  if (identical(after, before)) {
    ref.read(inAppNotificationControllerProvider).showInfoToast('已在屏蔽列表中');
    return;
  }
  await notifier.update(museBlockedHostsToRaw(after));
  ref.read(inAppNotificationControllerProvider).showSuccessToast(
    '已屏蔽 ${museBlockTarget(host)}',
    action: (label: '撤销', onPressed: () => notifier.update(museBlockedHostsToRaw(before))),
  );
}


/// 1.12.0: 连接详情里的「直连 / 走代理 / 走指定节点」+「仅本次」。
class MuseConnRuleButtons extends ConsumerStatefulWidget {
  const MuseConnRuleButtons({super.key, required this.host, required this.onDone});

  final String host;
  final VoidCallback onDone;

  @override
  ConsumerState<MuseConnRuleButtons> createState() => _MuseConnRuleButtonsState();
}

class _MuseConnRuleButtonsState extends ConsumerState<MuseConnRuleButtons> {
  bool once = false;

  @override
  Widget build(BuildContext context) {
    final target = museBlockTarget(widget.host);
    Widget button(String key, IconData icon, String label, Future<void> Function() run) => Expanded(
      child: OutlinedButton.icon(
        key: ValueKey(key),
        icon: Icon(icon, size: MuseIconSize.small),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: () async {
          await run();
          widget.onDone();
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('让 $target 以后：', style: MuseType.caption(context)),
        const SizedBox(height: MuseSpace.s4),
        Row(
          children: [
            button('conn_rule_direct', Icons.alt_route_outlined, '直连', () => museAddQuickRule(ref, target, MuseQuickWay.direct, once: once)),
            const SizedBox(width: MuseSpace.s8),
            button('conn_rule_proxy', Icons.vpn_lock_outlined, '走代理', () => museAddQuickRule(ref, target, MuseQuickWay.proxy, once: once)),
            const SizedBox(width: MuseSpace.s8),
            button('conn_rule_node', Icons.dns_outlined, '指定节点', () => museAddHostToNode(context, ref, target, once: once)),
          ],
        ),
        CheckboxListTile(
          key: const ValueKey('conn_rule_once'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: once,
          onChanged: (v) => setState(() => once = v ?? false),
          title: const Text('仅本次（断开连接后失效）'),
        ),
      ],
    );
  }
}

/// 1.12.0: [host] 直连 / 走代理 (saved, or 仅本次 in memory); the toast can undo it.
Future<void> museAddQuickRule(WidgetRef ref, String host, MuseQuickWay way, {bool once = false}) async {
  final toast = ref.read(inAppNotificationControllerProvider);
  if (once) {
    final c = ref.read(museTempQuickRulesProvider.notifier);
    final before = c.state;
    c.state = museSetQuickRule(before, host, way);
    toast.showSuccessToast('本次连接内 $host ${way.title}', action: (label: '撤销', onPressed: () => c.state = before));
    return;
  }
  final n = ref.read(MusePrefs.quickRules.notifier);
  final raw = ref.read(MusePrefs.quickRules);
  await n.update(museQuickRulesToRaw(museSetQuickRule(museParseQuickRules(raw), host, way)));
  toast.showSuccessToast('已设置 $host ${way.title}，可在 设置 › 分流规则 › 来自连接的规则 里修改', action: (label: '撤销', onPressed: () => n.update(raw)));
}

/// 1.12.0: [host] 走指定节点 — pick one of the subscription's nodes.
Future<void> museAddHostToNode(BuildContext context, WidgetRef ref, String host, {bool once = false}) async {
  final group = ref.read(museNodeGroupProvider).valueOrNull;
  final nodes = [for (final e in group?.items ?? const <OutboundInfo>[]) if (!e.isGroup) e];
  final toast = ref.read(inAppNotificationControllerProvider);
  if (nodes.isEmpty) {
    toast.showInfoToast('连接后才能选择节点');
    return;
  }
  final node = await showMuseSnapSheet<String>(
    context,
    title: '$host 走哪个节点',
    builder: (ctx, controller) => ListView(
      controller: controller,
      children: [
        for (final e in nodes)
          ListTile(
            key: ValueKey('conn_rule_pick_${e.tag}'),
            title: Text(museNodeName(e), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(ctx, e.tag),
          ),
      ],
    ),
  );
  if (node == null) return;
  if (once) {
    final c = ref.read(museTempNodeRulesProvider.notifier);
    final before = c.state;
    c.state = museAddHostToNodeRule(before, node, host);
    toast.showSuccessToast('本次连接内 $host 走所选节点', action: (label: '撤销', onPressed: () => c.state = before));
    return;
  }
  final n = ref.read(MusePrefs.nodeRules.notifier);
  final raw = ref.read(MusePrefs.nodeRules);
  await n.update(museNodeRulesToRaw(museAddHostToNodeRule(museParseNodeRules(raw), node, host)));
  toast.showSuccessToast('已设置 $host 走所选节点，可在 设置 › 分流规则 › 指定节点 里修改', action: (label: '撤销', onPressed: () => n.update(raw)));
}


/// 1.15.0 R16: 连接行左侧的应用图标（Android 有包名时读图标，缩小解码；其余显示通用图标）。
class MuseConnAppIcon extends ConsumerWidget {
  const MuseConnAppIcon({super.key, required this.app});

  final MuseConnApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final px = (MuseSize.appIcon * MediaQuery.devicePixelRatioOf(context)).round();
    final fallback = Icon(app.package != null ? Icons.android_outlined : Icons.terminal_outlined, size: MuseSize.appIcon, color: scheme.onSurfaceVariant);
    final pkg = app.package;
    if (pkg == null) return Semantics(label: app.name, child: fallback);
    final icon = ref.watch(museAppIconProvider(pkg)).valueOrNull;
    return Semantics(
      label: app.name,
      child: icon == null
          ? fallback
          : ClipOval(
              child: Image.memory(icon, key: ValueKey('conn_app_icon_$pkg'), width: MuseSize.appIcon, height: MuseSize.appIcon, cacheWidth: px, cacheHeight: px, gaplessPlayback: true),
            ),
    );
  }
}
