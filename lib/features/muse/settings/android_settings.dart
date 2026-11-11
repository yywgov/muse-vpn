// 穿云 1.6.0 C9 - Android-only settings rows. 1.10.0: the 「通用」 and 「隐私与后台」 groups of the 设置
// home page are gone; 通知栏断开按钮, 隐藏通知 and 隐藏桌面图标 sit on 设置 › 外观 › 通知与图标
// (MuseAndroidAppearanceSection); 1.10.2: 在最近任务中隐藏 is back there too. 自动运行 / 按需运行 are on 设置 › 自动连接 since 1.9.0 #5; the
// 后台保活 page was removed in 1.10.0 (only the one-time hint on the first connection stays).
// 1.11.0: 隐藏桌面图标 is gone; an icon hidden by an older version is shown again once
// ([museRestoreLauncherIconProvider]), since there is no switch left to bring it back.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 设置 › 自动连接 (Android): what other apps can send to connect / disconnect.
const museAndroidAutomationNote = '其他应用（如自动化工具）可发送 com.chuanyun.app.action.START / STOP / TOGGLE 来连接、断开或切换。';

/// 1.11.0: once per install, a launcher icon hidden by an older version is shown again.
final museRestoreLauncherIconProvider = Provider<void>((ref) {
  if (ref.read(MusePrefs.launcherIconRestored)) return;
  // after start-up (never on the cold start path)
  Future<void>.delayed(const Duration(seconds: 5), () async {
    try {
      if (await ChuanyunPlatform.isLauncherIconHidden()) await ChuanyunPlatform.setLauncherIconHidden(false);
      await ref.read(MusePrefs.launcherIconRestored.notifier).update(true);
    } catch (_) {}
  });
});

/// 1.10.2: the 外观 switch that keeps 穿云 out of the recent-apps screen.
const museExcludeRecentsTitle = '在最近任务中隐藏';

class MuseAndroidAppearanceSection extends ConsumerWidget {
  const MuseAndroidAppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stopButton = ref.watch(MusePrefs.notifyStopButton);
    final hideNotification = ref.watch(Preferences.hideNotification);
    final excludeRecents = ref.watch(Preferences.excludeFromRecents);
    return MuseSection(
      key: const ValueKey('appearance_android'),
      // 1.20.3：在 设置 › 隐私与通知 里，原 外观 › 通知与图标
      header: '通知',
      // 1.20.3: 外观页不再有 ⓘ，原 footer 改成这一行的副标题
      children: [
        MuseSwitchTile(
          key: const ValueKey('settings_notify_stop'),
          leading: const Icon(Icons.notifications_outlined),
          title: '通知栏断开按钮',
          subtitle: '从下次连接起生效',
          value: stopButton,
          onChanged: (v) => ref.read(MusePrefs.notifyStopButton.notifier).update(v),
        ),
        MuseSwitchTile(
          key: const ValueKey('settings_hide_notification'),
          leading: const Icon(Icons.notifications_off_outlined),
          title: '隐藏通知',
          value: hideNotification,
          onChanged: ref.read(Preferences.hideNotification.notifier).update,
        ),
        // 1.10.2: back after 1.10.0 removed it with the 后台保活 page (same key exclude_from_recents;
        // MainActivity applies the saved value every time 穿云 comes to the front, as in 1.9.1)
        MuseSwitchTile(
          key: const ValueKey('settings_exclude_recents'),
          leading: const Icon(Icons.layers_clear_outlined),
          title: museExcludeRecentsTitle,
          value: excludeRecents,
          onChanged: (value) async {
            await ref.read(Preferences.excludeFromRecents.notifier).update(value);
            await ChuanyunPlatform.setExcludeFromRecents(value);
          },
        ),
      ],
    );
  }
}
