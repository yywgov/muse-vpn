// 穿云 - 设置 > 隐私: hide the launcher icon, stay out of recents, quiet notification.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PrivacyPage extends HookConsumerWidget {
  const PrivacyPage({super.key});

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

    return MuseScaffold(
      title: '隐私',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseSwitchTile(
                leading: const Icon(Icons.visibility_off_rounded),
                title: '隐藏桌面图标',
                value: iconHidden.value ?? false,
                onChanged: iconHidden.value == null ? null : toggleIcon,
              ),
              MuseSwitchTile(
                leading: const Icon(Icons.layers_clear_rounded),
                title: '不在最近任务显示',
                value: excludeRecents,
                onChanged: (value) async {
                  await ref.read(Preferences.excludeFromRecents.notifier).update(value);
                  await ChuanyunPlatform.setExcludeFromRecents(value);
                },
              ),
            ],
          ),
          MuseSection(
            header: '通知',
            children: [
              MuseSwitchTile(
                leading: const Icon(Icons.notifications_off_rounded),
                title: '隐藏通知',
                value: hideNotification,
                onChanged: ref.read(Preferences.hideNotification.notifier).update,
              ),
              MuseTile(
                leading: const Icon(Icons.tune_rounded),
                title: '系统通知设置',
                chevron: true,
                onTap: ChuanyunPlatform.openNotificationSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
