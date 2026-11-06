// 穿云 - 设置 › 节点. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 节点

/// 1.11.0
const museAutoFailoverTitle = '节点失效自动切换';

class MuseNodeSettingsPage extends HookConsumerWidget {
  const MuseNodeSettingsPage({super.key, this.advancedOpen = false});

  /// 1.11.0: open with 「高级」 (订阅 UA / 重复判断) unfolded
  final bool advancedOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final include = ref.watch(MusePrefs.includeRegex);
    final exclude = ref.watch(MusePrefs.excludeRegex);
    final metas = MuseNodeMetas.parse(ref.watch(MusePrefs.nodeMeta));
    final hiddenCount = metas.hiddenTags.length;
    final ua = ref.watch(MusePrefs.subUserAgent);
    final fetch = MuseSubFetch.fromKey(ref.watch(MusePrefs.subFetch));

    Future<void> editRegex(String title, String current, Future<void> Function(String) save) async {
      final v = await museAskText(context, title, initial: current, hint: '正则，如 香港|日本');
      if (v == null) return;
      final err = museNodeFilterError(v);
      if (err != null) {
        _toast(ref, err, error: true);
        return;
      }
      await save(v);
    }

    return MuseScaffold(
      title: '节点',
      body: MuseGroupedBody(
        children: [
          // 1.11.0 节点失效自动切换 (on by default; event driven: acts on test results, never polls)
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('node_auto_failover'),
                leading: const Icon(Icons.swap_horiz_outlined),
                title: museAutoFailoverTitle,
                info: '当前节点连续两次测速失败时，自动换到同地区最快的可用节点并提示；该节点恢复后换回',
                value: ref.watch(MusePrefs.autoFailover),
                onChanged: (v) => ref.read(MusePrefs.autoFailover.notifier).update(v),
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('node_beautify'),
                leading: const Icon(Icons.auto_fix_high_outlined),
                title: '节点名美化',
                value: ref.watch(MusePrefs.beautifyNames),
                onChanged: (v) => ref.read(MusePrefs.beautifyNames.notifier).update(v),
              ),
              MuseSwitchTile(
                key: const ValueKey('node_hide_duplicates'),
                leading: const Icon(Icons.filter_none_outlined),
                title: '隐藏重复节点',
                value: ref.watch(MusePrefs.hideDuplicates),
                onChanged: (v) => ref.read(MusePrefs.hideDuplicates.notifier).update(v),
              ),
              MuseTile(
                key: const ValueKey('node_include'),
                leading: const Icon(Icons.filter_alt_outlined),
                title: '只显示',
                trailing: Text(include.isEmpty ? '全部' : include, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () => editRegex('只显示名称匹配的节点', include, ref.read(MusePrefs.includeRegex.notifier).update),
              ),
              MuseTile(
                key: const ValueKey('node_exclude'),
                leading: const Icon(Icons.filter_alt_off_outlined),
                title: '排除',
                trailing: Text(exclude.isEmpty ? '无' : exclude, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () => editRegex('排除名称匹配的节点', exclude, ref.read(MusePrefs.excludeRegex.notifier).update),
              ),
              if (hiddenCount > 0)
                MuseTile(
                  key: const ValueKey('node_unhide_all'),
                  leading: const Icon(Icons.visibility_outlined),
                  title: '显示全部已隐藏节点',
                  trailing: Text('$hiddenCount'),
                  onTap: () => ref.read(MusePrefs.nodeMeta.notifier).update(metas.setHidden(metas.hiddenTags, false).toRaw()),
                ),
            ],
          ),
          // 1.4.1: the user agent subscriptions are downloaded with (the server picks the format by it)
          MuseSection(
            header: '订阅',
            children: [
              // 1.5.0 #41
              MuseTile(
                key: const ValueKey('node_sub_fetch'),
                leading: const Icon(Icons.alt_route_outlined),
                title: '订阅更新方式',
                info: '自动：已连接时先走代理，失败再直连；未连接时总是直连',
                trailing: Text(fetch.title),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<MuseSubFetch>(context, '订阅更新方式', [for (final f in MuseSubFetch.values) (f, f.title)], fetch);
                  if (picked != null) await ref.read(MusePrefs.subFetch.notifier).update(picked.key);
                },
              ),
            ],
          ),
          // 1.11.0: 订阅 UA and 重复判断 fold into 「高级」 (same preferences)
          MuseFoldSection(
            key: const ValueKey('node_advanced'),
            foldKey: const ValueKey('node_advanced_fold'),
            summary: '订阅 UA、重复判断',
            footer: '订阅 UA「自动」适合大多数订阅；节点不全或格式不对时可换一个再更新',
            initiallyOpen: advancedOpen,
            children: [
              MuseTile(
                key: const ValueKey('node_sub_ua'),
                leading: const Icon(Icons.badge_outlined),
                title: '订阅 UA',
                trailing: Text(museUserAgents.firstWhere((e) => e.$1 == ua, orElse: () => museUserAgents.first).$2),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<String>(context, '订阅 UA', museUserAgents, ua);
                  if (picked != null) await ref.read(MusePrefs.subUserAgent.notifier).update(picked);
                },
              ),
              // 1.6.0 #31: what counts as a duplicate
              MuseTile(
                key: const ValueKey('node_dedup_mode'),
                leading: const Icon(Icons.rule_outlined),
                title: '重复判断',
                subtitle: ref.watch(MusePrefs.hideDuplicates) ? null : '开启「隐藏重复节点」后生效',
                trailing: Text(museDedupModes[ref.watch(MusePrefs.dedupMode)] ?? museDedupModes['protocol']!, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () async {
                  final cur = ref.read(MusePrefs.dedupMode);
                  final v = await showDialog<String>(
                    context: context,
                    builder: (c) => SimpleDialog(
                      key: const ValueKey('node_dedup_dialog'),
                      title: const Text('重复判断'),
                      children: [
                        for (final e in museDedupModes.entries)
                          SimpleDialogOption(
                            key: ValueKey('node_dedup_${e.key}'),
                            onPressed: () => Navigator.of(c).pop(e.key),
                            child: Text('${e.value}${cur == e.key ? '（当前）' : ''}'),
                          ),
                      ],
                    ),
                  );
                  if (v != null) await ref.read(MusePrefs.dedupMode.notifier).update(v);
                },
              ),
            ],
          ),
          MuseSection(
            header: '测速',
            children: [
              MuseTile(
                key: const ValueKey('node_clear_cache'),
                leading: const Icon(Icons.cleaning_services_outlined),
                title: '清除测速记录',
                onTap: () async {
                  await ref.read(MusePrefs.latencyCache.notifier).update(MuseLatencyCache.empty.toRaw());
                  await ref.read(MusePrefs.delayHistory.notifier).update('');
                  _toast(ref, '已清除');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
