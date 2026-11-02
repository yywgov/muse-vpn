// 穿云 1.1 - the one-time background hint on the first connection.
// 1.10.0: the 后台保活 page is gone; this is the only fallback left: on Android, the first time a
// connection is up and 穿云 is not exempt from battery optimisation, one dialog offers the system
// setting. Shown at most once (keep_alive_guide_shown); nothing runs in the background for it
// (no wake-ups, no polling).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/settings/data/battery_optimization_repository.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the hint should open (pure, for tests).
bool museShouldShowKeepAliveGuide({required bool isAndroid, required bool alreadyShown, required bool batteryIgnored}) =>
    isAndroid && !alreadyShown && !batteryIgnored;

/// [android] / [batteryIgnored] stand in for the platform in tests.
Future<void> museMaybeShowKeepAliveGuide(
  BuildContext context,
  WidgetRef ref, {
  bool? android,
  Future<bool?> Function()? batteryIgnored,
}) async {
  final isAndroid = android ?? PlatformUtils.isAndroid;
  if (!isAndroid || ref.read(Preferences.keepAliveGuideShown)) return;
  final ignored = await (batteryIgnored ?? BatteryOptimizationRepositoryImpl().isIgnoringBatteryOptimizations)() ?? false;
  final show = museShouldShowKeepAliveGuide(
    isAndroid: isAndroid,
    alreadyShown: ref.read(Preferences.keepAliveGuideShown),
    batteryIgnored: ignored,
  );
  if (!show || !context.mounted) return;
  // saved before the dialog opens: it never comes back, whatever the user taps
  await ref.read(Preferences.keepAliveGuideShown.notifier).update(true);
  if (!context.mounted) return;
  await showMuseKeepAliveHint(context, ref);
}

/// The hint itself: 「去设置」 asks the system to let 穿云 run in the background.
Future<void> showMuseKeepAliveHint(BuildContext context, WidgetRef ref) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('keep_alive_hint'),
      title: const Text('允许穿云在后台运行'),
      content: const Text('系统的电池优化可能在后台关闭穿云，导致连接断开。建议在系统设置里允许穿云在后台运行。'),
      actions: [
        TextButton(key: const ValueKey('keep_alive_hint_later'), onPressed: () => Navigator.of(c).pop(false), child: const Text('以后再说')),
        FilledButton(key: const ValueKey('keep_alive_hint_go'), onPressed: () => Navigator.of(c).pop(true), child: const Text('去设置')),
      ],
    ),
  );
  if (go ?? false) await ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore();
}
