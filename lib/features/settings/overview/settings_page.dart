// 穿云 - 设置 tab.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
//
// 1.1: no explanatory small text; state is shown with icons (a green dot when a feature is on,
// an orange warning icon on 后台运行 / 自启动 only while they still need doing).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart';
import 'package:hiddify/features/muse/settings/windows_settings.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final android = PlatformUtils.isAndroid;
    final batteryIgnored = android ? ref.watch(batteryOptimizationNotifierProvider).valueOrNull : null;
    final autostartVisited = ref.watch(Preferences.autostartVisited);
    final perAppOn = ref.watch(Preferences.perAppProxyModeInUse) != null;
    final needsBattery = android && batteryIgnored == false;
    final needsAutostart = android && !autostartVisited;
    final adLevel = MuseAdBlockLevel.fromKey(ref.watch(Preferences.museAdBlockLevel));
    final autoHours = ref.watch(Preferences.museAutoUpdateHours);

    return MuseScaffold(
      title: '设置',
      body: MuseGroupedBody(
        children: [
          const MuseSection(header: '常规', children: [ThemeModePrefTile()]),
          // 穿云 1.2.2: both platforms
          MuseSection(
            header: '节点',
            children: [
              MuseSwitchTile(
                leading: const Icon(Icons.visibility_off_rounded),
                title: '自动收起不可用节点',
                subtitle: '测速超时的节点收进「不可用」，恢复后自动放回',
                value: ref.watch(Preferences.hideBadNodes),
                onChanged: (v) => ref.read(Preferences.hideBadNodes.notifier).update(v),
              ),
              // 1.2.3
              MuseSwitchTile(
                leading: const Icon(Icons.travel_explore_rounded),
                title: '出口检测',
                subtitle: '首页显示出口 IP 和地区，以及 Google、ChatGPT、Netflix 能否使用',
                value: ref.watch(Preferences.museExitCheck),
                onChanged: (v) => ref.read(Preferences.museExitCheck.notifier).update(v),
              ),
              // 1.2.8
              MuseSwitchTile(
                key: const ValueKey('hide_info_nodes'),
                leading: const Icon(Icons.filter_alt_rounded),
                title: '隐藏非节点条目',
                subtitle: '自动隐藏「剩余流量」「到期」「官网」「套餐」等订阅信息',
                value: ref.watch(Preferences.museHideInfoNodes),
                onChanged: (v) => ref.read(Preferences.museHideInfoNodes.notifier).update(v),
              ),
            ],
          ),
          // 1.2.8: 去广告强度 / 订阅自动更新
          MuseSection(
            header: '规则与订阅',
            children: [
              MuseTile(
                key: const ValueKey('ad_block_level'),
                leading: const Icon(Icons.block_rounded),
                title: '去广告',
                trailing: Text(adLevel.title),
                chevron: true,
                onTap: () async {
                  final picked = await _pick<MuseAdBlockLevel>(
                    context,
                    '去广告',
                    [for (final l in MuseAdBlockLevel.values) (l, l.title, l.explain)],
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
                  final picked = await _pick<int>(
                    context,
                    '订阅自动更新',
                    [for (final h in museAutoUpdateChoices) (h, museAutoUpdateLabel(h), null)],
                    autoHours,
                  );
                  if (picked != null) await ref.read(Preferences.museAutoUpdateHours.notifier).update(picked);
                },
              ),
            ],
          ),
          if (PlatformUtils.isWindows) const WindowsSettingsSection(),
          if (android)
            MuseSection(
              header: '网络',
              children: [
                MuseTile(
                  leading: const Icon(Icons.apps_rounded),
                  title: '分应用代理',
                  trailing: MuseStatusTrailing(on: perAppOn),
                  onTap: () => context.goNamed('perAppProxy'),
                ),
              ],
            ),
          if (android)
            MuseSection(
              header: '隐私与后台',
              children: [
                MuseTile(
                  leading: const Icon(Icons.shield_moon_rounded),
                  title: '隐私',
                  chevron: true,
                  onTap: () => context.goNamed('privacy'),
                ),
                if (needsBattery)
                  MuseTile(
                    leading: const Icon(Icons.battery_alert_rounded, color: Colors.orange),
                    title: '允许后台运行',
                    trailing: const MuseStatusTrailing(warning: true),
                    onTap: () => ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore(),
                  ),
                if (needsAutostart)
                  MuseTile(
                    leading: const Icon(Icons.rocket_launch_rounded, color: Colors.orange),
                    title: '自启动',
                    trailing: const MuseStatusTrailing(warning: true),
                    onTap: () async {
                      await ChuanyunPlatform.openAutostartSettings();
                      await ref.read(Preferences.autostartVisited.notifier).update(true);
                    },
                  ),
              ],
            ),
          MuseSection(
            header: '更多',
            children: [
              MuseTile(
                key: const ValueKey('diagnose'),
                leading: const Icon(Icons.health_and_safety_rounded),
                title: '一键诊断',
                chevron: true,
                onTap: () => showMuseDiagnoseSheet(context),
              ),
              MuseTile(
                leading: const Icon(Icons.insights_rounded),
                title: '连接信息',
                chevron: true,
                onTap: () => context.goNamed('connections'),
              ),
              // 1.2.2: was 高级 › TLS 分片 / 技巧 (a page with one row)
              MuseTile(
                leading: const Icon(Icons.tune_rounded),
                title: 'TLS 分片',
                chevron: true,
                onTap: () => context.goNamed('tlsTricks'),
              ),
              MuseTile(
                leading: const Icon(Icons.info_rounded),
                title: '关于',
                chevron: true,
                onTap: () => context.goNamed('about'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A one-of-N choice as a simple dialog; null when dismissed.
Future<T?> _pick<T>(BuildContext context, String title, List<(T, String, String?)> options, T current) =>
    showDialog<T>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (value, label, explain) in options)
            ListTile(
              key: ValueKey('pick_$label'),
              leading: Icon(value == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
              title: Text(label),
              subtitle: explain == null ? null : Text(explain),
              onTap: () => Navigator.of(c).pop(value),
            ),
        ],
      ),
    );

/// Status at the end of a settings row: a green dot when on, an orange warning icon when
/// something still needs doing, then the chevron.
class MuseStatusTrailing extends StatelessWidget {
  const MuseStatusTrailing({super.key, this.on = false, this.warning = false});

  final bool on;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (warning)
          const Icon(Icons.error_rounded, color: Colors.orange, size: 20)
        else if (on)
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle),
          ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, color: MuseColors.secondaryText(context)),
      ],
    );
  }
}
