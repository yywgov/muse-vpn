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
import 'package:hiddify/features/muse/settings/windows_settings.dart';
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

    return MuseScaffold(
      title: '设置',
      body: MuseGroupedBody(
        children: [
          const MuseSection(header: '常规', children: [ThemeModePrefTile()]),
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
                leading: const Icon(Icons.insights_rounded),
                title: '连接信息',
                chevron: true,
                onTap: () => context.goNamed('connections'),
              ),
              MuseTile(
                leading: const Icon(Icons.tune_rounded),
                title: '高级',
                chevron: true,
                onTap: () => context.goNamed('advanced'),
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
