// 穿云 - 设置 › 节点. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// 1.20.3：节点设置只留显示相关；订阅的全局设置收进订阅弹层 ⋯ › 订阅设置（MuseSubSettingsPage）。
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 节点

/// 1.11.0
const museAutoFailoverTitle = '节点失效自动切换';

/// 1.20.3：节点设置的页标题（⋯ 菜单与搜索同名）。
const museNodeSettingsTitle = '节点设置';

/// 1.20.3：订阅弹层 ⋯ ›「订阅设置」。
const museSubSettingsTitle = '订阅设置';

/// 1.20.3：节点设置只留和节点显示有关的项（名称美化、隐藏重复、全部订阅的只显示 / 排除、已隐藏、清除测速记录）。
/// 节点失效自动切换 → 设置 › 启动与断线 › 断线处理；订阅更新方式、订阅 UA → 订阅弹层 ⋯ › 订阅设置。
class MuseNodeSettingsPage extends HookConsumerWidget {
  const MuseNodeSettingsPage({super.key, this.advancedOpen = false});

  /// 1.11.0 的「高级」已取消（重复判断直接在「隐藏重复节点」下面）；保留参数，旧调用方不用改
  final bool advancedOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final include = ref.watch(MusePrefs.includeRegex);
    final exclude = ref.watch(MusePrefs.excludeRegex);
    final metas = MuseNodeMetas.parse(ref.watch(MusePrefs.nodeMeta));
    final hiddenCount = metas.hiddenTags.length;
    final hideDup = ref.watch(MusePrefs.hideDuplicates);

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
      title: museNodeSettingsTitle,
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '显示',
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
                value: hideDup,
                onChanged: (v) => ref.read(MusePrefs.hideDuplicates.notifier).update(v),
              ),
              // 1.6.0 #31: what counts as a duplicate；1.20.3：从「高级」挪到开关下面
              MuseTile(
                key: const ValueKey('node_dedup_mode'),
                leading: const Icon(Icons.rule_outlined),
                title: '重复判断',
                subtitle: hideDup ? null : '开启「隐藏重复节点」后生效',
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
          // 1.20.3：改名「全部订阅：只显示 / 排除」，和单个订阅的「节点筛选」分开
          MuseSection(
            header: '全部订阅',
            children: [
              MuseTile(
                key: const ValueKey('node_include'),
                leading: const Icon(Icons.filter_alt_outlined),
                title: '只显示',
                trailing: Text(include.isEmpty ? '全部' : include, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () => editRegex('全部订阅：只显示名称匹配的节点', include, ref.read(MusePrefs.includeRegex.notifier).update),
              ),
              MuseTile(
                key: const ValueKey('node_exclude'),
                leading: const Icon(Icons.filter_alt_off_outlined),
                title: '排除',
                trailing: Text(exclude.isEmpty ? '无' : exclude, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () => editRegex('全部订阅：排除名称匹配的节点', exclude, ref.read(MusePrefs.excludeRegex.notifier).update),
              ),
              if (hiddenCount > 0)
                MuseTile(
                  key: const ValueKey('node_unhide_all'),
                  leading: const Icon(Icons.visibility_outlined),
                  title: '显示全部已隐藏节点',
                  trailing: Text('$hiddenCount'),
                  onTap: () => ref.read(MusePrefs.nodeMeta.notifier).update(metas.setHidden(metas.hiddenTags, false).toRaw()),
                ),
              // 1.20.3：开发者选项里那条重复的删掉了，只留这里
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

/// 1.20.3：订阅弹层 ⋯ ›「订阅设置」—— 订阅自动更新、更新后测速新增节点（原在 ⋯ 菜单里）、订阅更新方式、订阅 UA
/// （原在节点设置）。每个订阅自己的请求头、节点筛选、覆写仍在该订阅的 ⋮ 里。
class MuseSubSettingsPage extends ConsumerWidget {
  const MuseSubSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = ref.watch(Preferences.museAutoUpdateHours);
    final ua = ref.watch(MusePrefs.subUserAgent);
    final fetch = MuseSubFetch.fromKey(ref.watch(MusePrefs.subFetch));
    return MuseScaffold(
      key: const ValueKey('sub_settings_page'),
      title: museSubSettingsTitle,
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '更新',
            children: [
              MuseTile(
                key: const ValueKey('auto_update_hours'),
                leading: const Icon(Icons.update_outlined),
                title: '订阅自动更新',
                trailing: Text(museAutoUpdateLabel(hours)),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<int>(context, '订阅自动更新', [for (final h in museAutoUpdateChoices) (h, museAutoUpdateLabel(h))], hours);
                  if (picked != null) await ref.read(Preferences.museAutoUpdateHours.notifier).update(picked);
                },
              ),
              MuseSwitchTile(
                key: const ValueKey('test_new_nodes'),
                leading: const Icon(Icons.speed_outlined),
                title: '更新后测速新增节点',
                value: ref.watch(MusePrefs.testNewNodes),
                onChanged: (v) => ref.read(MusePrefs.testNewNodes.notifier).update(v),
              ),
              // 1.5.0 #41
              MuseTile(
                key: const ValueKey('node_sub_fetch'),
                leading: const Icon(Icons.alt_route_outlined),
                title: '订阅更新方式',
                subtitle: '自动：已连接时先走代理，失败再直连；未连接时直连',
                subtitleMaxLines: 2,
                trailing: Text(fetch.title),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<MuseSubFetch>(context, '订阅更新方式', [for (final f in MuseSubFetch.values) (f, f.title)], fetch);
                  if (picked != null) await ref.read(MusePrefs.subFetch.notifier).update(picked.key);
                },
              ),
              // 1.4.1: the user agent subscriptions are downloaded with (the server picks the format by it)
              MuseTile(
                key: const ValueKey('node_sub_ua'),
                leading: const Icon(Icons.badge_outlined),
                title: '订阅 UA',
                subtitle: '「自动」适合大多数订阅；节点不全或格式不对时换一个再更新',
                subtitleMaxLines: 2,
                trailing: Text(museUserAgents.firstWhere((e) => e.$1 == ua, orElse: () => museUserAgents.first).$2),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<String>(context, '订阅 UA', museUserAgents, ua);
                  if (picked != null) await ref.read(MusePrefs.subUserAgent.notifier).update(picked);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
