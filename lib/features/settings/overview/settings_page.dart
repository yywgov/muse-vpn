// 穿云 - 设置 tab.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
//
// 1.3.0: grouped cards (icon | label | trailing control), no explanatory small text.
// 智能保持连接 replaces the separate recovery switches; 出口检测 / 隐藏非节点条目 / 自动收起不可用节点
// switches are gone (part of 首页 / always on / part of 智能保持连接); 隐私与后台 is a group here;
// 负载均衡策略 / TLS 分片 / 连接信息 sit under a collapsed 高级.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart';
import 'package:hiddify/features/muse/settings/privacy_page.dart';
import 'package:hiddify/features/muse/settings/windows_settings.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final android = PlatformUtils.isAndroid;
    final perAppOn = ref.watch(Preferences.perAppProxyModeInUse) != null;
    final adLevel = MuseAdBlockLevel.fromKey(ref.watch(Preferences.museAdBlockLevel));
    final autoHours = ref.watch(Preferences.museAutoUpdateHours);
    final themeMode = ref.watch(themePreferencesProvider);
    final shownTheme = themeMode == AppThemeMode.black ? AppThemeMode.dark : themeMode;
    final balancer = ref.watch(ConfigOptions.balancerStrategy);
    final advancedOpen = useState(false);

    return MuseScaffold(
      large: true,
      title: '设置',
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
                onTap: () async {
                  final picked = await museSettingPick<AppThemeMode>(
                    context,
                    '外观',
                    [for (final m in AppThemeMode.choices) (m, m.present(t))],
                    shownTheme,
                  );
                  if (picked != null) await ref.read(themePreferencesProvider.notifier).changeThemeMode(picked);
                },
              ),
              // 1.3.0: one switch for reconnect → switch node → restart core (logic/keep_alive.dart)
              MuseSwitchTile(
                key: const ValueKey('keep_alive'),
                leading: const Icon(Icons.autorenew_rounded),
                title: '智能保持连接',
                value: ref.watch(Preferences.museKeepAlive),
                onChanged: (v) => ref.read(Preferences.museKeepAlive.notifier).update(v),
              ),
              MuseTile(
                key: const ValueKey('ad_block_level'),
                leading: const Icon(Icons.block_rounded),
                title: '去广告',
                trailing: Text(adLevel.title),
                chevron: true,
                onTap: () async {
                  final picked = await museSettingPick<MuseAdBlockLevel>(
                    context,
                    '去广告',
                    [for (final l in MuseAdBlockLevel.values) (l, l.title)],
                    adLevel,
                  );
                  if (picked != null) await ref.read(Preferences.museAdBlockLevel.notifier).update(picked.key);
                },
              ),
              MuseTile(
                key: const ValueKey('auto_update_hours'),
                leading: const Icon(Icons.update_rounded),
                title: '订阅自动更新',
                trailing: Text(museAutoUpdateLabel(autoHours)),
                chevron: true,
                onTap: () async {
                  final picked = await museSettingPick<int>(
                    context,
                    '订阅自动更新',
                    [for (final h in museAutoUpdateChoices) (h, museAutoUpdateLabel(h))],
                    autoHours,
                  );
                  if (picked != null) await ref.read(Preferences.museAutoUpdateHours.notifier).update(picked);
                },
              ),
              if (android)
                MuseTile(
                  leading: const Icon(Icons.apps_rounded),
                  title: '分应用代理',
                  trailing: perAppOn ? const MuseStatusDot() : null,
                  chevron: true,
                  onTap: () => context.goNamed('perAppProxy'),
                ),
            ],
          ),
          if (PlatformUtils.isWindows) const WindowsSettingsSection(),
          if (android) const MusePrivacySection(),
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('diagnose'),
                leading: const Icon(Icons.health_and_safety_outlined),
                title: '诊断',
                chevron: true,
                onTap: () => showMuseDiagnoseSheet(context),
              ),
              MuseTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: '关于',
                chevron: true,
                onTap: () => context.goNamed('about'),
              ),
              MuseTile(
                key: const ValueKey('advanced_toggle'),
                leading: const Icon(Icons.tune_rounded),
                title: '高级',
                trailing: AnimatedRotation(
                  turns: advancedOpen.value ? 0.5 : 0,
                  duration: MuseMotion.fast,
                  child: Icon(Icons.expand_more_rounded, size: MuseIconSize.small, color: MuseTheme.of(context).text3),
                ),
                onTap: () => advancedOpen.value = !advancedOpen.value,
              ),
              if (advancedOpen.value) ...[
                MuseTile(
                  key: const ValueKey('balancer_strategy'),
                  leading: const Icon(Icons.balance_rounded),
                  title: '负载均衡策略',
                  trailing: Text(balancer.present(t)),
                  chevron: true,
                  onTap: () async {
                    final picked = await museSettingPick<BalancerStrategy>(
                      context,
                      '负载均衡策略',
                      [for (final b in BalancerStrategy.values) (b, b.present(t))],
                      balancer,
                    );
                    if (picked != null) await ref.read(ConfigOptions.balancerStrategy.notifier).update(picked);
                  },
                ),
                MuseTile(
                  leading: const Icon(Icons.call_split_rounded),
                  title: 'TLS 分片',
                  chevron: true,
                  onTap: () => context.goNamed('tlsTricks'),
                ),
                MuseTile(
                  leading: const Icon(Icons.insights_rounded),
                  title: '连接信息',
                  chevron: true,
                  onTap: () => context.goNamed('connections'),
                ),
              ],
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
                  ? const Icon(Icons.check_rounded, color: MusePalette.brand, size: MuseIconSize.small)
                  : null,
              onTap: () => Navigator.of(c).pop(value),
            ),
        ],
      ),
    );

/// A green dot at the end of a row whose feature is on.
class MuseStatusDot extends StatelessWidget {
  const MuseStatusDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    margin: const EdgeInsets.only(right: MuseSpace.s8),
    decoration: const BoxDecoration(color: MusePalette.green, shape: BoxShape.circle),
  );
}
