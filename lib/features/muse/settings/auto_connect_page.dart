// 穿云 1.9.0 #5 - 设置 › 自动连接: everything that connects or disconnects without a tap, on one page:
// 自动运行 (Android), 按需运行, 每天定时连接 / 断开, 开机自启 and 开机自启时静默 (Windows).
// The rows moved here from 设置 › 通用 / 电脑 / 网络; preferences and behaviour are unchanged.
// 1.10.0: 智能保持连接 (from the 设置 home page) and Windows 静默启动 are here too.
// 1.11.0: only 打开即连接 (Android) and 开机自启 (+ 开机自启时静默, Windows) are shown; 智能保持连接,
// 按需运行, 每天定时连接 / 断开 and Windows 静默启动 fold into 「更多」 on the same page. Same preferences.
// 1.20.3：改名「启动与断线」，取消「更多」折叠，分 启动 / 断线处理 / Wi‑Fi 规则 / 定时 四组；节点失效自动切换从节点设置搬来，
// 按需运行与按 Wi‑Fi 切换模式合成一页「Wi‑Fi 规则」。键与行为不变。
// 1.20.5：取消「打开即连接」（Android「启动」组只剩这一项，整组去掉；自动化广播说明移到「定时」组页脚）。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/settings/wifi_mode_page.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/wifi_actions.dart';
import 'package:hiddify/features/muse/settings/android_settings.dart' show museAndroidAutomationNote;
import 'package:hiddify/features/muse/settings/more_settings.dart' show musePushPage, museAutoFailoverTitle;
import 'package:hiddify/features/muse/settings/windows_settings.dart' show MuseWindowsSilentStartTile;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One-line summary for the 设置 row: which automatic ways are on.
String museAutoConnectSummary({required bool onDemand, required MuseSchedule schedule, required bool autoStart}) {
  final on = [if (onDemand) '按需', if (schedule.connectAt >= 0 || schedule.disconnectAt >= 0) '定时', if (autoStart) '开机自启'];
  return on.isEmpty ? '关' : on.join('、');
}

/// 1.20.3：设置一级与页标题（原「自动连接」）。1.22.0 F2：「启动与断线」→「自动化」（旧名留在搜索关键词里）。
const museStartupTitle = '自动化';

/// 1.11.0–1.20.2 的「更多」里的行；1.20.3 起「更多」取消，各行直接分组显示（保留给旧调用方）。
const museAutoConnectMoreRows = ['智能保持连接', '按需运行', '每天定时连接', '每天定时断开', '静默启动'];

/// 1.20.3：「Wi‑Fi 规则」一行的摘要（第 2 轮：每个 Wi‑Fi 一个动作，同一个 Wi‑Fi 不重复计数）。
String museWifiRulesSummary({required bool onDemand, required int pauseCount, required int modeCount}) {
  final parts = [if (onDemand && pauseCount > 0) '暂停 $pauseCount 个', if (modeCount > 0) '切换模式 $modeCount 个'];
  return parts.isEmpty ? '关' : parts.join('，');
}

/// 1.9.0 #5；1.20.3：「启动与断线」—— 启动 / 断线处理 / Wi‑Fi 规则 / 定时 四组，不再折叠「更多」。
class MuseAutoConnectPage extends HookConsumerWidget {
  const MuseAutoConnectPage({super.key, this.android, this.windows, this.initiallyMore = false});

  /// 1.11.0 的「更多」已取消；保留参数，旧调用方不用改
  final bool initiallyMore;

  /// Platform overrides for tests; null = the running platform.
  final bool? android;
  final bool? windows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAndroid = android ?? PlatformUtils.isAndroid;
    final isWindows = windows ?? PlatformUtils.isWindows;
    final schedule = MuseSchedule.parse(ref.watch(MusePrefs.schedule));
    final onDemand = ref.watch(MusePrefs.onDemand);
    final wifiSummary = museWifiActionsSummary(
      museWifiActions(rulesRaw: ref.watch(MusePrefs.wifiRules), modesRaw: ref.watch(MusePrefs.wifiModes), onDemandOn: onDemand),
      onDemandOn: onDemand,
    );

    Future<void> pickTime(bool connect) async {
      final cur = connect ? schedule.connectAt : schedule.disconnectAt;
      final picked = await showTimePicker(
        context: context,
        initialTime: cur < 0 ? TimeOfDay(hour: connect ? 8 : 23, minute: 0) : TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
        helpText: connect ? '每天定时连接' : '每天定时断开',
        cancelText: '关闭',
      );
      final m = picked == null ? -1 : picked.hour * 60 + picked.minute;
      final next = connect ? MuseSchedule(connectAt: m, disconnectAt: schedule.disconnectAt) : MuseSchedule(connectAt: schedule.connectAt, disconnectAt: m);
      await ref.read(MusePrefs.schedule.notifier).update(next.toRaw());
    }

    return MuseScaffold(
      title: museStartupTitle,
      body: MuseGroupedBody(
        children: [
          if (isWindows) const _WindowsStartSection(),
          // 1.20.3：智能保持连接与节点失效自动切换放在一起（原来一个在这里、一个在节点设置）
          MuseSection(
            header: '断线处理',
            children: [
              MuseSwitchTile(
                key: const ValueKey('keep_alive'),
                leading: const Icon(Icons.autorenew_outlined),
                title: '智能保持连接',
                subtitle: '断线后自动重连，必要时重启内核',
                value: ref.watch(Preferences.museKeepAlive),
                onChanged: (v) => ref.read(Preferences.museKeepAlive.notifier).update(v),
              ),
              MuseSwitchTile(
                key: const ValueKey('node_auto_failover'),
                leading: const Icon(Icons.swap_horiz_outlined),
                title: museAutoFailoverTitle,
                subtitle: '当前节点连续两次测速失败时换到同地区最快的节点，恢复后换回',
                value: ref.watch(MusePrefs.autoFailover),
                onChanged: (v) => ref.read(MusePrefs.autoFailover.notifier).update(v),
              ),
            ],
          ),
          // 1.20.3：按需运行与按 Wi‑Fi 切换模式在同一页「Wi‑Fi 规则」
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('settings_wifi_rules'),
                leading: const Icon(Icons.wifi_outlined),
                title: museWifiRulesTitle,
                trailing: Text(wifiSummary),
                chevron: true,
                onTap: () => musePushPage(context, const MuseWifiRulesPage()),
              ),
            ],
          ),
          MuseSection(
            header: '定时',
            footer: isAndroid
                ? '穿云需在运行（可在后台）；时间到时只执行一次，手动操作随时优先。$museAndroidAutomationNote'
                : '穿云需在运行（可在后台）；时间到时只执行一次，手动操作随时优先',
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
        ],
      ),
    );
  }
}

/// 开机自启 + 开机自启时静默 + 静默启动 (Windows only; the auto-start notifier is never built elsewhere).
/// 1.20.3：静默启动回到这一组；它开着时每次启动都不弹窗口，「开机自启时静默」置灰并说明。
class _WindowsStartSection extends ConsumerWidget {
  const _WindowsStartSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoStart = ref.watch(autoStartNotifierProvider).valueOrNull ?? false;
    final silent = ref.watch(Preferences.silentStart);
    return MuseSection(
      header: '启动',
      children: [
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
            subtitle: museAutostartSilentSubtitle(silentStart: silent),
            value: silent || ref.watch(MusePrefs.autostartSilent),
            onChanged: silent ? null : (v) => ref.read(MusePrefs.autostartSilent.notifier).update(v),
          ),
        const MuseWindowsSilentStartTile(),
      ],
    );
  }
}

/// 1.20.3：「开机自启时静默」的副标题；静默启动开着时它不起作用。
String museAutostartSilentSubtitle({required bool silentStart}) => silentStart ? '已开「静默启动」，每次启动都不弹窗口，这项不起作用' : '开机自动启动时只在托盘运行；自己打开时照常显示窗口';
