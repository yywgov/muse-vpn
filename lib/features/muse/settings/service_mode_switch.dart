// 穿云 1.6.0 C4 - switching 运行模式 (系统代理 / TUN) on Windows, shared by 设置 › 电脑 and the
// 首页「网络接管」card. Only writes ConfigOptions.serviceMode (a running connection restarts in the
// new mode through ConfigOptionNotifier) or relaunches elevated - never touches the connection itself.
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/windows_admin.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What switching from [current] to [picked] needs.
enum MuseModeStep { none, apply, needsAdmin }

MuseModeStep museModeStep(ServiceMode current, ServiceMode picked, {required bool elevated}) {
  if (picked == current) return MuseModeStep.none;
  if (picked == ServiceMode.tun && !elevated) return MuseModeStep.needsAdmin;
  return MuseModeStep.apply;
}

const museTunAdminMessage = 'TUN 模式需要以管理员身份运行穿云。要以管理员身份重新打开吗？';
const museTunAdminWaitingMessage = 'TUN 模式需要以管理员身份运行穿云，现在没有管理员权限，暂时使用系统代理。要以管理员身份重新打开吗？';

/// `ref.read` of a widget or a provider (1.6.0 C8: the tray switches the mode too).
typedef MuseRead = T Function<T>(ProviderListenable<T> provider);

Future<void> museRelaunchElevated(MuseRead read) async {
  if (!await WindowsAdmin.relaunchElevated()) return;
  await read(windowNotifierProvider.notifier).exit();
}

/// Switches to [picked] (asks for administrator rights for TUN when needed). Returns true when the
/// mode was saved.
Future<bool> museSwitchServiceMode(MuseRead read, ServiceMode picked, {bool? elevated}) async {
  final current = read(ConfigOptions.serviceMode);
  switch (museModeStep(current, picked, elevated: elevated ?? WindowsAdmin.isElevated)) {
    case MuseModeStep.none:
      return false;
    case MuseModeStep.needsAdmin:
      final ok = await read(dialogNotifierProvider.notifier)
          .showConfirmation(title: '需要管理员权限', message: museTunAdminMessage, positiveBtnTxt: '重新打开');
      if (!ok) return false;
      await read(ConfigOptions.serviceMode.notifier).update(picked);
      await museRelaunchElevated(read);
      return true;
    case MuseModeStep.apply:
      await read(ConfigOptions.serviceMode.notifier).update(picked);
      return true;
  }
}

/// TUN chosen but this process has no administrator rights: offer to relaunch.
Future<void> museOfferElevation(MuseRead read) async {
  final ok = await read(dialogNotifierProvider.notifier)
      .showConfirmation(title: '需要管理员权限', message: museTunAdminWaitingMessage, positiveBtnTxt: '重新打开');
  if (ok) await museRelaunchElevated(read);
}
