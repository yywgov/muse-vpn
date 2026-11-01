// 穿云 1.8.0 - 活动 › DNS: the core's DNS queries (domain, which DNS answered, addresses, time,
// cache). Search by domain / address / server, long-press to keep one domain, tap to copy,
// 清空 empties the app's list and the core's buffer. The stream runs only while this tab is on
// screen; 兼容内核 has no query records and says so.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/local_api/dns_queries.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_card.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Row height of a query (fixed: the list uses itemExtent).
const museDnsRowHeight = MuseSize.rowMin + MuseSpace.s16;

/// Text when 兼容内核 runs.
const museDnsUnsupportedText = '当前内核不支持';

class MuseDnsPage extends HookConsumerWidget {
  const MuseDnsPage({super.key, this.header});

  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final domain = useState<String?>(null);
    final state = ref.watch(museDnsQueriesProvider).valueOrNull ?? const MuseDnsState(loading: true);
    final list = museFilterDns(state.queries, query: query.value, domain: domain.value);
    final scheme = Theme.of(context).colorScheme;
    final n = ref.read(inAppNotificationControllerProvider);

    final Widget content;
    if (state.unsupported) {
      content = const _Hint(icon: Icons.dns_outlined, text: '$museDnsUnsupportedText\nDNS 查询记录需要标准内核（设置 › 内核）');
    } else if (state.queries.isEmpty && state.error != null) {
      content = _Hint(icon: Icons.cloud_off_outlined, text: state.error == '未连接' ? '连接后可查看 DNS 查询' : '暂不可用（${state.error}）');
    } else if (list.isEmpty) {
      content = _Hint(
        icon: Icons.dns_outlined,
        text: state.loading ? '正在读取…' : (query.value.isEmpty && domain.value == null ? '暂无查询，打开网页或应用后显示' : '没有匹配的查询'),
      );
    } else {
      content = ListView.builder(
        key: const ValueKey('dns_list'),
        itemExtent: museDnsRowHeight,
        padding: EdgeInsets.fromLTRB(MuseSpace.page(context), 0, MuseSpace.page(context), museScrollEndGap(context, MuseSpace.s16)),
        itemCount: list.length,
        itemBuilder: (_, i) => MuseDnsRow(
          query: list[i],
          onTap: () {
            Clipboard.setData(ClipboardData(text: museDnsCopyText(list[i])));
            n.showSuccessToast('已复制');
          },
          onLongPress: () => domain.value = list[i].domain,
        ),
      );
    }

    return MuseScaffold(
      title: header == null ? 'DNS' : '活动',
      actions: [
        IconButton(
          key: const ValueKey('dns_clear'),
          tooltip: '清空',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: state.unsupported || state.queries.isEmpty ? null : () => museClearDnsQueries(ref),
        ),
      ],
      body: Column(
        children: [
          ?header,
          if (!state.unsupported)
            Padding(
              padding: EdgeInsets.fromLTRB(MuseSpace.page(context), 0, MuseSpace.page(context), MuseSpace.s8),
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('dns_search'),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_outlined), hintText: '搜索域名、IP 或 DNS', isDense: true),
                    onChanged: (v) => query.value = v,
                  ),
                  if (domain.value != null) ...[
                    const SizedBox(height: MuseSpace.s8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: InputChip(
                        key: const ValueKey('dns_domain_filter'),
                        label: Text('只看 ${domain.value}'),
                        onDeleted: () => domain.value = null,
                      ),
                    ),
                  ],
                  const SizedBox(height: MuseSpace.s4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '共 ${state.queries.length} 条（最多保留 $museDnsCapacity 条）· 点按复制 · 长按只看该域名',
                      style: MuseTextLevel.caption1.style(context, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// One query: domain + type, addresses; DNS, cache mark and time on the right.
class MuseDnsRow extends StatelessWidget {
  const MuseDnsRow({super.key, required this.query, this.onTap, this.onLongPress});

  final MuseDnsQuery query;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = query;
    return Padding(
      padding: const EdgeInsets.only(bottom: MuseSpace.s4),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: MuseCard(
          padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s8),
          onTap: onTap,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: q.domain),
                          TextSpan(text: '  ${q.type}', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w400)),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MuseTextLevel.callout.style(context, weight: FontWeight.w600),
                    ),
                    Text(
                      museDnsAnswerText(q),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MuseTextLevel.caption1.style(context, color: q.failed ? scheme.destructive : scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MuseSpace.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: MuseSize.dnsServerColumn),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(museDnsServerLabel(q), maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseTextLevel.footnote.style(context)),
                    Text(
                      q.cached ? '缓存 · ${museDnsElapsedText(q)}' : museDnsElapsedText(q),
                      key: q.cached ? const ValueKey('dns_cached') : null,
                      style: MuseTextLevel.caption1.style(context, color: q.cached ? scheme.primary : scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: MuseSize.emptyIcon, color: scheme.onSurfaceVariant),
            const SizedBox(height: MuseSpace.s8),
            Text(text, textAlign: TextAlign.center, style: MuseTextLevel.subheadline.style(context, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
