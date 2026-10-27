// 穿云 1.6.0 C9 - 设置 › 通用 (Android): 自动运行 (opening 穿云 connects, once per launch),
// 按需运行 › (pause on listed Wi‑Fi; same page and logic as Windows), 通知栏「断开」按钮.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show musePushPage;
import 'package:hiddify/features/muse/settings/windows_extras.dart' show MuseOnDemandPage;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseAndroidGeneralSection extends ConsumerWidget {
  const MuseAndroidGeneralSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoRun = ref.watch(MusePrefs.autoRun);
    final stopButton = ref.watch(MusePrefs.notifyStopButton);
    final onDemandOn = ref.watch(MusePrefs.onDemand) && museOnDemandSsids(ref.watch(MusePrefs.wifiRules)).isNotEmpty;
    return MuseSection(
      header: '通用',
      footer: '「通知栏断开按钮」从下次连接起生效。其他应用（如自动化工具）可发送 com.chuanyun.app.action.START / STOP / TOGGLE 来连接、断开或切换。',
      children: [
        MuseSwitchTile(
          key: const ValueKey('settings_auto_run'),
          leading: const Icon(Icons.play_circle_outlined),
          title: '自动运行',
          subtitle: '打开穿云时自动连接',
          value: autoRun,
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
        MuseSwitchTile(
          key: const ValueKey('settings_notify_stop'),
          leading: const Icon(Icons.notifications_outlined),
          title: '通知栏断开按钮',
          value: stopButton,
          onChanged: (v) => ref.read(MusePrefs.notifyStopButton.notifier).update(v),
        ),
      ],
    );
  }
}
