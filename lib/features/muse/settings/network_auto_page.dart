// 穿云 - 设置 > 按网络自动开关: disconnect on trusted Wi-Fi, reconnect after leaving it.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

List<String> _ssids(String raw) =>
    raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();

class NetworkAutoPage extends HookConsumerWidget {
  const NetworkAutoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(Preferences.netAutoEnabled);
    final ssids = _ssids(ref.watch(Preferences.netTrustedSsids));
    final status = useState<LocationStatus?>(null);
    final lifecycle = useAppLifecycleState();

    Future<void> refreshStatus() async {
      final value = await ChuanyunPlatform.locationStatus();
      if (context.mounted) status.value = value;
    }

    // re-check after coming back from the system settings
    useEffect(() {
      refreshStatus();
      return null;
    }, [lifecycle]);

    Future<void> saveSsids(List<String> list) async {
      await ref.read(Preferences.netTrustedSsids.notifier).update(list.join('\n'));
      await ChuanyunPlatform.applyNetworkAuto();
    }

    Future<void> setEnabled(bool value) async {
      if (value) {
        final granted = await ChuanyunPlatform.requestLocationPermission();
        await refreshStatus();
        if (!granted) {
          ref.read(inAppNotificationControllerProvider).showInfoToast('没有位置权限就无法识别 Wi-Fi 名称');
        }
      }
      await ref.read(Preferences.netAutoEnabled.notifier).update(value);
      await ChuanyunPlatform.applyNetworkAuto();
    }

    Future<void> addCurrent() async {
      if (!(status.value?.granted ?? false)) {
        await ChuanyunPlatform.requestLocationPermission();
        await refreshStatus();
      }
      final ssid = await ChuanyunPlatform.wifiSsid();
      if (ssid == null) {
        ref.read(inAppNotificationControllerProvider).showInfoToast('读取不到 Wi-Fi 名称：请连接 Wi-Fi，并打开定位和位置权限');
        return;
      }
      if (ssids.contains(ssid)) return;
      await saveSsids([...ssids, ssid]);
    }

    Future<void> addManual() async {
      final value = await ref
          .read(dialogNotifierProvider.notifier)
          .showSettingInput<String>(title: '添加可信 Wi-Fi', initialValue: '');
      final ssid = value?.trim() ?? '';
      if (ssid.isEmpty || ssids.contains(ssid)) return;
      await saveSsids([...ssids, ssid]);
    }

    final s = status.value;
    final permissionRows = <Widget>[
      if (s != null && !s.granted)
        MuseTile(
          leading: const Icon(Icons.location_off_rounded, color: Colors.orange),
          title: '需要位置权限',
          subtitle: 'Android 只在有位置权限时才告诉应用当前 Wi-Fi 的名称。穿云不会读取或上传你的位置。',
          chevron: true,
          onTap: () async {
            await ChuanyunPlatform.requestLocationPermission();
            await refreshStatus();
          },
        ),
      if (s != null && s.granted && !s.background)
        MuseTile(
          leading: const Icon(Icons.my_location_rounded, color: Colors.orange),
          title: '建议改为「始终允许」',
          subtitle: '穿云在后台时也要识别 Wi-Fi，请在 权限 > 位置信息 里选择「始终允许」。',
          chevron: true,
          onTap: ChuanyunPlatform.openAppDetails,
        ),
      if (s != null && !s.enabled)
        MuseTile(
          leading: const Icon(Icons.gps_off_rounded, color: Colors.orange),
          title: '请打开系统定位',
          subtitle: '定位总开关关闭时，系统不提供 Wi-Fi 名称。',
          chevron: true,
          onTap: ChuanyunPlatform.openLocationSettings,
        ),
    ];

    return MuseScaffold(
      title: '按网络自动开关',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer:
                '连上下面的可信 Wi-Fi（如家里、公司）时自动断开穿云；离开后（切到移动数据或其他 Wi-Fi）自动重新连接。'
                '只有被自动断开的连接才会自动恢复，你手动断开后不会再自己连上。\n'
                'Android 12 及以上系统可能不允许后台直接连接，这时会弹出一条通知，点一下即可连接。',
            children: [
              MuseSwitchTile(
                leading: const Icon(Icons.wifi_rounded),
                title: '按网络自动开关',
                value: enabled,
                onChanged: setEnabled,
              ),
            ],
          ),
          if (enabled && permissionRows.isNotEmpty) MuseSection(header: '权限', children: permissionRows),
          MuseSection(
            header: '可信 Wi-Fi',
            footer: ssids.isEmpty ? '还没有可信 Wi-Fi。' : '左滑或点右侧按钮删除。',
            children: [
              for (final ssid in ssids)
                Dismissible(
                  key: ValueKey(ssid),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => saveSsids(ssids.where((e) => e != ssid).toList()),
                  background: Container(
                    color: Theme.of(context).colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  ),
                  child: MuseTile(
                    leading: const Icon(Icons.wifi_lock_rounded),
                    title: ssid,
                    trailing: IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => saveSsids(ssids.where((e) => e != ssid).toList()),
                    ),
                  ),
                ),
              MuseTile(
                leading: const Icon(Icons.add_location_alt_rounded),
                title: '添加当前 Wi-Fi',
                onTap: addCurrent,
              ),
              MuseTile(leading: const Icon(Icons.edit_rounded), title: '手动输入 Wi-Fi 名称', onTap: addManual),
            ],
          ),
        ],
      ),
    );
  }
}
