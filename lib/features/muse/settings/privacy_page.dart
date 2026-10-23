// 穿云 - 设置 › 隐私与后台 (Android): hide the launcher icon, stay out of recents, quiet
// notification, and the 后台运行 / 自启动 rows while they still need doing.
// 1.3.0: one group inside 设置 instead of its own page.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/background_guard.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MusePrivacySection extends HookConsumerWidget {
  const MusePrivacySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconHidden = useState<bool?>(null);
    useEffect(() {
      ChuanyunPlatform.isLauncherIconHidden().then((value) {
        if (context.mounted) iconHidden.value = value;
      });
      return null;
    }, const []);

    Future<void> toggleIcon(bool hide) async {
      if (hide) {
        final ok = await ref
            .read(dialogNotifierProvider.notifier)
            .showConfirmation(
              title: '隐藏桌面图标？',
              message:
                  '隐藏后桌面上不再显示穿云。重新打开的方法：\n\n'
                  '1. 下拉通知栏，长按「穿云开关」快捷开关（需先在快捷开关编辑里添加），即可打开穿云；\n'
                  '2. 系统设置 > 应用 > 穿云 也能找到它。\n\n'
                  '部分系统（Android 10 及以上）可能仍会显示一个跳转到应用信息的图标，这是系统行为。',
              positiveBtnTxt: '隐藏',
            );
        if (!ok) return;
      }
      if (await ChuanyunPlatform.setLauncherIconHidden(hide)) iconHidden.value = hide;
    }

    final hideNotification = ref.watch(Preferences.hideNotification);
    final excludeRecents = ref.watch(Preferences.excludeFromRecents);
    final batteryIgnored = ref.watch(batteryOptimizationNotifierProvider).valueOrNull;
    final needsBattery = batteryIgnored == false;
    final needsAutostart = !ref.watch(Preferences.autostartVisited);
    final killCount = ref.watch(MusePrefs.killCount);

    return MuseSection(
      header: '隐私与后台',
      children: [
        if (needsBattery)
          MuseTile(
            leading: const MuseRowIcon(Icons.battery_alert_outlined, color: MusePalette.orange),
            title: '允许后台运行',
            trailing: const Icon(Icons.error_outlined, color: MusePalette.orange, size: MuseIconSize.small),
            chevron: true,
            onTap: () => ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore(),
          ),
        if (needsAutostart)
          MuseTile(
            leading: const MuseRowIcon(Icons.rocket_launch_outlined, color: MusePalette.orange),
            title: '自启动',
            trailing: const Icon(Icons.error_outlined, color: MusePalette.orange, size: MuseIconSize.small),
            chevron: true,
            onTap: () async {
              await ChuanyunPlatform.openAutostartSettings();
              await ref.read(Preferences.autostartVisited.notifier).update(true);
            },
          ),
        // 1.4.1: per-brand steps (also shown after the system killed 穿云 in the background)
        MuseTile(
          key: const ValueKey('settings_background_guide'),
          leading: const Icon(Icons.shield_moon_outlined),
          title: '后台保活指南',
          trailing: killCount > 0 ? Text('被关闭 $killCount 次') : null,
          chevron: true,
          onTap: () => showMuseBackgroundGuide(context),
        ),
        MuseSwitchTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: '隐藏桌面图标',
          value: iconHidden.value ?? false,
          onChanged: iconHidden.value == null ? null : toggleIcon,
        ),
        MuseSwitchTile(
          leading: const Icon(Icons.layers_clear_outlined),
          title: '不在最近任务显示',
          value: excludeRecents,
          onChanged: (value) async {
            await ref.read(Preferences.excludeFromRecents.notifier).update(value);
            await ChuanyunPlatform.setExcludeFromRecents(value);
          },
        ),
        MuseSwitchTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: '隐藏通知',
          value: hideNotification,
          onChanged: ref.read(Preferences.hideNotification.notifier).update,
        ),
      ],
    );
  }
}
