// 穿云 1.4.0 - settings pages added in 1.4: 外观, 节点, 分流 (presets / hosts / rule tester),
// 网络 (DNS), 同步与备份 and 统计. All built from the grouped-list widgets and design tokens.
// Network-affecting options start off; nothing here changes the default connection path.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/lan_sync_service.dart';
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/logic/lan_sync.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
import 'package:hiddify/features/muse/widget/qr_view.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart' show museIsEncrypted;
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart' show museAskText, museNodeName;
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens a settings sub-page.
Future<void> musePushPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

void _toast(WidgetRef ref, String text, {bool error = false}) {
  try {
    final n = ref.read(inAppNotificationControllerProvider);
    error ? n.showErrorToast(text) : n.showSuccessToast(text);
  } catch (_) {}
}

/// 1.5.0 #59: this app's rule file, or else Clash / Surge rule lines converted.
Future<void> _importRulesText(WidgetRef ref, String text) async {
  List<Rule>? rules;
  var skipped = 0;
  try {
    rules = museImportRules(text);
  } catch (_) {
    final conv = museConvertClashRules(text);
    if (conv.converted > 0) {
      rules = conv.rules;
      skipped = conv.skipped;
    }
  }
  if (rules == null || rules.isEmpty) {
    _toast(ref, '没有可导入的规则', error: true);
    return;
  }
  await ref.read(rulesNotifierProvider.notifier).museImport(rules);
  _toast(ref, '已导入 ${rules.length} 条规则${skipped > 0 ? '，$skipped 行无法转换已跳过' : ''}');
}

/// A one-of-N choice as a dialog; null when dismissed.
Future<T?> musePick<T>(BuildContext context, String title, List<(T, String)> options, T current) => showDialog<T>(
  context: context,
  builder: (c) => SimpleDialog(
    title: Text(title),
    children: [
      for (final (value, label) in options)
        ListTile(
          key: ValueKey('pick_$label'),
          title: Text(label),
          trailing: value == current ? Icon(Icons.check_outlined, color: MusePalette.brand, size: MuseIconSize.small) : null,
          onTap: () => Navigator.of(c).pop(value),
        ),
    ],
  ),
);

// ======================================================================= 外观

class MuseAppearancePage extends HookConsumerWidget {
  const MuseAppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final themeMode = ref.watch(themePreferencesProvider);
    final shownTheme = themeMode == AppThemeMode.black ? AppThemeMode.dark : themeMode;
    final accent = MuseAccent.fromKey(ref.watch(MusePrefs.accent));
    final textSize = ref.watch(MusePrefs.textSize);
    return MuseScaffold(
      title: '外观',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('appearance_theme'),
                leading: const Icon(Icons.dark_mode_outlined),
                title: '深浅色',
                trailing: Text(shownTheme.present(t)),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<AppThemeMode>(
                    context,
                    '深浅色',
                    [for (final m in AppThemeMode.choices) (m, m.present(t))],
                    shownTheme,
                  );
                  if (picked != null) await ref.read(themePreferencesProvider.notifier).changeThemeMode(picked);
                },
              ),
              MuseTile(
                key: const ValueKey('appearance_accent'),
                leading: const Icon(Icons.palette_outlined),
                title: '主题色',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in MuseAccent.values)
                      Padding(
                        padding: const EdgeInsets.only(left: MuseSpace.s8),
                        child: InkWell(
                          key: ValueKey('accent_${a.key}'),
                          customBorder: const CircleBorder(),
                          onTap: () => ref.read(MusePrefs.accent.notifier).update(a.key),
                          child: Container(
                            width: MuseSpace.s24,
                            height: MuseSpace.s24,
                            decoration: BoxDecoration(
                              color: a.brand,
                              shape: BoxShape.circle,
                              border: a == accent ? Border.all(color: MuseTheme.of(context).text1, width: 2) : null,
                            ),
                            child: a == accent
                                ? const Icon(Icons.check_outlined, size: MuseIconSize.tiny, color: MusePalette.white)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              MuseTile(
                key: const ValueKey('appearance_text_size'),
                leading: const Icon(Icons.format_size_outlined),
                title: '字体大小',
                trailing: Text(museTextSizes.firstWhere((e) => e.$1 == textSize, orElse: () => museTextSizes[1]).$2),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<String>(context, '字体大小', museTextSizes, textSize);
                  if (picked != null) await ref.read(MusePrefs.textSize.notifier).update(picked);
                },
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('appearance_privacy'),
                leading: const Icon(Icons.blur_on_outlined),
                title: '隐私模式',
                info: '首页的流量、IP 等数字打码',
                value: ref.watch(MusePrefs.privacyMask),
                onChanged: (v) => ref.read(MusePrefs.privacyMask.notifier).update(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ======================================================================= 节点

class MuseNodeSettingsPage extends HookConsumerWidget {
  const MuseNodeSettingsPage({super.key});

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
            footer: '「自动」适合大多数订阅；节点不全或格式不对时可换一个再更新',
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

// ======================================================================= 开发者选项

/// 1.5.0: tuning nobody needs day to day (测速 并发数 / 超时 moved here from 设置 › 节点).
class MuseDeveloperPage extends HookConsumerWidget {
  const MuseDeveloperPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(MusePrefs.testWorkers);
    final timeout = ref.watch(MusePrefs.testTimeoutSec);
    return MuseScaffold(
      title: '开发者选项',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '测速',
            children: [
              MuseTile(
                key: const ValueKey('node_test_workers'),
                leading: const Icon(Icons.speed_outlined),
                title: '并发数',
                trailing: Text('$workers'),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<int>(context, '测速并发数', [for (final n in const [4, 8, 16, 32, 64]) (n, '$n')], workers);
                  if (picked != null) await ref.read(MusePrefs.testWorkers.notifier).update(picked);
                },
              ),
              MuseTile(
                key: const ValueKey('node_test_timeout'),
                leading: const Icon(Icons.timer_outlined),
                title: '超时',
                trailing: Text('$timeout 秒'),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<int>(context, '测速超时', [for (final n in const [3, 5, 8, 10, 15]) (n, '$n 秒')], timeout);
                  if (picked != null) await ref.read(MusePrefs.testTimeoutSec.notifier).update(picked);
                },
              ),
              MuseTile(
                key: const ValueKey('dev_reset_test'),
                leading: const Icon(Icons.restart_alt_outlined),
                title: '恢复默认',
                onTap: () async {
                  await ref.read(MusePrefs.testWorkers.notifier).update(museTestWorkersDefault);
                  await ref.read(MusePrefs.testTimeoutSec.notifier).update(museTestTimeoutDefault);
                  _toast(ref, '已恢复默认');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
  const MuseRoutingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = museParsePresetChoice(ref.watch(MusePrefs.rulePresets));
    final hosts = museParseHosts(ref.watch(MusePrefs.hosts));
    final nodeRules = museParseNodeRules(ref.watch(MusePrefs.nodeRules));
    final remoteSets = museParseRemoteRuleSets(ref.watch(MusePrefs.remoteRuleSets));

    return MuseScaffold(
      title: '分流',
      body: MuseGroupedBody(
        children: [
          // 1.5.0: changes reach a running connection by themselves (hot reload)
          MuseSection(
            children: [
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
      ),
    );
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
                      style: choice.containsKey(p.key) ? TextStyle(color: MusePalette.brand, fontWeight: FontWeight.w600) : null,
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
    final result = useState<MuseRuleMatch?>(null);
    final mt = MuseTheme.of(context);
    void run() {
      final v = controller.text.trim();
      if (v.isEmpty) return;
      result.value = museTestRules(museEffectiveRules(ref), v);
    }

    final r = result.value;
    return MuseScaffold(
      title: '规则测试',
      body: MuseGroupedBody(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context), vertical: MuseSpace.s8),
            child: TextField(
              key: const ValueKey('rule_test_field'),
              controller: controller,
              onSubmitted: (_) => run(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '输入网址或域名，如 chatgpt.com',
                filled: true,
                fillColor: mt.card,
                border: const OutlineInputBorder(borderRadius: MuseRadius.cardAll, borderSide: BorderSide.none),
                suffixIcon: IconButton(key: const ValueKey('rule_test_go'), icon: const Icon(Icons.arrow_forward_outlined), onPressed: run),
              ),
            ),
          ),
          if (r != null)
            MuseSection(
              children: [
                MuseTile(
                  key: const ValueKey('rule_test_result'),
                  leading: Icon(
                    switch (r.outbound) {
                      Outbound.direct || Outbound.direct_with_fragment => Icons.near_me_outlined,
                      Outbound.block => Icons.block_outlined,
                      _ => Icons.vpn_lock_outlined,
                    },
                  ),
                  title: museOutboundTitle(r.outbound),
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

// ======================================================================= 网络

class MuseNetworkPage extends HookConsumerWidget {
  const MuseNetworkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dns = museDnsPreset(ref.watch(MusePrefs.dnsPreset));
    final schedule = MuseSchedule.parse(ref.watch(MusePrefs.schedule));

    Future<void> pickTime(bool connect) async {
      final cur = connect ? schedule.connectAt : schedule.disconnectAt;
      final picked = await showTimePicker(
        context: context,
        initialTime: cur < 0 ? TimeOfDay(hour: connect ? 8 : 23, minute: 0) : TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
        helpText: connect ? '每天定时连接' : '每天定时断开',
        cancelText: '关闭',
      );
      final m = picked == null ? -1 : picked.hour * 60 + picked.minute;
      final next = connect
          ? MuseSchedule(connectAt: m, disconnectAt: schedule.disconnectAt)
          : MuseSchedule(connectAt: schedule.connectAt, disconnectAt: m);
      await ref.read(MusePrefs.schedule.notifier).update(next.toRaw());
    }

    return MuseScaffold(
      title: '网络',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('network_dns'),
                leading: const Icon(Icons.dns_outlined),
                title: '远程 DNS',
                trailing: Text(dns.title),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<String>(context, '远程 DNS', [for (final p in museDnsPresets) (p.key, p.title)], dns.key);
                  if (picked != null) await ref.read(MusePrefs.dnsPreset.notifier).update(picked);
                },
              ),
            ],
          ),
          // 1.4.1
          MuseSection(
            header: '定时',
            footer: '穿云需在运行（可在后台）；时间到时只执行一次，手动操作随时优先',
            children: [
              MuseTile(
                key: const ValueKey('network_schedule_connect'),
                leading: const Icon(Icons.alarm_on_outlined),
                title: '每天定时连接',
                trailing: Text(museMinuteLabel(schedule.connectAt)),
                chevron: true,
                onTap: () => pickTime(true),
              ),
              MuseTile(
                key: const ValueKey('network_schedule_disconnect'),
                leading: const Icon(Icons.alarm_off_outlined),
                title: '每天定时断开',
                trailing: Text(museMinuteLabel(schedule.disconnectAt)),
                chevron: true,
                onTap: () => pickTime(false),
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('network_quality_alert'),
                leading: const Icon(Icons.network_check_outlined),
                title: '连接质量提醒',
                info: '当前节点延迟持续偏高或超时时通知（每分钟测一次）',
                value: ref.watch(MusePrefs.qualityAlert),
                onChanged: (v) => ref.read(MusePrefs.qualityAlert.notifier).update(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ======================================================================= files

/// Saves [text] as [name] (Android: the system save dialog; Windows: a save-as dialog).
Future<bool> museSaveTextFile(BuildContext context, String name, String text) async {
  try {
    final bytes = utf8.encode(text);
    final path = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
    if (path == null) return false;
    if (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) await File(path).writeAsBytes(bytes);
    return true;
  } catch (_) {
    return false;
  }
}

/// Picks a text file; null when cancelled or unreadable.
Future<String?> museOpenTextFile() async {
  try {
    final r = await FilePicker.platform.pickFiles(withData: true);
    final f = r?.files.firstOrNull;
    if (f == null) return null;
    final data = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    return data == null ? null : utf8.decode(data, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

// ======================================================================= 同步与备份

class MuseSyncPage extends HookConsumerWidget {
  const MuseSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastAt = ref.watch(MusePrefs.syncLastAt);
    final busy = useState(false);
    final webdavUser = ref.watch(MusePrefs.webdavUser);

    Future<void> run(Future<String> Function() job) async {
      if (busy.value) return;
      busy.value = true;
      try {
        final msg = await job();
        if (msg.isNotEmpty) _toast(ref, msg);
      } on MuseSyncException catch (e) {
        _toast(ref, e.message, error: true);
      } on MuseLanException catch (e) {
        _toast(ref, e.message, error: true);
      } catch (e) {
        _toast(ref, '失败：$e', error: true);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    /// The joining side: confirm, then sync with the device in [raw].
    Future<void> join(String? raw) async {
      if (raw == null || raw.trim().isEmpty || !context.mounted) return;
      final p = museParseLanPairing(raw);
      if (p == null) {
        _toast(ref, '不是穿云的配对码', error: true);
        return;
      }
      if (p.expired(DateTime.now())) {
        _toast(ref, '配对码已过期，请在对方设备上重新打开', error: true);
        return;
      }
      final ok = await museConfirm(
        context,
        title: '局域网同步',
        message: '与「${p.device.isEmpty ? p.host : p.device}」合并设置和订阅？\n两边各自的修改都会保留（同一项以较新的为准），订阅只增不删。',
        okText: '同步',
      );
      if (!ok) return;
      await run(() async => (await museLanSyncWith(ref.read(museSyncServiceProvider), p)).summary);
    }

    Future<String?> askPassword(String title) => museAskText(context, title, hint: '留空 = 不加密', obscure: true);

    return MuseScaffold(
      title: '同步与备份',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '局域网同步',
            footer: '两台设备连同一 Wi‑Fi / 局域网，无需账号；配对码 3 分钟内有效、只能用一次，数据全程加密',
            children: [
              MuseTile(
                key: const ValueKey('lan_host'),
                leading: const Icon(Icons.qr_code_2_outlined),
                title: '显示配对码',
                subtitle: '在另一台设备上扫码或输入',
                chevron: true,
                onTap: busy.value ? null : () => showMuseLanHostSheet(context),
              ),
              if (PlatformUtils.isAndroid || PlatformUtils.isIOS)
                MuseTile(
                  key: const ValueKey('lan_scan'),
                  leading: busy.value
                      ? const SizedBox(
                          width: MuseIconSize.small,
                          height: MuseIconSize.small,
                          child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                        )
                      : const Icon(Icons.qr_code_scanner_outlined),
                  title: '扫码配对',
                  chevron: true,
                  onTap: busy.value ? null : () async => join(await ref.read(dialogNotifierProvider.notifier).showQrScanner()),
                ),
              MuseTile(
                key: const ValueKey('lan_type'),
                leading: const Icon(Icons.keyboard_outlined),
                title: '输入配对码',
                chevron: true,
                onTap: busy.value ? null : () async => join(await museAskText(context, '配对码', hint: '192.168.1.5:43125 ABCD-EFGH-…')),
              ),
              if (lastAt != 0)
                MuseTile(
                  key: const ValueKey('sync_last'),
                  leading: const Icon(Icons.history_outlined),
                  title: '上次同步',
                  trailing: Text(museUpdatedAgo(DateTime.fromMillisecondsSinceEpoch(lastAt), now: DateTime.now()).replaceAll('更新', '')),
                ),
            ],
          ),
          MuseSection(
            header: '本地备份',
            children: [
              MuseTile(
                key: const ValueKey('backup_export'),
                leading: const Icon(Icons.save_alt_outlined),
                title: '导出备份',
                onTap: () async {
                  final pw = await askPassword('备份密码');
                  if (pw == null || !context.mounted) return;
                  await run(() async {
                    final text = await ref.read(museSyncServiceProvider).exportBackup(password: pw);
                    if (!context.mounted) return '';
                    final ok = await museSaveTextFile(context, 'chuanyun-backup.json', text);
                    return ok ? '已导出' : '已取消';
                  });
                },
              ),
              MuseTile(
                key: const ValueKey('backup_export_redacted'),
                leading: const Icon(Icons.shield_outlined),
                title: '导出脱敏备份',
                subtitle: '不含订阅链接',
                onTap: () => run(() async {
                  final text = await ref.read(museSyncServiceProvider).exportBackup(redact: true);
                  if (!context.mounted) return '';
                  final ok = await museSaveTextFile(context, 'chuanyun-backup-redacted.json', text);
                  return ok ? '已导出' : '已取消';
                }),
              ),
              MuseTile(
                key: const ValueKey('backup_import'),
                leading: const Icon(Icons.restore_outlined),
                title: '从备份恢复',
                onTap: () async {
                  final text = await museOpenTextFile();
                  if (text == null || !context.mounted) return;
                  var pw = '';
                  if (museIsEncrypted(text)) {
                    pw = await museAskText(context, '备份密码', obscure: true) ?? '';
                    if (pw.isEmpty) return;
                  }
                  await run(() async => (await ref.read(museSyncServiceProvider).importBackup(text, password: pw)).summary);
                },
              ),
            ],
          ),
          MuseSection(
            header: '更多',
            children: [
              MuseTile(
                key: const ValueKey('sync_webdav'),
                leading: const Icon(Icons.cloud_sync_outlined),
                title: 'WebDAV 同步',
                trailing: Text(webdavUser.isEmpty ? '未设置' : '已设置'),
                chevron: true,
                onTap: () => musePushPage(context, const MuseWebdavPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A yes / no question; false when dismissed.
Future<bool> museConfirm(BuildContext context, {required String title, required String message, String okText = '确定'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(key: const ValueKey('confirm_cancel'), onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          FilledButton(key: const ValueKey('confirm_ok'), onPressed: () => Navigator.of(c).pop(true), child: Text(okText)),
        ],
      ),
    ) ??
    false;

/// 局域网同步, the side that shows the code: listens only while this sheet is open.
Future<void> showMuseLanHostSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: MuseColors.card(context),
  builder: (_) => const MuseLanHostSheet(),
);

class MuseLanHostSheet extends ConsumerStatefulWidget {
  const MuseLanHostSheet({super.key, this.address, this.ttl = museLanPairingTtl});

  /// fixed address (tests); null = the LAN address
  final String? address;
  final Duration ttl;

  @override
  ConsumerState<MuseLanHostSheet> createState() => _MuseLanHostSheetState();
}

class _MuseLanHostSheetState extends ConsumerState<MuseLanHostSheet> {
  late final MuseLanHost _host;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _host = MuseLanHost(
      ref.read(museSyncServiceProvider),
      confirm: (device) async {
        if (!mounted) return false;
        return museConfirm(
          context,
          title: '局域网同步',
          message: '「$device」请求同步设置和订阅，同意吗？',
          okText: '同意',
        );
      },
      onChange: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_host.start(address: widget.address, ttl: widget.ttl));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _host.state == MuseLanHostState.waiting) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_host.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final p = _host.pairing;
    final left = p == null ? Duration.zero : Duration(milliseconds: p.expiresAt - DateTime.now().millisecondsSinceEpoch);
    final secs = left.isNegative ? 0 : left.inSeconds;
    final Widget body = switch (_host.state) {
      // 1.5.0: the QR code's place, pulsing, instead of a spinner
      MuseLanHostState.starting => const Padding(
        padding: EdgeInsets.all(MuseSpace.s32),
        child: Center(child: MuseSkeleton(child: MuseSkeletonBox(width: MuseSize.qrCode, height: MuseSize.qrCode, radius: MuseRadius.cardAll))),
      ),
      MuseLanHostState.waiting when p != null => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MuseQrView(p.toUri(), key: const ValueKey('lan_qr')),
          const SizedBox(height: MuseSpace.s16),
          SelectableText(
            p.manualCode,
            key: const ValueKey('lan_code'),
            textAlign: TextAlign.center,
            style: MuseType.body(context).copyWith(fontFeatures: MuseType.tabular, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: MuseSpace.s8),
          Text(
            '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')} 后失效 · 另一台设备：设置 › 同步与备份 › 扫码或输入配对码',
            textAlign: TextAlign.center,
            style: MuseType.caption(context),
          ),
          if (PlatformUtils.isWindows) ...[
            const SizedBox(height: MuseSpace.s4),
            Text('Windows 首次使用会询问防火墙，请允许「专用网络」', textAlign: TextAlign.center, style: MuseType.caption(context)),
          ],
        ],
      ),
      MuseLanHostState.syncing => Padding(
        padding: const EdgeInsets.all(MuseSpace.s24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: MuseIconSize.small, height: MuseIconSize.small, child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke)),
            const SizedBox(width: MuseSpace.s12),
            Text('正在同步…', style: MuseType.body(context)),
          ],
        ),
      ),
      _ => Padding(
        padding: const EdgeInsets.all(MuseSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _host.state == MuseLanHostState.done ? Icons.check_circle_outlined : Icons.error_outlined,
              color: _host.state == MuseLanHostState.done ? MusePalette.green : MusePalette.orange,
              size: MuseSize.emptyIcon,
            ),
            const SizedBox(height: MuseSpace.s12),
            Text(_host.message, key: const ValueKey('lan_host_message'), textAlign: TextAlign.center, style: MuseType.body(context)),
          ],
        ),
      ),
    };
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          key: const ValueKey('lan_host_sheet'),
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('局域网同步', style: MuseType.title(context)),
              const SizedBox(height: MuseSpace.s16),
              Center(child: body),
              const SizedBox(height: MuseSpace.s16),
              Text(
                '同步：订阅、节点重命名 / 备注 / 隐藏、收藏、分流和设置',
                textAlign: TextAlign.center,
                style: MuseType.caption(context).copyWith(color: mt.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1.4.1: WebDAV (any server) — the secondary sync, under 同步与备份 › 更多.
class MuseWebdavPage extends HookConsumerWidget {
  const MuseWebdavPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(MusePrefs.webdavUrl);
    final user = ref.watch(MusePrefs.webdavUser);
    final pass = ref.watch(MusePrefs.webdavPassword);
    final passphrase = ref.watch(MusePrefs.syncPassphrase);
    final lastAt = ref.watch(MusePrefs.syncLastAt);
    final busy = useState(false);

    Future<void> syncNow() async {
      if (busy.value) return;
      busy.value = true;
      try {
        _toast(ref, (await ref.read(museSyncServiceProvider).syncNow()).summary);
      } on MuseSyncException catch (e) {
        _toast(ref, e.message, error: true);
      } catch (e) {
        _toast(ref, '失败：$e', error: true);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return MuseScaffold(
      title: 'WebDAV 同步',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '支持任意 WebDAV 服务；文件加密后上传，两台设备的同步密码需相同',
            children: [
              MuseTile(
                key: const ValueKey('sync_url'),
                leading: const Icon(Icons.dns_outlined),
                title: '服务器',
                trailing: Text(url.isEmpty ? '未填写' : (Uri.tryParse(url)?.host ?? url), overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '服务器地址', initial: url, hint: 'https://dav.example.com/dav/');
                  if (v != null) await ref.read(MusePrefs.webdavUrl.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_user'),
                leading: const Icon(Icons.person_outlined),
                title: '账号',
                trailing: Text(user.isEmpty ? '未填写' : user, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '账号', initial: user);
                  if (v != null) await ref.read(MusePrefs.webdavUser.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_password'),
                leading: const Icon(Icons.key_outlined),
                title: '密码',
                trailing: Text(pass.isEmpty ? '未填写' : '已填写'),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '密码（部分服务需使用「应用密码」）', obscure: true);
                  if (v != null && v.isNotEmpty) await ref.read(MusePrefs.webdavPassword.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_passphrase'),
                leading: const Icon(Icons.lock_outlined),
                title: '同步密码',
                trailing: Text(passphrase.isEmpty ? '同登录密码' : '已设置'),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '同步密码（留空 = 用登录密码）', obscure: true);
                  if (v != null) await ref.read(MusePrefs.syncPassphrase.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_now'),
                leading: busy.value
                    ? const SizedBox(
                        width: MuseIconSize.small,
                        height: MuseIconSize.small,
                        child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                      )
                    : const Icon(Icons.sync_outlined),
                title: '立即同步',
                subtitle: lastAt == 0 ? null : '上次：${museUpdatedAgo(DateTime.fromMillisecondsSinceEpoch(lastAt), now: DateTime.now()).replaceAll('更新', '')}',
                onTap: busy.value ? null : syncNow,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ======================================================================= 统计

class MuseStatsPage extends HookConsumerWidget {
  const MuseStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = MuseTrafficLog.parse(ref.watch(MusePrefs.trafficLog));
    final monthly = useState(false);
    final now = DateTime.now();
    final days = log.lastDays(now, 14);
    final months = log.months();
    final shownMonths = months.length > 12 ? months.sublist(months.length - 12) : months;
    final bars = monthly.value
        ? [for (final m in shownMonths) (m.$1.substring(5), m.$2 + m.$3)]
        : [for (final d in days) (d.$1.substring(8), d.$2 + d.$3)];
    final today = days.isEmpty ? 0 : days.last.$2 + days.last.$3;
    final thisMonth = months.isEmpty || months.last.$1 != museMonthKey(now) ? 0 : months.last.$2 + months.last.$3;
    final report = museMonthlyReport(log, museMonthKey(now), bytes: museBytes);
    final mt = MuseTheme.of(context);

    return MuseScaffold(
      title: '统计',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            dividerIndent: MuseSpace.s16,
            children: [
              MuseTile(title: '今天', trailing: Text(museBytes(today), style: const TextStyle(fontFeatures: MuseType.tabular))),
              MuseTile(title: '本月', trailing: Text(museBytes(thisMonth), style: const TextStyle(fontFeatures: MuseType.tabular))),
            ],
          ),
          MuseSection(
            header: monthly.value ? '每月流量' : '近 14 天流量',
            headerTrailing: SegmentedButton<bool>(
              key: const ValueKey('stats_range'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              segments: const [ButtonSegment(value: false, label: Text('日')), ButtonSegment(value: true, label: Text('月'))],
              selected: {monthly.value},
              onSelectionChanged: (s) => monthly.value = s.first,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(MuseSpace.s16),
                child: SizedBox(
                  height: MuseSize.chartHeight,
                  child: bars.every((b) => b.$2 == 0)
                      ? Center(child: Text('还没有流量记录', style: MuseType.body(context).copyWith(color: mt.text2)))
                      : _MuseBarChart(bars: bars),
                ),
              ),
            ],
          ),
          MuseSection(
            header: '本月报告',
            dividerIndent: MuseSpace.s16,
            children: [for (final line in report) MuseTile(title: line)],
          ),
        ],
      ),
    );
  }
}

class _MuseBarChart extends StatelessWidget {
  const _MuseBarChart({required this.bars});

  final List<(String, int)> bars;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final maxV = bars.map((b) => b.$2).fold<int>(1, math.max);
    return LayoutBuilder(
      builder: (context, c) {
        final labelH = MuseSpace.s16 + MuseSpace.s4;
        // 1.4.1: never negative (a very short box / large text)
        final h = math.max(0.0, c.maxHeight - labelH);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final b in bars)
              Expanded(
                child: Tooltip(
                  message: '${b.$1}  ${museBytes(b.$2)}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: MuseSize.barGap),
                        height: b.$2 == 0 ? MuseSize.barGap : math.min(h, math.max(MuseSize.barMin, h * b.$2 / maxV)),
                        decoration: BoxDecoration(
                          color: b.$2 == 0 ? mt.hairline : MusePalette.brand,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(MuseSize.barMin)),
                        ),
                      ),
                      SizedBox(
                        height: labelH,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Text(b.$1, style: MuseType.caption(context), maxLines: 1, overflow: TextOverflow.clip),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
