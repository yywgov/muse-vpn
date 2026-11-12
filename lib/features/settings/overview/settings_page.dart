// 穿云 - 设置 tab.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
//
// 1.3.0: grouped cards (icon | label | trailing control), no explanatory small text.
// 1.10.0: eight rows — 外观, 自动连接, 分应用代理 (Android), 网络, 活动, 备份与同步, 内核与资源, 关于 —
// plus 开发者选项 once it was turned on. Everything else moved to the page it belongs to:
// 智能保持连接 → 自动连接; 高级 → 网络 › 高级; 统计 / 诊断 → 活动 tabs; 去广告 → 规则 › 分流;
// 订阅自动更新 → 订阅 › ⋯; 节点 → 节点 › ⋯ › 节点设置; Android 通用 / 隐私与后台 → 外观;
// Windows 电脑 → 网络 (运行模式), 自动连接 (静默启动), 外观 (窗口). 帮助与隐私 and 后台保活 are gone.
// 1.11.0: 备份与同步 is gone (导出 / 导入配置 on 关于); seven rows.
// 1.20.3：一级结构改为 外观、启动与断线、分流规则、网络、隐私与通知、活动、诊断、内核与资源、备份与恢复、关于（+ 开发者选项）。
// Old names still find their new place through search (logic/settings_index.dart); every
// preference keeps its storage key.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/muse/activity/activity_page.dart';
import 'package:hiddify/features/muse/config/rules_page.dart';
import 'package:hiddify/features/muse/nodes/subs_sheet.dart' show museOpenSubscriptions;
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/auto_connect_page.dart';
import 'package:hiddify/features/muse/settings/color_choice_picker.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/settings/resources_page.dart';
import 'package:hiddify/features/muse/settings/settings_search.dart';
import 'package:hiddify/features/muse/settings/theme_preview_page.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart' show museDiagnosePath, museDiagnoseLocation;
import 'package:hiddify/features/muse/settings/wifi_mode_page.dart' show MuseWifiRulesPage;
import 'package:hiddify/features/settings/data/config_option_repository.dart' show ConfigOptions;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 1.10.0: the rows of the 设置 home page, in order (pure, for tests). 1.20.3：按审查清单的一级结构——
/// 外观、启动与断线、分流规则、网络、隐私与通知、活动、诊断、内核与资源、备份与恢复、关于、开发者选项（打开后）。
/// 分应用代理（Android）进了分流规则页；旧名字都还能搜到。
List<String> museSettingsHomeRows({required bool android, required bool developer}) => [
  '外观',
  museStartupTitle,
  '分流规则',
  '网络',
  musePrivacyTitle,
  '活动',
  '诊断',
  '内核与资源',
  '备份与恢复',
  '关于',
  if (developer) '开发者选项',
];

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final android = PlatformUtils.isAndroid;
    // 1.20.3: 外观一行显示当前配色（原来显示深浅色，选了终端绿等主题时会对不上）
    final colors = ref.watch(museColorChoiceProvider);
    final devMode = ref.watch(MusePrefs.devMode);
    // 1.9.0 #5
    final autoSummary = museAutoConnectSummary(
      onDemand: ref.watch(MusePrefs.onDemand) && museOnDemandSsids(ref.watch(MusePrefs.wifiRules)).isNotEmpty,
      schedule: MuseSchedule.parse(ref.watch(MusePrefs.schedule)),
      autoStart: PlatformUtils.isWindows && (ref.watch(autoStartNotifierProvider).valueOrNull ?? false),
    );

    // 1.5.0 #101: jump to a setting found by search (1.10.0 / 1.20.3: at its new place)
    void openEntry(MuseSettingEntry e) {
      switch (e.page) {
        case MuseSettingPage.autoConnect:
          musePushPage(context, const MuseAutoConnectPage());
        case MuseSettingPage.wifiRules:
          musePushPage(context, const MuseWifiRulesPage());
        case MuseSettingPage.advanced:
          musePushPage(context, const MuseNetworkPage(advancedOpen: true));
        case MuseSettingPage.network:
          musePushPage(context, const MuseNetworkPage());
        case MuseSettingPage.appearance:
          musePushPage(context, const MuseAppearancePage());
        case MuseSettingPage.privacy:
          musePushPage(context, const MusePrivacyPage());
        case MuseSettingPage.windowAdvanced:
          musePushPage(context, const MuseAppearancePage(windowAdvancedOpen: true));
        case MuseSettingPage.nodes || MuseSettingPage.nodesAdvanced:
          musePushPage(context, const MuseNodeSettingsPage());
        case MuseSettingPage.routing:
          museOpenRules(context);
        case MuseSettingPage.myRules:
          context.goNamed('routingOptions');
        case MuseSettingPage.overrides:
          museOpenRules(context, tab: MuseRulesTab.overrides);
        case MuseSettingPage.subscriptions:
          museOpenSubscriptions(context, ref);
        case MuseSettingPage.subSettings:
          musePushPage(context, const MuseSubSettingsPage());
        case MuseSettingPage.stats:
          context.go(museActivityLocation(MuseActivityTab.stats));
        case MuseSettingPage.diagnose:
          context.go(museDiagnoseLocation(section: museDiagnoseSectionForSetting(e.title)));
        case MuseSettingPage.developer:
          musePushPage(context, const MuseDeveloperPage());
        case MuseSettingPage.resources:
          musePushPage(context, const MuseResourcesPage());
        case MuseSettingPage.themePreview:
          musePushPage(context, const MuseThemePreviewPage());
        case MuseSettingPage.perApp:
          context.goNamed('perAppProxy');
        case MuseSettingPage.sync:
          musePushPage(context, const MuseBackupPage());
        case MuseSettingPage.about:
          context.goNamed('about');
        case MuseSettingPage.openSource:
          context.goNamed('openSource');
        case MuseSettingPage.activity:
          context.go(museActivityLocation(museActivityTabForSetting(e.title)));
      }
    }

    return MuseScaffold(
      large: true,
      title: '设置',
      actions: [
        IconButton(
          key: const ValueKey('settings_search'),
          tooltip: '搜索设置',
          icon: const Icon(Icons.search_outlined),
          onPressed: () async {
            final picked = await showMuseSettingsSearch(context, developer: ref.read(MusePrefs.devMode));
            if (picked != null && context.mounted) openEntry(picked);
          },
        ),
      ],
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('theme_mode'),
                leading: const Icon(Icons.palette_outlined),
                title: '外观',
                trailing: Text(colors.title),
                chevron: true,
                onTap: () => musePushPage(context, const MuseAppearancePage()),
              ),
              // 1.9.0 #5 自动连接；1.20.3：「启动与断线」（+ 节点失效自动切换、Wi‑Fi 规则）
              MuseTile(
                key: const ValueKey('settings_auto_connect'),
                leading: const Icon(Icons.schedule_outlined),
                title: museStartupTitle,
                trailing: Text(autoSummary),
                chevron: true,
                onTap: () => musePushPage(context, const MuseAutoConnectPage()),
              ),
            ],
          ),
          // 1.20.3：用户找分流比找 DNS 多，排在网络前面
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('settings_rules'),
                leading: const Icon(Icons.rule_outlined),
                title: '分流规则',
                trailing: Text('${ref.watch(ConfigOptions.museRouteMode).title}模式'),
                chevron: true,
                onTap: () => museOpenRules(context),
              ),
              MuseTile(
                key: const ValueKey('settings_network'),
                leading: const Icon(Icons.lan_outlined),
                title: '网络',
                chevron: true,
                onTap: () => musePushPage(context, const MuseNetworkPage()),
              ),
              // 1.20.3：隐私 + Android 通知
              MuseTile(
                key: const ValueKey('settings_privacy_home'),
                leading: const Icon(Icons.shield_outlined),
                title: musePrivacyTitle,
                chevron: true,
                onTap: () => musePushPage(context, const MusePrivacyPage()),
              ),
            ],
          ),
          MuseSection(
            children: [
              // 1.8.0; 1.20.3：连接 / 日志 / DNS / 统计（诊断升为一级）
              MuseTile(
                key: const ValueKey('settings_activity'),
                leading: const Icon(Icons.swap_vert_outlined),
                title: '活动',
                chevron: true,
                onTap: () => context.go(museActivityLocation(MuseActivityTab.connections)),
              ),
              // 1.20.3：唯一的诊断入口
              MuseTile(
                key: const ValueKey('settings_diagnose'),
                leading: const Icon(Icons.medical_services_outlined),
                title: '诊断',
                chevron: true,
                onTap: () => context.go(museDiagnosePath),
              ),
            ],
          ),
          MuseSection(
            children: [
              // 1.6.0 C10; 1.9.0 #8: 内核 (Windows / Android) + 资源 on one page
              MuseTile(
                key: const ValueKey('settings_resources'),
                leading: const Icon(Icons.memory_outlined),
                title: '内核与资源',
                trailing: (PlatformUtils.isWindows || android) ? Text(MuseCoreKind.fromKey(ref.watch(MusePrefs.coreKind)).title) : null,
                chevron: true,
                onTap: () => musePushPage(context, const MuseResourcesPage()),
              ),
              // 1.20.3：导出 / 导入配置（原在关于页底部）
              MuseTile(
                key: const ValueKey('settings_backup'),
                leading: const Icon(Icons.settings_backup_restore_outlined),
                title: '备份与恢复',
                chevron: true,
                onTap: () => musePushPage(context, const MuseBackupPage()),
              ),
              MuseTile(
                key: const ValueKey('settings_about'),
                leading: const Icon(Icons.info_outlined),
                title: '关于',
                chevron: true,
                onTap: () => context.goNamed('about'),
              ),
            ],
          ),
          // 1.6.0 C10 (#127): only after 关于's icon was tapped 7 times
          if (devMode)
            MuseSection(
              children: [
                MuseTile(
                  key: const ValueKey('settings_developer'),
                  leading: const Icon(Icons.developer_mode_outlined),
                  title: '开发者选项',
                  chevron: true,
                  onTap: () => musePushPage(context, const MuseDeveloperPage()),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A one-of-N choice as a simple dialog; null when dismissed.
Future<T?> museSettingPick<T>(BuildContext context, String title, List<(T, String)> options, T current) =>
    showDialog<T>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (value, label) in options)
            ListTile(
              key: ValueKey('pick_$label'),
              title: Text(label),
              trailing: value == current
                  ? Icon(Icons.check_outlined, color: museBrandOf(context), size: MuseIconSize.small)
                  : null,
              onTap: () => Navigator.of(c).pop(value),
            ),
        ],
      ),
    );

/// A green dot at the end of a row whose feature is on.
class MuseStatusDot extends StatelessWidget {
  const MuseStatusDot({super.key, this.color = MusePalette.green});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: MuseSize.dot,
    height: MuseSize.dot,
    margin: const EdgeInsets.only(right: MuseSpace.s8),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
