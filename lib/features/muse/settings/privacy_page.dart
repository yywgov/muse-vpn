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
            footer: '桌面图标隐藏后，从快捷开关长按即可回到穿云。',
            children: [
              MuseSwitchTile(
                leading: const Icon(Icons.visibility_off_rounded),
                title: '隐藏桌面图标',
                subtitle: '不在桌面和应用列表中显示穿云',
                value: iconHidden.value ?? false,
                onChanged: iconHidden.value == null ? null : toggleIcon,
              ),
              MuseSwitchTile(
                leading: const Icon(Icons.layers_clear_rounded),
                title: '不在最近任务显示',
                subtitle: '切到后台后，多任务界面里看不到穿云',
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
            footer:
                '「隐藏通知」把穿云的常驻通知降到最低级别：状态栏不显示图标，只折叠在通知栏底部，下次连接时生效。'
                '想完全不显示，可以在系统通知设置里关闭穿云的通知，连接不受影响。\n'
                '系统自带的「已激活 VPN」提示和状态栏钥匙图标由 Android 显示，任何应用都无法隐藏。',
            children: [
              MuseSwitchTile(
                leading: const Icon(Icons.notifications_off_rounded),
                title: '隐藏通知',
                subtitle: '常驻通知降为最低级别',
                value: hideNotification,
                onChanged: (value) async {
                  await ref.read(Preferences.hideNotification.notifier).update(value);
                  if (value) await ref.read(Preferences.dynamicNotification.notifier).update(false);
                },
              ),
              MuseTile(
                leading: const Icon(Icons.tune_rounded),
                title: '系统通知设置',
                subtitle: '在这里可以完全关闭穿云的通知',
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
