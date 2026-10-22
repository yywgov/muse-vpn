// 穿云 1.1 - 第一次连上后，一次性引导「允许后台运行」(电池优化白名单) 和「自启动」(ColorOS)。
// Shown at most once; afterwards the rows only appear in 设置 while something is still missing.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/settings/data/battery_optimization_repository.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the guide should open (pure, for tests).
bool museShouldShowKeepAliveGuide({
  required bool isAndroid,
  required bool alreadyShown,
  required bool batteryIgnored,
  required bool autostartVisited,
}) => isAndroid && !alreadyShown && !(batteryIgnored && autostartVisited);

Future<void> museMaybeShowKeepAliveGuide(BuildContext context, WidgetRef ref) async {
  final batteryIgnored = await BatteryOptimizationRepositoryImpl().isIgnoringBatteryOptimizations() ?? false;
  final show = museShouldShowKeepAliveGuide(
    isAndroid: PlatformUtils.isAndroid,
    alreadyShown: ref.read(Preferences.keepAliveGuideShown),
    batteryIgnored: batteryIgnored,
    autostartVisited: ref.read(Preferences.autostartVisited),
  );
  if (!show || !context.mounted) return;
  await ref.read(Preferences.keepAliveGuideShown.notifier).update(true);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _KeepAliveGuideDialog(batteryIgnored: batteryIgnored),
  );
}

class _KeepAliveGuideDialog extends ConsumerWidget {
  const _KeepAliveGuideDialog({required this.batteryIgnored});

  final bool batteryIgnored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autostartVisited = ref.watch(Preferences.autostartVisited);
    final ignored = ref.watch(batteryOptimizationNotifierProvider).valueOrNull ?? batteryIgnored;
    return AlertDialog(
      title: const Text('保持后台连接'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('为防止系统清理后台导致断开，建议开启以下两项。'),
          const SizedBox(height: MuseSpace.s12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              ignored ? Icons.check_circle_rounded : Icons.battery_alert_rounded,
              color: ignored ? MusePalette.green : MusePalette.orange,
            ),
            title: const Text('允许后台运行'),
            onTap: ignored ? null : () => ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              autostartVisited ? Icons.check_circle_rounded : Icons.rocket_launch_rounded,
              color: autostartVisited ? MusePalette.green : MusePalette.orange,
            ),
            title: const Text('自启动'),
            onTap: () async {
              await ChuanyunPlatform.openAutostartSettings();
              await ref.read(Preferences.autostartVisited.notifier).update(true);
            },
          ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('完成'))],
    );
  }
}
