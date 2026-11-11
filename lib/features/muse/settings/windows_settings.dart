// 穿云 Windows - the desktop-only settings rows. 1.10.0: there is no 「电脑」 group on the 设置 home
// page any more; each row sits on the page it belongs to:
//   运行模式 (系统代理 / TUN) → 设置 › 网络 (MuseWindowsModeTile)
//   静默启动 → 设置 › 自动连接 (MuseWindowsSilentStartTile, next to 开机自启)
//   穿云标题栏 / 窗口置顶 / 快捷键 / 关闭窗口时 → 设置 › 外观 › 窗口 (MuseWindowsWindowSection)
// Preferences and behaviour are unchanged.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/windows_admin.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/desktop/uwp_loopback.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
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

/// 运行模式 (设置 › 网络).
class MuseWindowsModeTile extends ConsumerWidget {
  const MuseWindowsModeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ConfigOptions.serviceMode);
    final tunNeedsAdmin = mode == ServiceMode.tun && !WindowsAdmin.isElevated;
    return MuseTile(
      key: const ValueKey('settings_service_mode'),
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
    );
  }
}

/// 1.17.0 R12: the SIDs stored by 「允许商店应用走代理」.
List<String> museUwpAddedFromRaw(String raw) {
  try {
    return [for (final e in jsonDecode(raw) as List) '$e'];
  } catch (_) {
    return const [];
  }
}

/// 1.17.0 R12: 允许商店应用走代理 (设置 › 网络, Windows). Runs only when tapped, after the explanation.
class MuseUwpLoopbackTile extends ConsumerStatefulWidget {
  const MuseUwpLoopbackTile({super.key});

  @override
  ConsumerState<MuseUwpLoopbackTile> createState() => _MuseUwpLoopbackTileState();
}

class _MuseUwpLoopbackTileState extends ConsumerState<MuseUwpLoopbackTile> {
  bool _busy = false;

  Future<void> _run({required bool revert}) async {
    final dialogs = ref.read(dialogNotifierProvider.notifier);
    final added = museUwpAddedFromRaw(ref.read(MusePrefs.uwpLoopbackAdded));
    final ok = await dialogs.showConfirmation(
      title: revert ? '撤销商店应用开通' : '允许商店应用走代理',
      message: revert
          ? '将撤销穿云之前为 ${added.length} 个商店应用开通的本机回环，需要一次管理员授权。你自己用其他工具开通的不受影响。'
          : museLoopbackExplain,
      positiveBtnTxt: revert ? '撤销' : '开通',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final MuseLoopbackResult r;
    try {
      r = revert
          ? await MuseUwpLoopback.revert(added)
          : await MuseUwpLoopback.exemptAll(
              onAdded: (sids) => ref
                  .read(MusePrefs.uwpLoopbackAdded.notifier)
                  .update(jsonEncode({...added, ...sids}.toList())),
            );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (revert && r is MuseLoopbackDone) await ref.read(MusePrefs.uwpLoopbackAdded.notifier).update('');
    final toast = ref.read(inAppNotificationControllerProvider);
    final text = museLoopbackResultText(r);
    if (r is MuseLoopbackDone) {
      toast.showSuccessToast(text);
    } else {
      toast.showErrorToast(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final added = museUwpAddedFromRaw(ref.watch(MusePrefs.uwpLoopbackAdded));
    return MuseTile(
      key: const ValueKey('settings_uwp_loopback'),
      leading: const Icon(Icons.storefront_outlined),
      title: '允许商店应用走代理',
      subtitle: added.isEmpty ? '邮件、天气等商店应用默认连不上本机代理；点一下开通（需管理员授权）' : '已为 ${added.length} 个商店应用开通 · 点一下可再次开通或撤销',
      trailing: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      chevron: !_busy,
      onTap: _busy
          ? null
          : () async {
              if (added.isEmpty) return _run(revert: false);
              final picked = await ref.read(dialogNotifierProvider.notifier).showSettingPicker<String>(
                title: '允许商店应用走代理',
                selected: '',
                options: const ['add', 'revert'],
                getTitle: (v) => v == 'revert' ? '撤销穿云开通的' : '为新装的商店应用开通',
              );
              if (picked == 'add' || picked == 'revert') await _run(revert: picked == 'revert');
            },
    );
  }
}

/// 静默启动 (设置 › 自动连接 › 开机). 1.6.0 C7 (#146): the existing silent_start preference.
class MuseWindowsSilentStartTile extends ConsumerWidget {
  const MuseWindowsSilentStartTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MuseSwitchTile(
    key: const ValueKey('settings_silent_start'),
    leading: const Icon(Icons.visibility_off_outlined),
    title: '静默启动',
    info: '打开穿云时不弹出窗口，只在托盘里运行（点托盘图标显示窗口）',
    value: ref.watch(Preferences.silentStart),
    onChanged: (v) => ref.read(Preferences.silentStart.notifier).update(v),
  );
}

/// 穿云标题栏 / 窗口置顶 / 快捷键 / 关闭窗口时 (设置 › 外观 › 窗口).
class MuseWindowsWindowSection extends ConsumerWidget {
  const MuseWindowsWindowSection({super.key, this.advancedOpen = false});

  /// 1.11.0: 「高级」 (穿云标题栏 / 快捷键 / 窗口置顶) unfolded
  final bool advancedOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final closing = ref.watch(Preferences.actionAtClose);
    final hotkeyCount = ref.watch(MusePrefs.hotkeysOn) ? museParseHotkeys(ref.watch(MusePrefs.hotkeys)).length : 0;
    return Column(
      key: const ValueKey('appearance_windows'),
      children: [
        MuseSection(header: '窗口', children: [
        MuseTile(
          key: const ValueKey('settings_close_action'),
          leading: const Icon(Icons.close_outlined),
          title: '关闭窗口时',
          trailing: Text(closing.present(t)),
          chevron: true,
          onTap: () async {
            final selected = await ref.read(dialogNotifierProvider.notifier).showActionAtClosing(selected: closing);
            if (selected != null) await ref.read(Preferences.actionAtClose.notifier).update(selected);
          },
        ),
        ]),
        // 1.11.0: 穿云标题栏 / 快捷键 / 窗口置顶 fold into 「高级」 (same preferences)
        MuseFoldSection(
          foldKey: const ValueKey('window_advanced_fold'),
          summary: '穿云标题栏、全局快捷键、窗口置顶',
          initiallyOpen: advancedOpen,
          children: [
        // 1.6.0 C8: 穿云's own title bar (off = the Windows one) and 窗口置顶
        MuseSwitchTile(
          key: const ValueKey('settings_custom_title_bar'),
          leading: const Icon(Icons.web_asset_outlined),
          title: '穿云标题栏',
          // 1.20.3: 外观页不再有 ⓘ（原说明：含置顶按钮；关闭后改用系统自带标题栏）
          subtitle: '关闭后用系统自带标题栏',
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
          key: const ValueKey('settings_hotkeys'),
          leading: const Icon(Icons.keyboard_outlined),
          title: '快捷键',
          trailing: Text(hotkeyCount == 0 ? '未设置' : '$hotkeyCount 个'),
          chevron: true,
          onTap: () => musePushPage(context, const MuseHotkeysPage()),
        ),
          ],
        ),
      ],
    );
  }
}
