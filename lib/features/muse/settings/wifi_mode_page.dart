// 穿云 1.15.0 R23 - 设置 › 自动连接 › 按 Wi‑Fi 切换模式：列出 Wi‑Fi 与要切到的模式（规则 / 全局）。
// Android 读 Wi‑Fi 名称前先说明为什么需要「位置信息」，同意后才向系统请求；拒绝时仍可手动输入名称，
// 只是读不到名称时不会切换。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/desktop/wifi_mode.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 请求权限前的说明。
const museWifiModePermissionExplain =
    'Android 只把 Wi‑Fi 名称提供给有「位置信息」权限的应用。穿云只用它判断你连的是哪个 Wi‑Fi，不读取、不保存你的位置。'
    '接下来系统会询问，请选「使用时允许」和「精确位置」。不允许也没关系：可以手动输入名称，只是读不到名称时不会自动切换。';

/// 自动连接页上的一行摘要。
String museWifiModeSummary(String raw) {
  final n = museParseWifiModes(raw).length;
  return n == 0 ? '关' : '$n 个 Wi‑Fi';
}

class MuseWifiModePage extends HookConsumerWidget {
  const MuseWifiModePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = ref.watch(MusePrefs.wifiModes);
    final modes = museParseWifiModes(raw);
    final input = useTextEditingController();
    final hint = useState<String?>(null);
    final blocked = useState(false);
    final reading = useState(false);
    final android = ref.watch(museOnDemandAndroidProvider);
    final toast = ref.read(inAppNotificationControllerProvider);

    Future<void> save(Map<String, MuseRouteMode> next) => ref.read(MusePrefs.wifiModes.notifier).update(museWifiModesToRaw(next));

    Future<void> add(String name) async {
      final n = name.trim();
      if (n.isEmpty) return;
      if (modes.containsKey(n)) {
        toast.showInfoToast('「$n」已在列表里');
        return;
      }
      await save({...modes, n: MuseRouteMode.global});
    }

    /// Android：先说明，同意后才请求；false = 没有权限（已显示说明与去设置的入口）。
    Future<bool> ensurePermission() async {
      if (!android) return true;
      final now = await ChuanyunPlatform.wifiPermission();
      if (now == 'granted') return true;
      if (!context.mounted) return false;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          key: const ValueKey('wifi_mode_permission_explain'),
          title: const Text('需要「位置信息」权限'),
          content: const Text(museWifiModePermissionExplain),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('暂不')),
            TextButton(key: const ValueKey('wifi_mode_permission_go'), onPressed: () => Navigator.pop(c, true), child: const Text('继续')),
          ],
        ),
      );
      if (go != true) {
        hint.value = museWifiPermissionHint;
        return false;
      }
      final answer = await ref.read(museWifiPermissionRequestProvider)();
      if (answer == null || answer == 'granted') {
        blocked.value = false;
        hint.value = null;
        return true;
      }
      blocked.value = answer == 'blocked';
      hint.value = museWifiPermissionHint;
      return false;
    }

    Future<void> addCurrent() async {
      if (!await ensurePermission()) return;
      reading.value = true;
      final r = await ref.read(museSsidReaderProvider)();
      reading.value = false;
      if (!r.ok) {
        hint.value = r.hint;
        return;
      }
      hint.value = null;
      if (r.ssid == null) {
        toast.showErrorToast('现在没有连接 Wi‑Fi');
        return;
      }
      await add(r.ssid!);
    }

    return MuseScaffold(
      title: '按 Wi‑Fi 切换模式',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '连上列表里的 Wi‑Fi 时自动切到所选模式，离开后恢复你原来的模式；你手动改了模式以你的为准。'
                '只在 Wi‑Fi 变化和回到穿云时检查，不在后台反复读取。想在某个 Wi‑Fi 下完全不走代理，请用「按需运行」。',
            children: [
              for (final e in modes.entries)
                MuseTile(
                  key: ValueKey('wifi_mode_ssid_${e.key}'),
                  leading: const Icon(Icons.wifi_outlined),
                  title: e.key,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<MuseRouteMode>(
                        key: ValueKey('wifi_mode_pick_${e.key}'),
                        showSelectedIcon: false,
                        segments: [for (final m in MuseRouteMode.values) ButtonSegment(value: m, label: Text(m.title))],
                        selected: {e.value},
                        onSelectionChanged: (s) => save({...modes, e.key: s.first}),
                      ),
                      IconButton(
                        key: ValueKey('wifi_mode_remove_${e.key}'),
                        tooltip: '移除',
                        icon: const Icon(Icons.delete_outlined),
                        onPressed: () => save({...modes}..remove(e.key)),
                      ),
                    ],
                  ),
                ),
              MuseTile(
                key: const ValueKey('wifi_mode_add_current'),
                leading: reading.value
                    ? const SizedBox.square(dimension: MuseIconSize.regular, child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke))
                    : const Icon(Icons.add_outlined),
                title: '添加当前 Wi‑Fi',
                onTap: reading.value ? null : addCurrent,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16, vertical: MuseSpace.s8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('wifi_mode_input'),
                        controller: input,
                        decoration: const InputDecoration(hintText: '输入 Wi‑Fi 名称', isDense: true),
                        onSubmitted: (v) async {
                          await add(v);
                          input.clear();
                        },
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('wifi_mode_add'),
                      onPressed: () async {
                        await add(input.text);
                        input.clear();
                      },
                      child: const Text('添加'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hint.value != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s24),
              child: Text(hint.value!, key: const ValueKey('wifi_mode_hint'), style: MuseType.caption(context).copyWith(color: MusePalette.orange)),
            ),
          if (android && blocked.value)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('wifi_mode_open_permission'),
                  onPressed: ChuanyunPlatform.openAppDetails,
                  child: const Text('去系统设置开启权限'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
