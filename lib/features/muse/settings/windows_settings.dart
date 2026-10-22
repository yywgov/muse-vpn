// 穿云 Windows - the desktop-only rows of 设置: 运行模式 (系统代理 / TUN), 开机自启, 关闭窗口时.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/muse/data/windows_admin.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

String _modeTitle(ServiceMode mode) => switch (mode) {
  ServiceMode.tun => 'TUN 模式（需管理员）',
  _ => '系统代理',
};

class WindowsSettingsSection extends ConsumerWidget {
  const WindowsSettingsSection({super.key});

  Future<void> _relaunchElevated(WidgetRef ref) async {
    if (!await WindowsAdmin.relaunchElevated()) return;
    await ref.read(windowNotifierProvider.notifier).exit();
  }

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
          leading: const Icon(Icons.swap_horiz_rounded),
          title: '运行模式',
          trailing: tunNeedsAdmin
              ? const Icon(Icons.error_rounded, color: MusePalette.orange, size: MuseIconSize.small)
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
              if (tunNeedsAdmin) {
                final ok = await dialogs.showConfirmation(
                  title: '需要管理员权限',
                  message: 'TUN 模式需要以管理员身份运行穿云，现在没有管理员权限，暂时使用系统代理。要以管理员身份重新打开吗？',
                  positiveBtnTxt: '重新打开',
                );
                if (ok) await _relaunchElevated(ref);
              }
              return;
            }
            if (picked == mode) return;
            if (picked == ServiceMode.tun && !WindowsAdmin.isElevated) {
              final ok = await dialogs.showConfirmation(
                title: '需要管理员权限',
                message: 'TUN 模式需要以管理员身份运行穿云。要以管理员身份重新打开吗？',
                positiveBtnTxt: '重新打开',
              );
              if (!ok) return;
              await ref.read(ConfigOptions.serviceMode.notifier).update(picked);
              await _relaunchElevated(ref);
              return;
            }
            // a running connection restarts in the new mode (ConfigOptionNotifier)
            await ref.read(ConfigOptions.serviceMode.notifier).update(picked);
          },
        ),
        // 1.2.2: same switch tile as every other 设置 row
        MuseSwitchTile(
          leading: const Icon(Icons.power_settings_new_rounded),
          title: '开机自启',
          value: autoStart,
          onChanged: (value) async {
            final notifier = ref.read(autoStartNotifierProvider.notifier);
            value ? await notifier.enable() : await notifier.disable();
          },
        ),
        MuseTile(
          leading: const Icon(Icons.close_rounded),
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
