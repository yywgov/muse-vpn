// 穿云 1.4.0 - settings pages added in 1.4: 外观, 节点, 分流 (presets / hosts / rule tester),
// 网络 (DNS), 同步与备份 and 统计. All built from the grouped-list widgets and design tokens.
// Network-affecting options start off; nothing here changes the default connection path.
// Part of 穿云 (GPLv3).

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
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart' show museIsEncrypted;
import 'package:hiddify/features/muse/nodes/node_list.dart' show museAskText;
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
          trailing: value == current ? Icon(Icons.check_rounded, color: MusePalette.brand, size: MuseIconSize.small) : null,
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
                                ? const Icon(Icons.check_rounded, size: MuseIconSize.tiny, color: MusePalette.white)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              MuseTile(
                key: const ValueKey('appearance_text_size'),
                leading: const Icon(Icons.format_size_rounded),
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
                leading: const Icon(Icons.blur_on_rounded),
                title: '隐私模式',
                subtitle: '首页的流量、IP 等数字打码',
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
    final workers = ref.watch(MusePrefs.testWorkers);
    final timeout = ref.watch(MusePrefs.testTimeoutSec);
    final metas = MuseNodeMetas.parse(ref.watch(MusePrefs.nodeMeta));
    final hiddenCount = metas.hiddenTags.length;

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
                leading: const Icon(Icons.auto_fix_high_rounded),
                title: '节点名美化',
                value: ref.watch(MusePrefs.beautifyNames),
                onChanged: (v) => ref.read(MusePrefs.beautifyNames.notifier).update(v),
              ),
              MuseSwitchTile(
                key: const ValueKey('node_hide_duplicates'),
                leading: const Icon(Icons.filter_none_rounded),
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
          MuseSection(
            header: '测速（高级）',
            children: [
              MuseTile(
                key: const ValueKey('node_test_workers'),
                leading: const Icon(Icons.speed_rounded),
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
      .applyTo(museApplyPresets(own, museParsePresetChoice(ref.read(MusePrefs.rulePresets))));
}

class MuseRoutingPage extends HookConsumerWidget {
  const MuseRoutingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = museParsePresetChoice(ref.watch(MusePrefs.rulePresets));
    final hosts = museParseHosts(ref.watch(MusePrefs.hosts));

    Future<void> setChoice(String key, Outbound? way) async {
      final next = {...choice};
      if (way == null) {
        next.remove(key);
      } else {
        next[key] = way;
      }
      await ref.read(MusePrefs.rulePresets.notifier).update(musePresetChoiceToRaw(next));
    }

    return MuseScaffold(
      title: '分流',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '预设',
            footer: '修改后重新连接生效',
            dividerIndent: MuseSpace.s16,
            children: [
              for (final p in museRulePresets)
                MuseTile(
                  key: ValueKey('preset_${p.key}'),
                  title: p.title,
                  trailing: Text(choice.containsKey(p.key) ? museOutboundTitle(choice[p.key]!) : '关'),
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
                leading: const Icon(Icons.ios_share_rounded),
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
                  try {
                    final rules = museImportRules(text);
                    await ref.read(rulesNotifierProvider.notifier).museImport(rules);
                    _toast(ref, '已导入 ${rules.length} 条规则');
                  } catch (_) {
                    _toast(ref, '不是有效的规则文件', error: true);
                  }
                },
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
                suffixIcon: IconButton(key: const ValueKey('rule_test_go'), icon: const Icon(Icons.arrow_forward_rounded), onPressed: run),
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
                      Outbound.block => Icons.block_rounded,
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
  if (name.startsWith('preset:')) return '预设：${museRulePreset(name.substring(7))?.title ?? name.substring(7)}';
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
    return MuseScaffold(
      title: '网络',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '修改后重新连接生效',
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
    final url = ref.watch(MusePrefs.webdavUrl);
    final user = ref.watch(MusePrefs.webdavUser);
    final pass = ref.watch(MusePrefs.webdavPassword);
    final passphrase = ref.watch(MusePrefs.syncPassphrase);
    final lastAt = ref.watch(MusePrefs.syncLastAt);
    final busy = useState(false);

    Future<void> run(Future<String> Function() job) async {
      if (busy.value) return;
      busy.value = true;
      try {
        _toast(ref, await job());
      } on MuseSyncException catch (e) {
        _toast(ref, e.message, error: true);
      } catch (e) {
        _toast(ref, '失败：$e', error: true);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<String?> askPassword(String title) => museAskText(context, title, hint: '留空 = 不加密');

    return MuseScaffold(
      title: '同步与备份',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '坚果云 WebDAV',
            footer: '同步订阅、节点重命名/备注/隐藏、收藏、分流和设置；文件加密后上传',
            children: [
              MuseTile(
                key: const ValueKey('sync_url'),
                leading: const Icon(Icons.dns_outlined),
                title: '服务器',
                trailing: Text(Uri.tryParse(url)?.host ?? url, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '服务器地址', initial: url);
                  if (v != null) await ref.read(MusePrefs.webdavUrl.notifier).update(v.isEmpty ? 'https://dav.jianguoyun.com/dav/' : v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_user'),
                leading: const Icon(Icons.person_outline_rounded),
                title: '账号',
                trailing: Text(user.isEmpty ? '未填写' : user, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '坚果云账号（邮箱）', initial: user);
                  if (v != null) await ref.read(MusePrefs.webdavUser.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_password'),
                leading: const Icon(Icons.key_outlined),
                title: '应用密码',
                trailing: Text(pass.isEmpty ? '未填写' : '已填写'),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '应用密码（坚果云 › 安全选项 › 第三方应用管理）');
                  if (v != null && v.isNotEmpty) await ref.read(MusePrefs.webdavPassword.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_passphrase'),
                leading: const Icon(Icons.lock_outline_rounded),
                title: '同步密码',
                trailing: Text(passphrase.isEmpty ? '同应用密码' : '已设置'),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '同步密码（两台设备需相同；留空 = 用应用密码）');
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
                    : const Icon(Icons.sync_rounded),
                title: '立即同步',
                subtitle: lastAt == 0 ? null : '上次：${museUpdatedAgo(DateTime.fromMillisecondsSinceEpoch(lastAt), now: DateTime.now()).replaceAll('更新', '')}',
                onTap: busy.value ? null : () => run(() async => (await ref.read(museSyncServiceProvider).syncNow()).summary),
              ),
            ],
          ),
          MuseSection(
            header: '本地备份',
            children: [
              MuseTile(
                key: const ValueKey('backup_export'),
                leading: const Icon(Icons.save_alt_rounded),
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
                leading: const Icon(Icons.restore_rounded),
                title: '从备份恢复',
                onTap: () async {
                  final text = await museOpenTextFile();
                  if (text == null || !context.mounted) return;
                  var pw = '';
                  if (museIsEncrypted(text)) {
                    pw = await museAskText(context, '备份密码') ?? '';
                    if (pw.isEmpty) return;
                  }
                  await run(() async => (await ref.read(museSyncServiceProvider).importBackup(text, password: pw)).summary);
                },
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
                      ? Center(child: Text('还没有流量记录', style: MuseType.body(context).copyWith(color: mt.text3)))
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
        final h = c.maxHeight - labelH;
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
                        height: b.$2 == 0 ? MuseSize.barGap : math.max(MuseSize.barMin, h * b.$2 / maxV),
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
