// 穿云 Windows - the desktop-only rows of 设置: 运行模式 (系统代理 / TUN), 开机自启, 静默启动 (1.6.0 C7),
// 关闭窗口时.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/muse/data/windows_admin.dart';
import 'package:hiddify/features/muse/settings/service_mode_switch.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

String _modeTitle(ServiceMode mode) => switch (mode) {
  ServiceMode.tun => 'TUN 模式（需管理员）',
  _ => '系统代理',
};

class WindowsSettingsSection extends ConsumerWidget {
  const WindowsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final mode = ref.watch(ConfigOptions.serviceMode);
    final tunNeedsAdmin = mode == ServiceMode.tun && !WindowsAdmin.isElevated;
    final autoStart = ref.watch(autoStartNotifierProvider).valueOrNull ?? false;
    final closing = ref.watch(Preferences.actionAtClose);

    return MuseSection(
      header: '电脑',
      children: [
        MuseTile(
          leading: const Icon(Icons.swap_horiz_outlined),
          title: '运行模式',
          trailing: tunNeedsAdmin
              ? const Icon(Icons.error_outlined, color: MusePalette.orange, size: MuseIconSize.small)
              : Text(mode == ServiceMode.tun ? 'TUN' : '系统代理'),
          chevron: true,
          onTap: () async {
            final dialogs = ref.read(dialogNotifierProvider.notifier);
            final picked = await dialogs.showSettingPicker<ServiceMode>(
              title: '运行模式',
              selected: mode,
              options: const [ServiceMode.systemProxy, ServiceMode.tun],
              getTitle: _modeTitle,
            );
            if (picked == null) {
              // tapping the row again while TUN still waits for administrator rights
              if (tunNeedsAdmin) await museOfferElevation(ref);
              return;
            }
            await museSwitchServiceMode(ref, picked);
          },
        ),
        // 1.2.2: same switch tile as every other 设置 row
        MuseSwitchTile(
          leading: const Icon(Icons.power_settings_new_outlined),
          title: '开机自启',
          value: autoStart,
          onChanged: (value) async {
            final notifier = ref.read(autoStartNotifierProvider.notifier);
            value ? await notifier.enable() : await notifier.disable();
          },
        ),
        // 1.6.0 C7 (#146): the existing silent_start preference, now on screen
        MuseSwitchTile(
          key: const ValueKey('settings_silent_start'),
          leading: const Icon(Icons.visibility_off_outlined),
          title: '静默启动',
          info: '打开穿云时不弹出窗口，只在托盘里运行（点托盘图标显示窗口）',
          value: ref.watch(Preferences.silentStart),
          onChanged: (v) => ref.read(Preferences.silentStart.notifier).update(v),
        ),
        MuseTile(
          leading: const Icon(Icons.close_outlined),
          title: '关闭窗口时',
          trailing: Text(closing.present(t)),
          chevron: true,
          onTap: () async {
            final selected = await ref.read(dialogNotifierProvider.notifier).showActionAtClosing(selected: closing);
            if (selected != null) await ref.read(Preferences.actionAtClose.notifier).update(selected);
          },
        ),
      ],
    );
  }
}
