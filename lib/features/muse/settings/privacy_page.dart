// 穿云 - 设置 › 隐私与后台 (Android): hide the launcher icon, stay out of recents, quiet
// notification, and the 后台运行 / 自启动 rows while they still need doing.
// 1.3.0: one group inside 设置 instead of its own page.
// 1.9.0 #6: the 后台 rows moved to 设置 › 后台保活 (keep_alive_page.dart); one row leads there.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/settings/keep_alive_page.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show musePushPage;
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
    final needsAttention = museKeepAliveNeedsAttention(
      batteryIgnored: ref.watch(batteryOptimizationNotifierProvider).valueOrNull,
      autostartVisited: ref.watch(Preferences.autostartVisited),
    );
    final killCount = ref.watch(MusePrefs.killCount);

    return MuseSection(
      header: '隐私与后台',
      children: [
        // 1.9.0 #6: 允许后台运行 / 自启动 / 不在最近任务显示 / 本机设置步骤 live on 后台保活
        MuseTile(
          key: const ValueKey('settings_keep_alive'),
          leading: needsAttention
              ? const MuseRowIcon(Icons.shield_moon_outlined, color: MusePalette.orange)
              : const Icon(Icons.shield_moon_outlined),
          title: '后台保活',
          trailing: needsAttention
              ? const Icon(Icons.error_outlined, color: MusePalette.orange, size: MuseIconSize.small)
              : (killCount > 0 ? Text('被关闭 $killCount 次') : null),
          chevron: true,
          onTap: () => musePushPage(context, const MuseKeepAlivePage()),
        ),
        MuseSwitchTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: '隐藏桌面图标',
          value: iconHidden.value ?? false,
          onChanged: iconHidden.value == null ? null : toggleIcon,
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
