// 穿云 Windows - the desktop-only rows of 设置: 运行模式 (系统代理 / TUN), 开机自启, 静默启动 (1.6.0 C7),
// 关闭窗口时; 1.6.0 C8: 开机自启时静默, 穿云标题栏, 窗口置顶, 按需运行, 快捷键.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/data/windows_admin.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show musePushPage;
import 'package:hiddify/features/muse/settings/windows_extras.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
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
    final onDemandOn = ref.watch(MusePrefs.onDemand) && museOnDemandSsids(ref.watch(MusePrefs.wifiRules)).isNotEmpty;
    final hotkeyCount = ref.watch(MusePrefs.hotkeysOn) ? museParseHotkeys(ref.watch(MusePrefs.hotkeys)).length : 0;

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
              if (tunNeedsAdmin) await museOfferElevation(ref.read);
              return;
            }
            await museSwitchServiceMode(ref.read, picked);
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
        // 1.6.0 C7 (#146): the existing silent_start preference, now on screen
        MuseSwitchTile(
          key: const ValueKey('settings_silent_start'),
          leading: const Icon(Icons.visibility_off_outlined),
          title: '静默启动',
          info: '打开穿云时不弹出窗口，只在托盘里运行（点托盘图标显示窗口）',
          value: ref.watch(Preferences.silentStart),
          onChanged: (v) => ref.read(Preferences.silentStart.notifier).update(v),
        ),
        // 1.6.0 C8: 穿云's own title bar (off = the Windows one) and 窗口置顶
        MuseSwitchTile(
          key: const ValueKey('settings_custom_title_bar'),
          leading: const Icon(Icons.web_asset_outlined),
          title: '穿云标题栏',
          info: '窗口顶部用穿云自己的标题栏（含置顶按钮）；关闭后改用 Windows 自带标题栏',
          value: ref.watch(MusePrefs.customTitleBar),
          onChanged: (v) => ref.read(windowNotifierProvider.notifier).setCustomTitleBar(v),
        ),
        MuseSwitchTile(
          key: const ValueKey('settings_always_on_top'),
          leading: const Icon(Icons.push_pin_outlined),
          title: '窗口置顶',
          value: ref.watch(MusePrefs.alwaysOnTop),
          onChanged: (v) => ref.read(windowNotifierProvider.notifier).setAlwaysOnTop(v),
        ),
        MuseTile(
          key: const ValueKey('settings_on_demand'),
          leading: const Icon(Icons.wifi_outlined),
          title: '按需运行',
          trailing: Text(onDemandOn ? '开' : '关'),
          chevron: true,
          onTap: () => musePushPage(context, const MuseOnDemandPage()),
        ),
        MuseTile(
          key: const ValueKey('settings_hotkeys'),
          leading: const Icon(Icons.keyboard_outlined),
          title: '快捷键',
          trailing: Text(hotkeyCount == 0 ? '未设置' : '$hotkeyCount 个'),
          chevron: true,
          onTap: () => musePushPage(context, const MuseHotkeysPage()),
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
