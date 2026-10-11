// 穿云 - 设置 tab.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
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
    final perAppMode = ref.watch(Preferences.perAppProxyModeInUse);

    return MuseScaffold(
      title: '设置',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '常规',
            children: [
              const ThemeModePrefTile(),
              if (android) ...[
                MuseSwitchTile(
                  leading: const Icon(Icons.speed_rounded),
                  title: '通知栏显示网速',
                  value: ref.watch(Preferences.dynamicNotification),
                  onChanged: ref.read(Preferences.dynamicNotification.notifier).update,
                ),
                MuseSwitchTile(
                  leading: const Icon(Icons.vibration_rounded),
                  title: '触感反馈',
                  value: ref.watch(hapticServiceProvider),
                  onChanged: ref.read(hapticServiceProvider.notifier).updatePreference,
                ),
              ],
            ],
          ),
          MuseSection(
            header: '网络',
            children: [
              if (android)
                MuseTile(
                  leading: const Icon(Icons.apps_rounded),
                  title: '分应用代理',
                  subtitle: switch (perAppMode) {
                    null => '已关闭：所有 App 都经过穿云',
                    _ => perAppMode.name == 'exclude' ? '列表里的 App 不走代理' : '仅列表里的 App 走代理',
                  },
                  chevron: true,
                  onTap: () => context.goNamed('perAppProxy'),
                ),
              if (android)
                MuseTile(
                  leading: const Icon(Icons.wifi_rounded),
                  title: '按网络自动开关',
                  subtitle: ref.watch(Preferences.netAutoEnabled) ? '已开启：可信 Wi-Fi 自动断开' : '连上家里/公司 Wi-Fi 时自动断开',
                  chevron: true,
                  onTap: () => context.goNamed('networkAuto'),
                ),
              MuseSwitchTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: '节点失效自动切换',
                subtitle: '手动选的节点测速超时后，自动改用「自动最快」',
                value: ref.watch(Preferences.nodeFailover),
                onChanged: ref.read(Preferences.nodeFailover.notifier).update,
              ),
            ],
          ),
          if (android)
            MuseSection(
              header: '隐私与后台',
              footer: 'ColorOS 等系统会清理后台应用。建议允许穿云后台运行和自启动，避免连接被系统断开。',
              children: [
                MuseTile(
                  leading: const Icon(Icons.shield_moon_rounded),
                  title: '隐私',
                  subtitle: '隐藏桌面图标、不在最近任务显示、隐藏通知',
                  chevron: true,
                  onTap: () => context.goNamed('privacy'),
                ),
                MuseTile(
                  leading: Icon(
                    batteryIgnored == true ? Icons.battery_full_rounded : Icons.battery_alert_rounded,
                    color: batteryIgnored == false ? Colors.orange : null,
                  ),
                  title: '允许后台运行',
                  subtitle: batteryIgnored == true ? '已关闭电池优化' : '关闭电池优化，锁屏后也保持连接',
                  trailing: batteryIgnored == true ? const Icon(Icons.check_rounded, color: Colors.green) : null,
                  chevron: batteryIgnored != true,
                  onTap: batteryIgnored == true
                      ? ChuanyunPlatform.openAppDetails
                      : () => ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore(),
                ),
                const MuseTile(
                  leading: Icon(Icons.rocket_launch_rounded),
                  title: '自启动',
                  subtitle: 'ColorOS：在「自启动管理」里打开穿云，开机后可自动恢复连接',
                  chevron: true,
                  onTap: ChuanyunPlatform.openAutostartSettings,
                ),
              ],
            ),
          MuseSection(
            header: '更多',
            children: [
              MuseTile(
                leading: const Icon(Icons.insights_rounded),
                title: '连接信息',
                subtitle: '本次流量、出口 IP、活动连接',
                chevron: true,
                onTap: () => context.goNamed('connections'),
              ),
              MuseTile(
                leading: const Icon(Icons.description_rounded),
                title: '日志',
                subtitle: '排查连接问题',
                chevron: true,
                onTap: () => context.goNamed('logs'),
              ),
              MuseTile(
                leading: const Icon(Icons.tune_rounded),
                title: '高级',
                subtitle: 'VPN 模式与端口、TLS 分片、测速、内核、备份',
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
