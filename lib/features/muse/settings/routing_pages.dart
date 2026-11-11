// 穿云 - 设置 › 分流规则. 1.20.3：分「我的规则 / 规则来源 / 工具」三组，页顶一行写生效顺序；模式（规则 / 全局）与分应用代理在最上面；
// 导入导出收进右上 ⋯；自定义 hosts 挪到 网络 › DNS。 Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
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
  // 1.20.3：和连接时一样带上「已屏蔽」「来自连接」两层（局域网之后、其他规则之前），规则测试才说得准
  final applied = ref
      .read(ConfigOptions.museRouteMode)
      .applyTo(
        museApplyPresets(
          own,
          museParsePresetChoice(ref.read(MusePrefs.rulePresets)),
          remote: museParseRemoteRuleSets(ref.read(MusePrefs.remoteRuleSets)),
        ),
      );
  return museApplyBlockedHosts(
    museApplyQuickRules(musePinLanRule(applied), museParseQuickRules(ref.read(MusePrefs.quickRules))),
    museParseBlockedHosts(ref.read(MusePrefs.blockedHosts)),
  );
}

/// 1.20.3：分流规则页顶的一行，按 config_option_repository 里实际拼接的顺序写（局域网始终第一，不列）。
const museRoutingOrderText = '生效顺序：订阅覆写 → 已屏蔽 → 来自连接 → 自定义规则 → 预设 → 远程规则集 → 其余走代理。指定节点在规则、全局模式下都生效。';

/// 1.20.3：分流规则页「我的规则」组里那一行的标题（打开的页面标题是「我的规则」）。
const museMyRulesTitle = '我的规则';

/// 1.20.3：Wi‑Fi 规则把模式改成了现在这个（[applied] 是 Wi‑Fi 规则切到的模式，空 = 没切过）。
bool museRouteModeByWifi({required String applied, required MuseRouteMode current}) => applied.isNotEmpty && applied == current.key;

class MuseRoutingPage extends HookConsumerWidget {
  const MuseRoutingPage({super.key, this.embedded = false, this.android});

  /// 1.9.0 #17: shown as the 「分流」 tab of 「规则」 (body only, plus the rule list entry)
  final bool embedded;

  /// Platform override for tests; null = the running platform.
  final bool? android;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = museParsePresetChoice(ref.watch(MusePrefs.rulePresets));
    final nodeRules = museParseNodeRules(ref.watch(MusePrefs.nodeRules));
    final quickRules = museParseQuickRules(ref.watch(MusePrefs.quickRules));
    final blocked = museParseBlockedHosts(ref.watch(MusePrefs.blockedHosts));
    final remoteSets = museParseRemoteRuleSets(ref.watch(MusePrefs.remoteRuleSets));
    final adLevel = MuseAdBlockLevel.fromKey(ref.watch(Preferences.museAdBlockLevel));
    final mode = ref.watch(ConfigOptions.museRouteMode);
    final byWifi = museRouteModeByWifi(applied: ref.watch(MusePrefs.wifiModeApplied), current: mode);
    final isAndroid = android ?? PlatformUtils.isAndroid;
    final perAppOn = isAndroid && ref.watch(Preferences.perAppProxyModeInUse) != null;
    final mt = MuseTheme.of(context);

    final body = MuseGroupedBody(
        children: [
          // 1.20.3：谁先谁后，一行写清
          Padding(
            padding: EdgeInsets.fromLTRB(MuseSpace.page(context) + MuseSpace.s16, MuseSpace.s4, MuseSpace.page(context) + MuseSpace.s16, MuseSpace.s4),
            child: Text(museRoutingOrderText, key: const ValueKey('routing_order'), style: MuseType.caption(context).copyWith(color: mt.text2)),
          ),
          // 1.20.3：规则 / 全局（原来只有首页胶囊、托盘能改）
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('routing_mode'),
                leading: const Icon(Icons.alt_route_outlined),
                title: '模式',
                subtitle: byWifi ? '由「按 Wi‑Fi 切换模式」设定，手动改了以你的为准' : null,
                subtitleMaxLines: 2,
                trailing: SizedBox(
                  width: 128,
                  child: MuseSegmented<MuseRouteMode>(
                    key: const ValueKey('routing_mode_segmented'),
                    values: MuseRouteMode.values,
                    selected: mode,
                    label: (m) => m.title,
                    onChanged: (m) => ref.read(ConfigOptions.museRouteMode.notifier).update(m),
                  ),
                ),
              ),
              // 1.20.3：分应用代理放进分流规则（Android）；被它排除的应用不进穿云，按应用写的规则不生效
              if (isAndroid)
                MuseTile(
                  key: const ValueKey('settings_per_app'),
                  leading: const Icon(Icons.apps_outlined),
                  title: '分应用代理',
                  trailing: Text(perAppOn ? '开' : '关'),
                  chevron: true,
                  onTap: () => context.goNamed('perAppProxy'),
                ),
            ],
          ),
          MuseSection(
            header: museMyRulesTitle,
            children: [
              // 1.9.0 #17: the custom rule list; 1.20.3：挂在 /settings 下，页标题「我的规则」
              MuseTile(
                key: const ValueKey('routing_rule_list'),
                leading: const Icon(Icons.route_outlined),
                title: '自定义规则',
                chevron: true,
                onTap: () => context.goNamed('routingOptions'),
              ),
              MuseTile(
                key: const ValueKey('routing_node_rules'),
                leading: const Icon(Icons.hub_outlined),
                title: '指定节点',
                trailing: Text(nodeRules.isEmpty ? '无' : '${nodeRules.length} 条'),
                chevron: true,
                onTap: () => musePushPage(context, const MuseNodeRulesPage()),
              ),
              // 1.12.0: 在「活动 › 连接」里加的 直连 / 走代理；1.20.3：没有时也显示，写「无」
              MuseTile(
                key: const ValueKey('routing_quick_rules'),
                leading: const Icon(Icons.bolt_outlined),
                title: '来自连接的规则',
                trailing: Text(quickRules.isEmpty ? '无' : '${quickRules.length} 条'),
                chevron: true,
                onTap: () => showMuseQuickRulesSheet(context),
              ),
              // 1.20.3：在「活动 › 连接」里屏蔽的网站，原来只能靠 toast 撤销
              MuseTile(
                key: const ValueKey('routing_blocked_hosts'),
                leading: const Icon(Icons.do_not_disturb_on_outlined),
                title: '已屏蔽的网站',
                trailing: Text(blocked.isEmpty ? '无' : '${blocked.length} 个'),
                chevron: true,
                onTap: () => showMuseBlockedHostsSheet(context),
              ),
            ],
          ),
          MuseSection(
            header: '规则来源',
            children: [
              // 1.10.0: 去广告 moved here from the 设置 home page (same preference)
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
              MuseTile(
                key: const ValueKey('routing_presets'),
                leading: const Icon(Icons.playlist_add_check_outlined),
                title: '预设',
                trailing: Text(choice.isEmpty ? '未开启' : '已开启 ${choice.length} 个'),
                chevron: true,
                onTap: () => musePushPage(context, const MusePresetsPage()),
              ),
              // 1.20.3：远程规则集只在这里管理（内核与资源页只读显示下载状态）
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
            header: '工具',
            children: [
              MuseTile(
                key: const ValueKey('routing_tester'),
                leading: const Icon(Icons.science_outlined),
                title: '规则测试',
                subtitle: '看一个网址命中哪一层、走哪条规则',
                chevron: true,
                onTap: () => musePushPage(context, const MuseRuleTesterPage()),
              ),
            ],
          ),
        ],
      );
    return embedded ? body : MuseScaffold(title: '分流规则', actions: const [MuseRoutingMoreMenu()], body: body);
  }
}

/// 1.20.3：分流规则页右上 ⋯ —— 导出 / 导入 / 粘贴规则（原来是主列表里的四行，功能不变）。
class MuseRoutingMoreMenu extends ConsumerWidget {
  const MuseRoutingMoreMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> onSelected(String v) async {
      switch (v) {
        case 'export':
          final text = museExportRules(ref.read(rulesNotifierProvider));
          final ok = await museSaveTextFile(context, 'chuanyun-rules.json', text);
          if (ok) _toast(ref, '已导出');
        case 'export_singbox':
          // 1.9.0 #67：只导出你自己的规则（route.rules 片段），内置规则和预设不含在内
          final text = museExportRulesSingBox(ref.read(rulesNotifierProvider));
          final ok = await museSaveTextFile(context, 'chuanyun-rules-singbox.json', text);
          if (ok) _toast(ref, '已导出');
        case 'import':
          final text = await museOpenTextFile();
          if (text == null) return;
          await _importRulesText(ref, text);
        case 'paste':
          // 1.5.0 #59: 本应用导出的规则文件，以及 Clash / Surge 的规则行
          final text = await museAskText(context, '粘贴规则', hint: 'DOMAIN-SUFFIX,google.com,Proxy', maxLines: 8);
          if (text == null || text.trim().isEmpty) return;
          await _importRulesText(ref, text);
      }
    }

    return PopupMenuButton<String>(
      key: const ValueKey('routing_more'),
      tooltip: '更多',
      icon: const Icon(Icons.more_horiz_outlined),
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(key: ValueKey('routing_import'), value: 'import', child: Text('导入规则')),
        PopupMenuItem(key: ValueKey('routing_paste_rules'), value: 'paste', child: Text('粘贴规则')),
        PopupMenuDivider(),
        PopupMenuItem(key: ValueKey('routing_export'), value: 'export', child: Text('导出规则')),
        PopupMenuItem(key: ValueKey('routing_export_singbox'), value: 'export_singbox', child: Text('导出为 sing-box 格式')),
      ],
    );
  }
}

/// 1.20.3：在「活动 › 连接」里屏蔽的网站（MusePrefs.blockedHosts），每个一行，可删除。
Future<void> showMuseBlockedHostsSheet(BuildContext context) => showMuseSnapSheet<void>(
  context,
  title: '已屏蔽的网站',
  builder: (ctx, controller) => Consumer(
    builder: (ctx, ref, _) {
      final hosts = museParseBlockedHosts(ref.watch(MusePrefs.blockedHosts));
      return ListView(
        key: const ValueKey('blocked_hosts_sheet'),
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s8),
            child: Text('在「活动 › 连接」里点「屏蔽」加入，含子域名；排在订阅覆写之后、其他规则之前。', style: MuseType.caption(ctx)),
          ),
          if (hosts.isEmpty) const ListTile(title: Text('没有屏蔽的网站')),
          for (final h in hosts)
            ListTile(
              key: ValueKey('blocked_host_$h'),
              leading: const Icon(Icons.do_not_disturb_on_outlined),
              title: Text(h, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                key: ValueKey('blocked_host_delete_$h'),
                tooltip: '取消屏蔽',
                icon: const Icon(Icons.delete_outlined),
                onPressed: () => ref.read(MusePrefs.blockedHosts.notifier).update(museBlockedHostsToRaw([for (final x in hosts) if (x != h) x])),
              ),
            ),
        ],
      );
    },
  ),
);

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
    // 1.20.3：分应用代理里不走代理的应用不进穿云，给它写的应用规则不生效
    final perApp = ref.watch(musePerAppStateProvider).valueOrNull ?? (mode: null, active: const <String>{});
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
      actions: [IconButton(key: const ValueKey('node_rule_add'), tooltip: '添加', icon: const Icon(Icons.add_outlined), onPressed: () => edit())],
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
                  leading: Icon(museBypassedPackages(rules[i].packages, perApp).isEmpty ? Icons.hub_outlined : Icons.warning_amber_outlined),
                  title: nodeName(rules[i].node),
                  subtitle: [rules[i].summary, ?museBypassedNote(museBypassedPackages(rules[i].packages, perApp))].join('\n'),
                  subtitleMaxLines: 4,
                  trailing: IconButton(
                    key: ValueKey('node_rule_delete_$i'),
                    tooltip: '删除',
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
      actions: [IconButton(key: const ValueKey('remote_set_add'), tooltip: '添加', icon: const Icon(Icons.add_outlined), onPressed: add)],
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
                    tooltip: '删除',
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
                suffixIcon: IconButton(key: const ValueKey('rule_test_go'), tooltip: '开始测试', icon: const Icon(Icons.arrow_forward_outlined), onPressed: run),
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
  // 1.20.3：说出命中的是哪一层（和分流规则页顶的生效顺序一致）
  return switch (name) {
    'builtin:bypassLan' => '局域网直连',
    _ when name.startsWith('builtin:') => '内置规则',
    _ when name.startsWith(museBlockedHostsRuleName) => '已屏蔽的网站',
    _ when name.startsWith(museQuickRuleName) => '来自连接的规则',
    _ when name.startsWith('remote:') => '远程规则集',
    _ => '自定义规则：$name',
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
