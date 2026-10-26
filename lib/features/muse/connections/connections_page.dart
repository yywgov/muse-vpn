// 穿云 1.6.0 C3 - 连接: live connections (search, sort, close one / all, details, 屏蔽此域名) and
// 请求 (connections that ended, newest first). Lists are lazy with a fixed row height; a frame
// only rebuilds the list, rows are cheap. A local API failure shows 「暂不可用」 and never touches
// the connection state.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart' show museSpeedText;
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
  const MuseConnectionsPage({super.key});

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
      title: '连接',
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
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(MuseSpace.page(context), 0, MuseSpace.page(context), MuseSpace.s8),
            child: Column(
              children: [
                _Summary(state: state, ended: history.length),
                const SizedBox(height: MuseSpace.s8),
                SegmentedButton<int>(
                  key: const ValueKey('conn_tabs'),
                  segments: [
                    ButtonSegment(value: 0, label: Text('活动 ${state.connections.length}')),
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
          ),
          Expanded(
            child: state.error != null && tab.value == 0
                ? _Empty(icon: Icons.cloud_off_outlined, text: state.error == '未连接' ? '连接后可查看实时连接' : '暂不可用（${state.error}）')
                : list.isEmpty
                ? _Empty(icon: Icons.swap_vert_outlined, text: state.loading && tab.value == 0 ? '正在读取…' : (query.value.isEmpty ? '暂无连接' : '没有匹配的连接'))
                : ListView.builder(
                    key: const ValueKey('conn_list'),
                    itemExtent: museConnRowHeight,
                    padding: EdgeInsets.fromLTRB(MuseSpace.page(context), 0, MuseSpace.page(context), MuseSize.fabClearance),
                    itemCount: list.length,
                    itemBuilder: (_, i) => MuseConnRow(conn: list[i], ended: tab.value == 1, wide: MediaQuery.sizeOf(context).width > MuseBreak.laptop),
                  ),
          ),
        ],
      ),
    );
  }
}

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
          cell('活动', '${state.connections.length}'),
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
    final sub = [if (conn.node.isNotEmpty) conn.node, if (conn.rule.isNotEmpty) conn.rule, if (wide && conn.process.isNotEmpty) conn.process].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: MuseSpace.s4),
      child: MuseCard(
        padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s8),
        radius: MuseRadiusScale.md,
        onTap: () => showMuseConnDetail(context, ref, conn, ended: ended),
        child: Row(
          children: [
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
        padding: const EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s24),
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
          const SizedBox(height: MuseSpace.s16),
          MuseSectionGroup(
            children: [
              kv('主机', c.host),
              kv('目标', c.destination),
              kv('协议', c.network),
              kv('入站', c.inbound),
              kv('链路', c.chains.reversed.join(' → ')),
              kv('规则', c.rule),
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
