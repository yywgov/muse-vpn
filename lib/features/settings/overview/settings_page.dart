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
// 1.22.0 F2：一级 6 组（连接与网络、订阅与节点、外观、自动化、诊断、关于），每行副标题是当前状态；搜索框常驻顶部。
// Old names still find their new place through search (logic/settings_index.dart); every
// preference keeps its storage key.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/muse/activity/activity_page.dart';
import 'package:hiddify/features/muse/config/rules_page.dart';
import 'package:hiddify/features/muse/nodes/subs_sheet.dart' show museOpenSubscriptions;
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/logic/terms.dart';
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
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/muse/home/home_data.dart' show museActiveProfileNameProvider;
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 1.10.0: the rows of the 设置 home page, in order (pure, for tests). 1.20.3：按审查清单的一级结构。
/// 1.22.0 F2：一级收成 6 组——连接与网络、订阅与节点、外观、自动化、诊断、关于。分流规则和活动搬到底栏「流量」，
/// 网络 / 内核与资源 / 隐私与通知 在「连接与网络」里，备份与恢复 / 开发者选项（打开后）在「关于」里。旧名字都还能搜到。
/// [android] / [developer] 不再改变一级行，参数留给旧调用方。
List<String> museSettingsHomeRows({required bool android, required bool developer}) => const [
  museNetGroupTitle,
  museSubsGroupTitle,
  '外观',
  museStartupTitle,
  '诊断',
  '关于',
];

/// 1.22.0 F2：一级分组名。
const museNetGroupTitle = '连接与网络';
const museSubsGroupTitle = '订阅与节点';

/// 1.22.0：「关于」组里打开关于页的那一行。
const museAboutRowTitle = '关于穿云';

/// 1.22.0 F2：「订阅与节点」一行的状态（当前订阅；数量在二级页「订阅列表」一行）。
String museSubsGroupSummary(String? active) {
  final name = active?.trim() ?? '';
  return name.isEmpty ? '还没有订阅' : '当前订阅：$name';
}

/// 1.22.0 F2：「连接与网络」一行的状态（内核 · 接管方式）；什么都不用显示时写这组有什么。
String museNetGroupSummary({String? core, String? takeover}) {
  final parts = [?core, ?takeover];
  return parts.isEmpty ? '网络、内核与资源、隐私与通知' : parts.join(' · ');
}

/// 1.22.0 F2：「自动化」一行的状态。
String museAutomationSummary(String auto) => auto == '关' ? '自动连接：关' : auto;

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final android = PlatformUtils.isAndroid;
    final windows = PlatformUtils.isWindows;
    // 1.20.3: 外观一行显示当前配色（原来显示深浅色，选了终端绿等主题时会对不上）
    final colors = ref.watch(museColorChoiceProvider);
    // 1.9.0 #5
    final autoSummary = museAutoConnectSummary(
      onDemand: ref.watch(MusePrefs.onDemand) && museOnDemandSsids(ref.watch(MusePrefs.wifiRules)).isNotEmpty,
      schedule: MuseSchedule.parse(ref.watch(MusePrefs.schedule)),
      autoStart: windows && (ref.watch(autoStartNotifierProvider).valueOrNull ?? false),
    );
    final netSummary = museNetGroupSummary(
      core: (windows || android) ? MuseCoreKind.fromKey(ref.watch(MusePrefs.coreKind)).title : null,
      takeover: windows ? museTakeoverTitle(ref.watch(ConfigOptions.serviceMode)) : null,
    );
    final subsSummary = museSubsGroupSummary(ref.watch(museActiveProfileNameProvider));
    final version = ref.watch(appInfoProvider).valueOrNull?.version;

    // 1.5.0 #101: jump to a setting found by search (1.10.0 / 1.20.3 / 1.22.0: at its new place)
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
        case MuseSettingPage.netGroup:
          musePushPage(context, const MuseNetGroupPage());
        case MuseSettingPage.subsGroup:
          musePushPage(context, const MuseSubsGroupPage());
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

    Future<void> search() async {
      final picked = await showMuseSettingsSearch(context, developer: ref.read(MusePrefs.devMode));
      if (picked != null && context.mounted) openEntry(picked);
    }

    return MuseScaffold(
      large: true,
      title: '设置',
      body: MuseGroupedBody(
        children: [
          // 1.22.0 F2：搜索框常驻列表顶部（原来是右上角的放大镜）；点一下打开搜索，搜到的条目跳到它所在的页面
          Padding(
            padding: EdgeInsets.fromLTRB(MuseSpace.page(context), MuseSpace.s4, MuseSpace.page(context), MuseSpace.s8),
            child: MuseSettingsSearchBar(key: const ValueKey('settings_search'), onTap: search),
          ),
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('settings_group_net'),
                leading: const Icon(Icons.lan_outlined),
                title: museNetGroupTitle,
                subtitle: netSummary,
                subtitleMaxLines: 1,
                chevron: true,
                onTap: () => musePushPage(context, const MuseNetGroupPage()),
              ),
              MuseTile(
                key: const ValueKey('settings_group_subs'),
                leading: const Icon(Icons.layers_outlined),
                title: museSubsGroupTitle,
                subtitle: subsSummary,
                subtitleMaxLines: 1,
                chevron: true,
                onTap: () => musePushPage(context, const MuseSubsGroupPage()),
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('theme_mode'),
                leading: const Icon(Icons.palette_outlined),
                title: '外观',
                subtitle: colors.title,
                subtitleMaxLines: 1,
                chevron: true,
                onTap: () => musePushPage(context, const MuseAppearancePage()),
              ),
              // 1.9.0 #5 自动连接；1.20.3「启动与断线」；1.22.0 F2：「自动化」（开机自启、断线处理、Wi‑Fi 规则、定时）
              MuseTile(
                key: const ValueKey('settings_auto_connect'),
                leading: const Icon(Icons.schedule_outlined),
                title: museStartupTitle,
                subtitle: museAutomationSummary(autoSummary),
                subtitleMaxLines: 1,
                chevron: true,
                onTap: () => musePushPage(context, const MuseAutoConnectPage()),
              ),
            ],
          ),
          MuseSection(
            children: [
              // 1.20.3：唯一的诊断入口
              MuseTile(
                key: const ValueKey('settings_diagnose'),
                leading: const Icon(Icons.medical_services_outlined),
                title: '诊断',
                subtitle: ref.watch(MusePrefs.logCapture) ? '日志记录：开' : '日志记录：关',
                subtitleMaxLines: 1,
                chevron: true,
                onTap: () => context.go(museDiagnosePath),
              ),
              MuseTile(
                key: const ValueKey('settings_group_about'),
                leading: const Icon(Icons.info_outlined),
                title: '关于',
                subtitle: version == null ? '版本、备份与恢复' : '版本 $version',
                subtitleMaxLines: 1,
                chevron: true,
                onTap: () => musePushPage(context, const MuseAboutGroupPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 1.22.0 F2：设置顶部常驻的搜索框（只是入口，点了打开搜索面板，输入框在面板里）。
class MuseSettingsSearchBar extends StatelessWidget {
  const MuseSettingsSearchBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    return Semantics(
      button: true,
      label: '搜索设置',
      excludeSemantics: true,
      child: Material(
        color: mt.inner,
        shape: MuseShape.full,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: MuseSize.button),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12),
              child: Row(
                children: [
                  Icon(Icons.search_outlined, size: MuseIconSize.small, color: mt.text2),
                  const SizedBox(width: MuseSpace.s8),
                  Expanded(
                    child: Text(
                      '搜索设置，如 DNS、去广告、备份',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MuseType.body(context).copyWith(color: mt.text2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.22.0 F2：「连接与网络」——网络、内核与资源、隐私与通知。
class MuseNetGroupPage extends ConsumerWidget {
  const MuseNetGroupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final android = PlatformUtils.isAndroid;
    final windows = PlatformUtils.isWindows;
    return MuseScaffold(
      key: const ValueKey('settings_group_net_page'),
      title: museNetGroupTitle,
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('settings_network'),
                leading: const Icon(Icons.lan_outlined),
                title: '网络',
                subtitle: windows ? '接管方式：${museTakeoverTitle(ref.watch(ConfigOptions.serviceMode))}' : 'DNS、TLS 分片、IPv6',
                subtitleMaxLines: 1,
                chevron: true,
                onTap: () => musePushPage(context, const MuseNetworkPage()),
              ),
              // 1.6.0 C10; 1.9.0 #8: 内核 (Windows / Android) + 资源 on one page
              MuseTile(
                key: const ValueKey('settings_resources'),
                leading: const Icon(Icons.memory_outlined),
                title: '内核与资源',
                trailing: (windows || android) ? Text(MuseCoreKind.fromKey(ref.watch(MusePrefs.coreKind)).title) : null,
                chevron: true,
                onTap: () => musePushPage(context, const MuseResourcesPage()),
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
        ],
      ),
    );
  }
}

/// 1.22.0 F2：「订阅与节点」——订阅列表、订阅设置、节点设置、订阅修改（这些在节点页也都能打开）。
class MuseSubsGroupPage extends ConsumerWidget {
  const MuseSubsGroupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
    return MuseScaffold(
      key: const ValueKey('settings_group_subs_page'),
      title: museSubsGroupTitle,
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('settings_subs_list'),
                leading: const Icon(Icons.layers_outlined),
                title: '订阅列表',
                trailing: Text(profiles.isEmpty ? '无' : '${profiles.length} 个'),
                chevron: true,
                onTap: () => museOpenSubscriptions(context, ref),
              ),
              MuseTile(
                key: const ValueKey('settings_sub_settings'),
                leading: const Icon(Icons.update_outlined),
                title: '订阅设置',
                chevron: true,
                onTap: () => musePushPage(context, const MuseSubSettingsPage()),
              ),
              MuseTile(
                key: const ValueKey('settings_node_settings'),
                leading: const Icon(Icons.language_outlined),
                title: '节点设置',
                chevron: true,
                onTap: () => musePushPage(context, const MuseNodeSettingsPage()),
              ),
              MuseTile(
                key: const ValueKey('settings_overrides'),
                leading: const Icon(Icons.edit_note_outlined),
                title: museOverrideTitle,
                chevron: true,
                onTap: () => museOpenRules(context, tab: MuseRulesTab.overrides),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 1.22.0 F2：「关于」——关于穿云（版本、检查更新、开源许可）、备份与恢复、开发者选项（打开后）。
class MuseAboutGroupPage extends ConsumerWidget {
  const MuseAboutGroupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devMode = ref.watch(MusePrefs.devMode);
    return MuseScaffold(
      key: const ValueKey('settings_group_about_page'),
      title: '关于',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('settings_about'),
                leading: const Icon(Icons.info_outlined),
                title: museAboutRowTitle,
                chevron: true,
                onTap: () => context.goNamed('about'),
              ),
              // 1.20.3：导出 / 导入配置（原在关于页底部）
              MuseTile(
                key: const ValueKey('settings_backup'),
                leading: const Icon(Icons.settings_backup_restore_outlined),
                title: '备份与恢复',
                chevron: true,
                onTap: () => musePushPage(context, const MuseBackupPage()),
              ),
              // 1.6.0 C10 (#127): only after 关于's icon was tapped 7 times
              if (devMode)
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
