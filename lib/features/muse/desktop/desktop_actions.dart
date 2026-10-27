// 穿云 1.6.0 C8 - what the tray menu and the global hotkeys can do. Each one calls the same
// notifier method the window's own buttons use, so the connection state machine stays the only
// place that changes the connection.
// Part of 穿云 (GPLv3).

import 'package:flutter/services.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/notify.dart';
import 'package:hiddify/features/muse/logic/proxy_env.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/settings/service_mode_switch.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum MuseDesktopAction {
  toggleConnection,
  showWindow,
  toggleWindow,
  toggleMode,
  urlTest,
  updateProfiles,
  copyEnv,
  openNodes,
  systemProxy,
  tun,
  toggleAutoStart,
  quit,
}

const museCopiedEnvId = 2108;

/// The mode the other one of 规则 / 全局.
MuseRouteMode museOtherRouteMode(MuseRouteMode m) =>
    m == MuseRouteMode.rule ? MuseRouteMode.global : MuseRouteMode.rule;

/// The terminal command for [kind] on this computer's proxy port.
String museProxyEnvFor(MuseRead read, MuseShellKind kind) => museProxyEnvCommand(kind, read(ConfigOptions.mixedPort));

Future<void> museRunDesktopAction(
  Ref ref,
  MuseDesktopAction action, {
  MuseShellKind shell = MuseShellKind.powershell,
  bool fromHotkey = false,
}) async {
  switch (action) {
    case MuseDesktopAction.toggleConnection:
      await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    case MuseDesktopAction.showWindow:
      await ref.read(windowNotifierProvider.notifier).show();
    case MuseDesktopAction.toggleWindow:
      await ref.read(windowNotifierProvider.notifier).showOrHide();
    case MuseDesktopAction.toggleMode:
      final m = ref.read(ConfigOptions.museRouteMode);
      await ref.read(ConfigOptions.museRouteMode.notifier).update(museOtherRouteMode(m));
    case MuseDesktopAction.urlTest:
      final group = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
      if (group != null) await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group.tag);
    case MuseDesktopAction.updateProfiles:
      await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
    case MuseDesktopAction.copyEnv:
      final text = museProxyEnvFor(ref.read, shell);
      await Clipboard.setData(ClipboardData(text: text));
      // a hotkey has no menu to see: say what was copied
      if (fromHotkey) await museNotify(id: museCopiedEnvId, title: '已复制终端代理命令（${shell.title}）', text: text);
    case MuseDesktopAction.openNodes:
      await ref.read(windowNotifierProvider.notifier).show();
      ref.read(goRouterNotiferProvider).goNamed('nodes');
    case MuseDesktopAction.systemProxy:
      await museSwitchServiceMode(ref.read, ServiceMode.systemProxy);
    case MuseDesktopAction.tun:
      // TUN may ask for administrator rights in a dialog: bring the window up first
      await ref.read(windowNotifierProvider.notifier).show();
      await museSwitchServiceMode(ref.read, ServiceMode.tun);
    case MuseDesktopAction.toggleAutoStart:
      final on = ref.read(autoStartNotifierProvider).valueOrNull ?? false;
      final n = ref.read(autoStartNotifierProvider.notifier);
      on ? await n.disable() : await n.enable();
    case MuseDesktopAction.quit:
      await ref.read(windowNotifierProvider.notifier).exit();
  }
}
