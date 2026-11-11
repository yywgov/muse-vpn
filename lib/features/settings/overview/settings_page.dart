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
// Old names still find their new place through search (logic/settings_index.dart); every
// preference keeps its storage key.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
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
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/settings/resources_page.dart';
import 'package:hiddify/features/muse/settings/settings_search.dart';
import 'package:hiddify/features/muse/settings/theme_preview_page.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 1.10.0: the rows of the 设置 home page, in order (pure, for tests). 1.11.0: 备份与同步 is gone
/// (导出 / 导入配置 are on 关于).
List<String> museSettingsHomeRows({required bool android, required bool developer}) => [
  '外观',
  '自动连接',
  if (android) '分应用代理',
  '网络',
  // 1.20.2：订阅页并入节点页，分流规则搬到「网络」下面
  '分流规则',
  '活动',
  '内核与资源',
  '关于',
  if (developer) '开发者选项',
];

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final android = PlatformUtils.isAndroid;
    final perAppOn = ref.watch(Preferences.perAppProxyModeInUse) != null;
    final themeMode = ref.watch(themePreferencesProvider);
    final shownTheme = themeMode == AppThemeMode.black ? AppThemeMode.dark : themeMode;
    final devMode = ref.watch(MusePrefs.devMode);
    // 1.9.0 #5
    final autoSummary = museAutoConnectSummary(
      autoRun: android && ref.watch(MusePrefs.autoRun),
      onDemand: ref.watch(MusePrefs.onDemand) && museOnDemandSsids(ref.watch(MusePrefs.wifiRules)).isNotEmpty,
      schedule: MuseSchedule.parse(ref.watch(MusePrefs.schedule)),
      autoStart: PlatformUtils.isWindows && (ref.watch(autoStartNotifierProvider).valueOrNull ?? false),
    );

    // 1.5.0 #101: jump to a setting found by search (1.10.0: at its new place)
    void openEntry(MuseSettingEntry e) {
      switch (e.page) {
        case MuseSettingPage.autoConnect:
          musePushPage(context, MuseAutoConnectPage(initiallyMore: museAutoConnectMoreRows.any(e.title.startsWith)));
        case MuseSettingPage.advanced:
          musePushPage(context, const MuseNetworkPage(advancedOpen: true));
        case MuseSettingPage.network:
          musePushPage(context, const MuseNetworkPage());
        case MuseSettingPage.appearance:
          musePushPage(context, const MuseAppearancePage());
        case MuseSettingPage.windowAdvanced:
          musePushPage(context, const MuseAppearancePage(windowAdvancedOpen: true));
        case MuseSettingPage.nodes:
          musePushPage(context, const MuseNodeSettingsPage());
        case MuseSettingPage.nodesAdvanced:
          musePushPage(context, const MuseNodeSettingsPage(advancedOpen: true));
        case MuseSettingPage.routing:
          museOpenRules(context);
        case MuseSettingPage.overrides:
          museOpenRules(context, tab: MuseRulesTab.overrides);
        case MuseSettingPage.subscriptions:
          museOpenSubscriptions(context, ref);
        case MuseSettingPage.stats:
          context.go(museActivityLocation(MuseActivityTab.stats));
        case MuseSettingPage.diagnose:
          context.go(museActivityLocation(MuseActivityTab.diagnose));
        case MuseSettingPage.developer:
          musePushPage(context, const MuseDeveloperPage());
        case MuseSettingPage.resources:
          musePushPage(context, const MuseResourcesPage());
        case MuseSettingPage.themePreview:
          musePushPage(context, const MuseThemePreviewPage());
        case MuseSettingPage.perApp:
          context.goNamed('perAppProxy');
        case MuseSettingPage.about || MuseSettingPage.sync:
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
                trailing: Text(shownTheme.present(t)),
                chevron: true,
                onTap: () => musePushPage(context, const MuseAppearancePage()),
              ),
              // 1.9.0 #5: 自动运行 / 按需运行 / 定时 / 开机自启; 1.10.0: + 智能保持连接
              MuseTile(
                key: const ValueKey('settings_auto_connect'),
                leading: const Icon(Icons.schedule_outlined),
                title: '自动连接',
                trailing: Text(autoSummary),
                chevron: true,
                onTap: () => musePushPage(context, const MuseAutoConnectPage()),
              ),
              if (android)
                MuseTile(
                  key: const ValueKey('settings_per_app'),
                  leading: const Icon(Icons.apps_outlined),
                  title: '分应用代理',
                  trailing: perAppOn ? const MuseStatusDot() : null,
                  chevron: true,
                  onTap: () => context.goNamed('perAppProxy'),
                ),
              MuseTile(
                key: const ValueKey('settings_network'),
                leading: const Icon(Icons.lan_outlined),
                title: '网络',
                chevron: true,
                onTap: () => musePushPage(context, const MuseNetworkPage()),
              ),
              // 1.20.2：订阅页并入节点页后，分流是全局设置，放在「网络」下面
              MuseTile(
                key: const ValueKey('settings_rules'),
                leading: const Icon(Icons.rule_outlined),
                title: '分流规则',
                chevron: true,
                onTap: () => museOpenRules(context),
              ),
              // 1.8.0; 1.10.0: + 统计 / 诊断 tabs
              MuseTile(
                key: const ValueKey('settings_activity'),
                leading: const Icon(Icons.swap_vert_outlined),
                title: '活动',
                chevron: true,
                onTap: () => context.go(museActivityLocation(MuseActivityTab.connections)),
              ),
              // 1.6.0 C10; 1.9.0 #8: 内核 (Windows / Android) + 资源 on one page
              MuseTile(
                key: const ValueKey('settings_resources'),
                leading: const Icon(Icons.memory_outlined),
                title: '内核与资源',
                trailing: (PlatformUtils.isWindows || android) ? Text(MuseCoreKind.fromKey(ref.watch(MusePrefs.coreKind)).title) : null,
                chevron: true,
                onTap: () => musePushPage(context, const MuseResourcesPage()),
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
