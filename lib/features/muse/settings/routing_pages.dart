// 穿云 - 设置 › 分流（预设、指定节点、远程规则集、规则测试）. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 分流

/// The rules as sent to the core (user rules + presets + built-ins, route mode applied).
List<Rule> museEffectiveRules(WidgetRef ref) {
  List<Rule> own;
  try {
    own = ref.read(rulesNotifierProvider);
  } catch (_) {
    own = const [];
  }
  return ref
      .read(ConfigOptions.museRouteMode)
      .applyTo(
        museApplyPresets(
          own,
          museParsePresetChoice(ref.read(MusePrefs.rulePresets)),
          remote: museParseRemoteRuleSets(ref.read(MusePrefs.remoteRuleSets)),
        ),
      );
}

class MuseRoutingPage extends HookConsumerWidget {
  const MuseRoutingPage({super.key, this.embedded = false});

  /// 1.9.0 #17: shown as the 「分流」 tab of 「规则」 (body only, plus the rule list entry)
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = museParsePresetChoice(ref.watch(MusePrefs.rulePresets));
    final hosts = museParseHosts(ref.watch(MusePrefs.hosts));
    final nodeRules = museParseNodeRules(ref.watch(MusePrefs.nodeRules));
    final quickRules = museParseQuickRules(ref.watch(MusePrefs.quickRules));
    final remoteSets = museParseRemoteRuleSets(ref.watch(MusePrefs.remoteRuleSets));
    final adLevel = MuseAdBlockLevel.fromKey(ref.watch(Preferences.museAdBlockLevel));

    final body = MuseGroupedBody(
        children: [
          // 1.10.0: 去广告 moved here from the 设置 home page (same preference)
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('ad_block_level'),
                leading: const Icon(Icons.block_outlined),
                title: '去广告',
                trailing: Text(adLevel.title),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<MuseAdBlockLevel>(
                    context,
                    '去广告',
                    [for (final l in MuseAdBlockLevel.values) (l, l.title)],
                    adLevel,
                  );
                  if (picked != null) await ref.read(Preferences.museAdBlockLevel.notifier).update(picked.key);
                },
              ),
            ],
          ),
          // 1.5.0: changes reach a running connection by themselves (hot reload)
          MuseSection(
            children: [
              // 1.9.0 #17: the custom rule list (formerly 订阅 › 路由规则) lives under 「规则」 too
              if (embedded)
                MuseTile(
                  key: const ValueKey('routing_rule_list'),
                  leading: const Icon(Icons.route_outlined),
                  title: '自定义规则列表',
                  chevron: true,
                  onTap: () => context.goNamed('routingOptions'),
                ),
              MuseTile(
                key: const ValueKey('routing_presets'),
                leading: const Icon(Icons.playlist_add_check_outlined),
                title: '预设',
                trailing: Text(choice.isEmpty ? '未开启' : '已开启 ${choice.length} 个'),
                chevron: true,
                onTap: () => musePushPage(context, const MusePresetsPage()),
              ),
              MuseTile(
                key: const ValueKey('routing_node_rules'),
                leading: const Icon(Icons.call_split_outlined),
                title: '指定节点',
                trailing: Text(nodeRules.isEmpty ? '无' : '${nodeRules.length} 条'),
                chevron: true,
                onTap: () => musePushPage(context, const MuseNodeRulesPage()),
              ),
              // 1.12.0: 在「活动 › 连接」里加的 直连 / 走代理
              if (quickRules.isNotEmpty)
                MuseTile(
                  key: const ValueKey('routing_quick_rules'),
                  leading: const Icon(Icons.bolt_outlined),
                  title: '来自连接的规则',
                  trailing: Text('${quickRules.length} 条'),
                  chevron: true,
                  onTap: () => showMuseQuickRulesSheet(context),
                ),
              MuseTile(
                key: const ValueKey('routing_remote_sets'),
                leading: const Icon(Icons.cloud_download_outlined),
                title: '远程规则集',
                trailing: Text(remoteSets.isEmpty ? '无' : '${remoteSets.length} 个'),
                chevron: true,
                onTap: () => musePushPage(context, const MuseRemoteRuleSetsPage()),
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('routing_tester'),
                leading: const Icon(Icons.science_outlined),
                title: '规则测试',
                chevron: true,
                onTap: () => musePushPage(context, const MuseRuleTesterPage()),
              ),
              MuseTile(
                key: const ValueKey('routing_hosts'),
                leading: const Icon(Icons.dns_outlined),
                title: '自定义 hosts',
                trailing: Text(hosts.isEmpty ? '无' : '${hosts.length} 条'),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(
                    context,
                    '自定义 hosts',
                    initial: ref.read(MusePrefs.hosts),
                    hint: '每行一条：1.2.3.4 example.com',
                    maxLines: 8,
                  );
                  if (v != null) await ref.read(MusePrefs.hosts.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('routing_export'),
                leading: const Icon(Icons.ios_share_outlined),
                title: '导出规则',
                onTap: () async {
                  final text = museExportRules(ref.read(rulesNotifierProvider));
                  final ok = await museSaveTextFile(context, 'chuanyun-rules.json', text);
                  if (ok) _toast(ref, '已导出');
                },
              ),
              // 1.9.0 #67
              MuseTile(
                key: const ValueKey('routing_export_singbox'),
                leading: const Icon(Icons.output_outlined),
                title: '导出为 sing-box 格式',
                info: '只导出你自己的规则（route.rules 片段），内置规则和预设不含在内',
                onTap: () async {
                  final text = museExportRulesSingBox(ref.read(rulesNotifierProvider));
                  final ok = await museSaveTextFile(context, 'chuanyun-rules-singbox.json', text);
                  if (ok) _toast(ref, '已导出');
                },
              ),
              MuseTile(
                key: const ValueKey('routing_import'),
                leading: const Icon(Icons.file_open_outlined),
                title: '导入规则',
                onTap: () async {
                  final text = await museOpenTextFile();
                  if (text == null) return;
                  await _importRulesText(ref, text);
                },
              ),
              // 1.5.0 #59: Clash / Surge rule lines pasted as text
              MuseTile(
                key: const ValueKey('routing_paste_rules'),
                leading: const Icon(Icons.content_paste_outlined),
                title: '粘贴规则',
                info: '支持本应用导出的规则文件，以及 Clash / Surge 的规则行（如 DOMAIN-SUFFIX,google.com,Proxy）',
                onTap: () async {
                  final text = await museAskText(context, '粘贴规则', hint: 'DOMAIN-SUFFIX,google.com,Proxy', maxLines: 8);
                  if (text == null || text.trim().isEmpty) return;
                  await _importRulesText(ref, text);
                },
              ),
            ],
          ),
        ],
      );
    return embedded ? body : MuseScaffold(title: '分流', body: body);
  }
}

/// 1.4.1: the 分流 presets, in sections with a search (they no longer fit one list).
class MusePresetsPage extends HookConsumerWidget {
  const MusePresetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = museParsePresetChoice(ref.watch(MusePrefs.rulePresets));
    final query = useState('');
    final mt = MuseTheme.of(context);
    final groups = musePresetsByGroup(query: query.value);

    Future<void> setChoice(String key, Outbound? way) async {
      final next = {...museParsePresetChoice(ref.read(MusePrefs.rulePresets))};
      if (way == null) {
        next.remove(key);
      } else {
        next[key] = way;
      }
      await ref.read(MusePrefs.rulePresets.notifier).update(musePresetChoiceToRaw(next));
    }

    return MuseScaffold(
      title: '预设',
      body: MuseGroupedBody(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context), vertical: MuseSpace.s8),
            child: TextField(
              key: const ValueKey('preset_search'),
              onChanged: (v) => query.value = v,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索，如 YouTube、github.com',
                prefixIcon: const Icon(Icons.search_outlined),
                filled: true,
                fillColor: mt.card,
                isDense: true,
                border: const OutlineInputBorder(borderRadius: MuseRadius.cardAll, borderSide: BorderSide.none),
              ),
            ),
          ),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(MuseSpace.s24),
              child: Center(child: Text('没有匹配的预设', style: MuseType.body(context).copyWith(color: mt.text2))),
            ),
          for (final g in groups.entries)
            MuseSection(
              key: ValueKey('preset_group_${g.key.name}'),
              header: g.key.title,
              dividerIndent: MuseSpace.s16,
              children: [
                for (final p in g.value)
                  MuseTile(
                    key: ValueKey('preset_${p.key}'),
                    title: p.title,
                    subtitleMaxLines: 1,
                    trailing: Text(
                      choice.containsKey(p.key) ? museOutboundTitle(choice[p.key]!) : '关',
                      style: choice.containsKey(p.key) ? TextStyle(color: museBrandOf(context), fontWeight: FontWeight.w600) : null,
                    ),
                    chevron: true,
                    onTap: () async {
                      const off = 'off';
                      final cur = choice.containsKey(p.key) ? museOutboundKey(choice[p.key]!) : off;
                      final picked = await musePick<String>(context, p.title, const [
                        (off, '关'),
                        ('proxy', '代理'),
                        ('direct', '直连'),
                        ('block', '拦截'),
                      ], cur);
                      if (picked == null) return;
                      await setChoice(p.key, picked == off ? null : museOutboundFromKey(picked));
                    },
                  ),
              ],
            ),
          if (groups.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(MuseSpace.page(context) + MuseSpace.s16, MuseSpace.s8, MuseSpace.page(context), MuseSpace.s16),
              child: Text('单独设置的服务优先于范围更大的预设（如 YouTube 优先于其他流媒体、Google）', style: MuseType.caption(context)),
            ),
        ],
      ),
    );
  }
}

/// 1.4.1: sites / apps through one chosen node.
class MuseNodeRulesPage extends HookConsumerWidget {
  const MuseNodeRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = museParseNodeRules(ref.watch(MusePrefs.nodeRules));
    final group = ref.watch(museNodeGroupProvider).valueOrNull;
    final metas = MuseNodeMetas.parse(ref.watch(MusePrefs.nodeMeta));
    final nodes = [for (final e in group?.items ?? const <OutboundInfo>[]) if (!e.isGroup && !museIsInfoNode(museNodeName(e))) e];
    String nodeName(String tag) {
      final n = nodes.where((e) => e.tag == tag).firstOrNull;
      return n == null ? '$tag（不在当前订阅）' : metas.displayName(tag, museNodeName(n));
    }

    Future<void> save(List<MuseNodeRule> next) => ref.read(MusePrefs.nodeRules.notifier).update(museNodeRulesToRaw(next));

    Future<void> edit({int? index}) async {
      final cur = index == null ? null : rules[index];
      if (nodes.isEmpty) {
        _toast(ref, '还没有节点：先添加订阅并连接一次', error: true);
        return;
      }
      final tag = await musePick<String>(
        context,
        '走哪个节点',
        [for (final n in nodes) (n.tag, metas.displayName(n.tag, museNodeName(n)))],
        cur?.node ?? '',
      );
      if (tag == null || !context.mounted) return;
      final text = await museAskText(
        context,
        '网站或应用',
        initial: cur?.summary.replaceAll('、', '\n') ?? '',
        hint: '每行一个：netflix.com、chrome.exe、com.android.chrome',
        maxLines: 6,
      );
      if (text == null) return;
      final rule = museNodeRuleFromText(tag, text);
      final next = [...rules];
      if (index != null) next.removeAt(index);
      if (!rule.isEmpty) next.insert(index ?? next.length, rule);
      await save(next);
    }

    return MuseScaffold(
      title: '指定节点',
      actions: [IconButton(key: const ValueKey('node_rule_add'), icon: const Icon(Icons.add_outlined), onPressed: () => edit())],
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '这些网站或应用总走所选节点（规则、全局模式都生效）；节点不在当前订阅时该条不生效',
            children: [
              if (rules.isEmpty)
                MuseTile(key: const ValueKey('node_rule_empty'), leading: const Icon(Icons.add_outlined), title: '添加', onTap: () => edit()),
              for (var i = 0; i < rules.length; i++)
                MuseTile(
                  key: ValueKey('node_rule_$i'),
                  leading: const Icon(Icons.call_split_outlined),
                  title: nodeName(rules[i].node),
                  subtitle: rules[i].summary,
                  subtitleMaxLines: 2,
                  trailing: IconButton(
                    key: ValueKey('node_rule_delete_$i'),
                    icon: const Icon(Icons.delete_outlined),
                    onPressed: () => save([...rules]..removeAt(i)),
                  ),
                  onTap: () => edit(index: i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 1.4.1: rule-sets by link (sing-box .srs / .json).
class MuseRemoteRuleSetsPage extends HookConsumerWidget {
  const MuseRemoteRuleSetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = museParseRemoteRuleSets(ref.watch(MusePrefs.remoteRuleSets));
    Future<void> save(List<MuseRemoteRuleSet> next) => ref.read(MusePrefs.remoteRuleSets.notifier).update(museRemoteRuleSetsToRaw(next));

    Future<void> add() async {
      final url = await museAskText(context, '规则集链接', hint: 'https://…/geosite-xxx.srs 或 .json');
      if (url == null || url.isEmpty || !context.mounted) return;
      if (!museIsRuleSetUrl(url)) {
        _toast(ref, '需要 .srs 或 .json 规则集链接', error: true);
        return;
      }
      final way = await musePick<String>(context, '命中后', const [('proxy', '代理'), ('direct', '直连'), ('block', '拦截')], 'proxy');
      if (way == null) return;
      await save([...sets.where((s) => s.url != url.trim()), MuseRemoteRuleSet(url.trim(), museOutboundFromKey(way)!)]);
    }

    return MuseScaffold(
      title: '远程规则集',
      actions: [IconButton(key: const ValueKey('remote_set_add'), icon: const Icon(Icons.add_outlined), onPressed: add)],
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '首次连接时下载（最多等 5 秒，失败不影响连接），之后在后台更新',
            children: [
              if (sets.isEmpty) MuseTile(key: const ValueKey('remote_set_empty'), leading: const Icon(Icons.add_outlined), title: '添加', onTap: add),
              for (var i = 0; i < sets.length; i++)
                MuseTile(
                  key: ValueKey('remote_set_$i'),
                  leading: const Icon(Icons.cloud_outlined),
                  title: Uri.tryParse(sets[i].url)?.pathSegments.lastOrNull ?? sets[i].url,
                  subtitle: '${museOutboundTitle(sets[i].outbound)} · ${Uri.tryParse(sets[i].url)?.host ?? ''}',
                  trailing: IconButton(
                    key: ValueKey('remote_set_delete_$i'),
                    icon: const Icon(Icons.delete_outlined),
                    onPressed: () => save([...sets]..removeAt(i)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class MuseRuleTesterPage extends HookConsumerWidget {
  const MuseRuleTesterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    // 1.9.0 #64: several domains at once (one per line, or separated by spaces / commas)
    final results = useState<List<(String, MuseRuleMatch)>>(const []);
    final mt = MuseTheme.of(context);
    void run() {
      final targets = museSplitTargets(controller.text);
      if (targets.isEmpty) return;
      final rules = museEffectiveRules(ref);
      results.value = [for (final t in targets) (t, museTestRules(rules, t))];
    }

    final single = results.value.length == 1;
    return MuseScaffold(
      title: '规则测试',
      body: MuseGroupedBody(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context), vertical: MuseSpace.s8),
            child: TextField(
              key: const ValueKey('rule_test_field'),
              controller: controller,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: '输入网址或域名，如 chatgpt.com；可一次粘贴多个',
                filled: true,
                fillColor: mt.card,
                border: const OutlineInputBorder(borderRadius: MuseRadius.cardAll, borderSide: BorderSide.none),
                suffixIcon: IconButton(key: const ValueKey('rule_test_go'), icon: const Icon(Icons.arrow_forward_outlined), onPressed: run),
              ),
            ),
          ),
          if (results.value.isNotEmpty)
            MuseSection(
              dividerIndent: MuseSpace.s16,
              children: [
                for (final (i, (target, r)) in results.value.indexed)
                  MuseTile(
                    key: ValueKey(single ? 'rule_test_result' : 'rule_test_result_$i'),
                    leading: Icon(
                      switch (r.outbound) {
                        Outbound.direct || Outbound.direct_with_fragment => Icons.near_me_outlined,
                        Outbound.block => Icons.block_outlined,
                        _ => Icons.vpn_lock_outlined,
                      },
                    ),
                    title: single ? museOutboundTitle(r.outbound) : '$target → ${museOutboundTitle(r.outbound)}',
                    subtitle: r.rule == null ? r.reason : '${museRuleDisplayName(r.rule!.name)} · ${r.reason}',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A rule's name for people (built-in / preset names are keys).
String museRuleDisplayName(String name) {
  if (name.startsWith('preset:')) {
    final key = name.substring(7).split(':').first;
    return '预设：${museRulePreset(key)?.title ?? key}';
  }
  return switch (name) {
    'builtin:bypassLan' => '局域网直连',
    _ when name.startsWith('builtin:') => '内置规则',
    _ => name,
  };
}


/// 1.12.0: 来自连接的规则 — 每个网站一行，可删除。
Future<void> showMuseQuickRulesSheet(BuildContext context) => showMuseSnapSheet<void>(
  context,
  title: '来自连接的规则',
  builder: (ctx, controller) => Consumer(
    builder: (ctx, ref, _) {
      final rules = museParseQuickRules(ref.watch(MusePrefs.quickRules));
      return ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s8),
            child: Text('在「活动 › 连接」详情里设置，优先于其他自定义规则（含子域名）。', style: MuseType.caption(ctx)),
          ),
          if (rules.isEmpty) const ListTile(title: Text('没有规则')),
          for (final r in rules)
            ListTile(
              key: ValueKey('quick_rule_${r.host}'),
              title: Text(r.host, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(r.way.title),
              trailing: IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outlined),
                onPressed: () => ref.read(MusePrefs.quickRules.notifier).update(museQuickRulesToRaw(museRemoveQuickRule(rules, r.host))),
              ),
            ),
        ],
      );
    },
  ),
);
