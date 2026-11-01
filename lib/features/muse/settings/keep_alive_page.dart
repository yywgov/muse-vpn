// 穿云 1.9.0 #6 - 设置 › 后台保活 (Android): the one place for 允许后台运行, 自启动 and 不在最近任务显示,
// plus the per-brand steps. The first-connect guide and the 「被系统关闭」 dialog use the same actions
// (museAllowBackground / museOpenAutostart), so 自启动 is opened and remembered the same way everywhere.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/background_guard.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 允许后台运行: ask the system to ignore battery optimisation for 穿云.
Future<void> museAllowBackground(WidgetRef ref) => ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore();

/// 自启动: open the brand's auto-start settings and remember that it was visited.
Future<void> museOpenAutostart(WidgetRef ref) async {
  await ChuanyunPlatform.openAutostartSettings();
  await ref.read(Preferences.autostartVisited.notifier).update(true);
}

/// Whether 设置 should flag 后台保活 (something is still missing).
bool museKeepAliveNeedsAttention({required bool? batteryIgnored, required bool autostartVisited}) =>
    batteryIgnored == false || !autostartVisited;

class MuseKeepAlivePage extends ConsumerWidget {
  const MuseKeepAlivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ignored = ref.watch(batteryOptimizationNotifierProvider).valueOrNull;
    final autostartVisited = ref.watch(Preferences.autostartVisited);
    final excludeRecents = ref.watch(Preferences.excludeFromRecents);
    final killCount = ref.watch(MusePrefs.killCount);
    Widget state(bool done, String todo) => done
        ? const Text('已设置')
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outlined, color: MusePalette.orange, size: MuseIconSize.small),
              const SizedBox(width: MuseSpace.s4),
              Text(todo),
            ],
          );
    return MuseScaffold(
      title: '后台保活',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '系统清理后台会让连接断开。开启下面两项后，穿云在后台更不容易被关闭。',
            children: [
              MuseTile(
                key: const ValueKey('keep_alive_battery'),
                leading: const Icon(Icons.battery_charging_full_outlined),
                title: '允许后台运行',
                trailing: state(ignored ?? false, '去开启'),
                chevron: ignored != true,
                onTap: ignored == true ? null : () => museAllowBackground(ref),
              ),
              MuseTile(
                key: const ValueKey('keep_alive_autostart'),
                leading: const Icon(Icons.rocket_launch_outlined),
                title: '自启动',
                trailing: state(autostartVisited, '去设置'),
                chevron: true,
                onTap: () => museOpenAutostart(ref),
              ),
              MuseSwitchTile(
                key: const ValueKey('keep_alive_recents'),
                leading: const Icon(Icons.layers_clear_outlined),
                title: '不在最近任务显示',
                value: excludeRecents,
                onChanged: (value) async {
                  await ref.read(Preferences.excludeFromRecents.notifier).update(value);
                  await ChuanyunPlatform.setExcludeFromRecents(value);
                },
              ),
            ],
          ),
          MuseSection(
            children: [
              // 1.4.1: per-brand steps (also shown after the system killed 穿云 in the background)
              MuseTile(
                key: const ValueKey('settings_background_guide'),
                leading: const Icon(Icons.shield_moon_outlined),
                title: '本机设置步骤',
                trailing: killCount > 0 ? Text('被关闭 $killCount 次') : null,
                chevron: true,
                onTap: () => showMuseBackgroundGuide(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
