// 穿云 1.4.1 - Android: notices that the system killed 穿云 in the background (the VPN service
// recorded a start but never a stop, and it wasn't a reboot or an app update) and shows the steps
// for this phone's brand to keep it alive. Also reachable from 设置 › 后台保活.
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/android_keepalive.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Checks once, a few seconds after start-up; true when 穿云 was killed since the last start.
Future<bool> museCheckBackgroundKill(WidgetRef ref) async {
  if (!PlatformUtils.isAndroid) return false;
  await Future<void>.delayed(const Duration(seconds: 4));
  try {
    final since = await ChuanyunPlatform.connectedSince() ?? 0;
    final info = await ChuanyunPlatform.deviceInfo();
    final version = ref.read(museAppVersionProvider) ?? '';
    final last = ref.read(MusePrefs.lastRunVersion);
    final updated = last.isNotEmpty && version.isNotEmpty && last != version;
    if (version.isNotEmpty && last != version) await ref.read(MusePrefs.lastRunVersion.notifier).update(version);
    final killed = museWasKilledInBackground(
      connectedSince: since,
      running: ref.read(serviceRunningProvider),
      bootTime: info?.bootTime ?? 0,
      appUpdated: updated,
      lastReported: ref.read(MusePrefs.killReported),
    );
    if (since > 0 && !ref.read(serviceRunningProvider)) await ref.read(MusePrefs.killReported.notifier).update(since);
    if (!killed) return false;
    await ref.read(MusePrefs.killCount.notifier).update(ref.read(MusePrefs.killCount) + 1);
    unawaited(ChuanyunPlatform.recordDisconnect('穿云在后台被系统关闭（上次连接开始于 ${DateTime.fromMillisecondsSinceEpoch(since)}）'));
    return true;
  } catch (_) {
    return false;
  }
}

/// The per-brand steps; [killed] adds the 「刚刚被系统关闭」 line.
Future<void> showMuseBackgroundGuide(BuildContext context, {bool killed = false}) async {
  final info = await ChuanyunPlatform.deviceInfo();
  if (!context.mounted) return;
  final guide = museOemGuide(info?.manufacturer ?? '', brand: info?.brand ?? '');
  await showDialog<void>(
    context: context,
    builder: (c) => _BackgroundGuideDialog(guide: guide, killed: killed),
  );
}

class _BackgroundGuideDialog extends ConsumerWidget {
  const _BackgroundGuideDialog({required this.guide, required this.killed});

  final MuseOemGuide guide;
  final bool killed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ignored = ref.watch(batteryOptimizationNotifierProvider).valueOrNull ?? false;
    final mt = MuseTheme.of(context);
    return AlertDialog(
      key: const ValueKey('background_guide'),
      title: Text(killed ? '穿云在后台被系统关闭了' : '后台保活'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${guide.brand} 手机请这样设置：', style: MuseType.body(context).copyWith(color: mt.text2)),
            const SizedBox(height: MuseSpace.s8),
            for (var i = 0; i < guide.steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: MuseSpace.s24, child: Text('${i + 1}.', style: MuseType.body(context))),
                    Expanded(child: Text(guide.steps[i], style: MuseType.body(context))),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (!ignored)
          TextButton(
            key: const ValueKey('background_guide_battery'),
            onPressed: () => ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore(),
            child: const Text('允许后台运行'),
          ),
        TextButton(
          key: const ValueKey('background_guide_settings'),
          onPressed: () => ChuanyunPlatform.openAutostartSettings(),
          child: const Text('打开设置'),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('好的')),
      ],
    );
  }
}
