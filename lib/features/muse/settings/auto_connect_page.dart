// 穿云 1.9.0 #5 - 设置 › 自动连接: everything that connects or disconnects without a tap, on one page:
// 自动运行 (Android), 按需运行, 每天定时连接 / 断开, 开机自启 and 开机自启时静默 (Windows).
// The rows moved here from 设置 › 通用 / 电脑 / 网络; preferences and behaviour are unchanged.
// 1.10.0: 智能保持连接 (from the 设置 home page) and Windows 静默启动 are here too.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/settings/android_settings.dart' show museAndroidAutomationNote;
import 'package:hiddify/features/muse/settings/more_settings.dart' show musePushPage;
import 'package:hiddify/features/muse/settings/windows_settings.dart' show MuseWindowsSilentStartTile;
import 'package:hiddify/features/muse/settings/windows_extras.dart' show MuseOnDemandPage;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One-line summary for the 设置 row: which automatic ways are on.
String museAutoConnectSummary({required bool autoRun, required bool onDemand, required MuseSchedule schedule, required bool autoStart}) {
  final on = [
    if (autoRun) '自动运行',
    if (onDemand) '按需',
    if (schedule.connectAt >= 0 || schedule.disconnectAt >= 0) '定时',
    if (autoStart) '开机自启',
  ];
  return on.isEmpty ? '关' : on.join('、');
}

class MuseAutoConnectPage extends ConsumerWidget {
  const MuseAutoConnectPage({super.key, this.android, this.windows});

  /// Platform overrides for tests; null = the running platform.
  final bool? android;
  final bool? windows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAndroid = android ?? PlatformUtils.isAndroid;
    final isWindows = windows ?? PlatformUtils.isWindows;
    final onDemandOn = ref.watch(MusePrefs.onDemand) && museOnDemandSsids(ref.watch(MusePrefs.wifiRules)).isNotEmpty;
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
      title: '自动连接',
      body: MuseGroupedBody(
        children: [
          // 1.10.0: 智能保持连接 moved here (1.3.0: one switch for reconnect → switch node → restart core)
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('keep_alive'),
                leading: const Icon(Icons.autorenew_outlined),
                title: '智能保持连接',
                info: '断线后自动重连；当前节点失效时自动换到可用节点，必要时重启内核',
                value: ref.watch(Preferences.museKeepAlive),
                onChanged: (v) => ref.read(Preferences.museKeepAlive.notifier).update(v),
              ),
            ],
          ),
          MuseSection(
            footer: isAndroid ? museAndroidAutomationNote : null,
            children: [
              if (isAndroid)
                MuseSwitchTile(
                  key: const ValueKey('settings_auto_run'),
                  leading: const Icon(Icons.play_circle_outlined),
                  title: '自动运行',
                  subtitle: '打开穿云时自动连接',
                  value: ref.watch(MusePrefs.autoRun),
                  onChanged: (v) => ref.read(MusePrefs.autoRun.notifier).update(v),
                ),
              MuseTile(
                key: const ValueKey('settings_on_demand'),
                leading: const Icon(Icons.wifi_outlined),
                title: '按需运行',
                trailing: Text(onDemandOn ? '开' : '关'),
                chevron: true,
                onTap: () => musePushPage(context, const MuseOnDemandPage()),
              ),
            ],
          ),
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
          if (isWindows) const _WindowsStartSection(),
        ],
      ),
    );
  }
}

/// 静默启动 + 开机自启 + 开机自启时静默 (Windows only; the auto-start notifier is never built elsewhere).
class _WindowsStartSection extends ConsumerWidget {
  const _WindowsStartSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoStart = ref.watch(autoStartNotifierProvider).valueOrNull ?? false;
    return MuseSection(
      header: '启动',
      children: [
        const MuseWindowsSilentStartTile(),
        MuseSwitchTile(
          key: const ValueKey('settings_autostart'),
          leading: const Icon(Icons.power_settings_new_outlined),
          title: '开机自启',
          value: autoStart,
          onChanged: (value) async {
            final notifier = ref.read(autoStartNotifierProvider.notifier);
            value ? await notifier.enable() : await notifier.disable();
          },
        ),
        // 1.6.0 C8: a start by 开机自启 (--autostart) can stay in the tray on its own
        if (autoStart)
          MuseSwitchTile(
            key: const ValueKey('settings_autostart_silent'),
            leading: const Icon(Icons.nights_stay_outlined),
            title: '开机自启时静默',
            info: '电脑开机自动启动穿云时只在托盘里运行，不弹出窗口；自己打开穿云时照常显示窗口',
            value: ref.watch(MusePrefs.autostartSilent),
            onChanged: (v) => ref.read(MusePrefs.autostartSilent.notifier).update(v),
          ),
      ],
    );
  }
}
