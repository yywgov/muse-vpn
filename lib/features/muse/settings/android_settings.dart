// 穿云 1.6.0 C9 - 设置 › 通用 (Android): 通知栏「断开」按钮.
// 1.9.0 #5: 自动运行 / 按需运行 moved to 设置 › 自动连接 (auto_connect_page.dart).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseAndroidGeneralSection extends ConsumerWidget {
  const MuseAndroidGeneralSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stopButton = ref.watch(MusePrefs.notifyStopButton);
    return MuseSection(
      header: '通用',
      footer: '「通知栏断开按钮」从下次连接起生效。其他应用（如自动化工具）可发送 com.chuanyun.app.action.START / STOP / TOGGLE 来连接、断开或切换。',
      children: [
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
