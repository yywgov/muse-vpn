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
import 'package:hiddify/features/muse/logic/wifi_actions.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show musePick;
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
  const MuseWifiModePage({super.key, this.embedded = false});

  /// 1.20.3：作为「Wi‑Fi 规则」页的下半部分（不带标题栏、不自带滚动）
  final bool embedded;

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

    final children = <Widget>[
      MuseSection(
        header: embedded ? '切换模式' : null,
        footer:
            '连上列表里的 Wi‑Fi 时自动切到所选模式，离开后恢复你原来的模式；你手动改了模式以你的为准。'
            '只在 Wi‑Fi 变化和回到穿云时检查，不在后台反复读取。',
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
                  IconButton(key: ValueKey('wifi_mode_remove_${e.key}'), tooltip: '移除', icon: const Icon(Icons.delete_outlined), onPressed: () => save({...modes}..remove(e.key))),
                ],
              ),
            ),
          MuseTile(
            key: const ValueKey('wifi_mode_add_current'),
            leading: reading.value
                ? const SizedBox.square(
                    dimension: MuseIconSize.regular,
                    child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                  )
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
          child: Text(
            hint.value!,
            key: const ValueKey('wifi_mode_hint'),
            style: MuseType.caption(context).copyWith(color: MusePalette.orange),
          ),
        ),
      if (android && blocked.value)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(key: const ValueKey('wifi_mode_open_permission'), onPressed: ChuanyunPlatform.openAppDetails, child: const Text('去系统设置开启权限')),
          ),
        ),
    ];
    if (embedded) return Column(key: const ValueKey('wifi_mode_embedded'), crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return MuseScaffold(
      title: '按 Wi‑Fi 切换模式',
      body: MuseGroupedBody(children: children),
    );
  }
}

/// 1.20.3：设置 › 启动与断线 ›「Wi‑Fi 规则」。第 2 轮：一个名单，每个 Wi‑Fi 选一个动作（暂停连接 / 切到规则模式 /
/// 切到全局模式），同一个 Wi‑Fi 只能有一个动作，不再有「两边都列了谁说了算」。存储见 logic/wifi_actions.dart。
const museWifiRulesTitle = 'Wi‑Fi 规则';

/// 页面说明（折叠在名单的 ⓘ 里）。
const museWifiRulesFooter = '连上名单里的 Wi‑Fi 时按所选动作处理，离开后恢复：暂停的连接自动重新连上，切换的模式改回原来的。你手动点了连接 / 断开或改了模式，以你的操作为准。';

/// 「按需运行」开关下的一行：它只管「暂停连接」这个动作（切换模式不受它影响，和以前一样）。
const museWifiRulesSwitchSubtitle = '关着时「暂停连接」不生效，切换模式照常';

class MuseWifiRulesPage extends HookConsumerWidget {
  const MuseWifiRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(MusePrefs.onDemand);
    final acts = museWifiActions(rulesRaw: ref.watch(MusePrefs.wifiRules), modesRaw: ref.watch(MusePrefs.wifiModes), onDemandOn: on);
    final input = useTextEditingController();
    final hint = useState<String?>(null);
    final blocked = useState(false);
    final reading = useState(false);
    final android = ref.watch(museOnDemandAndroidProvider);
    final toast = ref.read(inAppNotificationControllerProvider);
    final mt = MuseTheme.of(context);

    Future<void> save(Map<String, MuseWifiAct> next) => museSaveWifiActions(ref.read, next);

    Future<MuseWifiAct?> pickAct(String ssid, MuseWifiAct? current) => musePick<MuseWifiAct>(context, '连上「$ssid」时', [for (final a in MuseWifiAct.values) (a, a.title)], current ?? MuseWifiAct.pause);

    Future<void> add(String name) async {
      final n = name.trim();
      if (n.isEmpty) return;
      if (acts.containsKey(n)) {
        toast.showInfoToast('「$n」已在名单里');
        return;
      }
      final a = await pickAct(n, null);
      if (a == null) return;
      await save({...acts, n: a});
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
      key: const ValueKey('wifi_rules_page'),
      title: museWifiRulesTitle,
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('on_demand_switch'),
                leading: const Icon(Icons.wifi_off_outlined),
                title: '按需运行',
                subtitle: museWifiRulesSwitchSubtitle,
                value: on,
                onChanged: (v) async {
                  if (v && !await ensurePermission()) return;
                  await ref.read(MusePrefs.onDemand.notifier).update(v);
                },
              ),
            ],
          ),
          MuseSection(
            header: 'Wi‑Fi',
            footer: museWifiRulesFooter,
            children: [
              for (final e in acts.entries)
                MuseTile(
                  key: ValueKey('wifi_rule_${e.key}'),
                  leading: Icon(e.value == MuseWifiAct.pause ? Icons.wifi_lock_outlined : Icons.alt_route_outlined),
                  title: e.key,
                  subtitle: e.value == MuseWifiAct.pause && !on ? '按需运行关着，暂不生效' : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.value.title, key: ValueKey('wifi_rule_act_${e.key}')),
                      IconButton(key: ValueKey('wifi_rule_remove_${e.key}'), tooltip: '移除', icon: const Icon(Icons.delete_outlined), onPressed: () => save({...acts}..remove(e.key))),
                    ],
                  ),
                  onTap: () async {
                    final a = await pickAct(e.key, e.value);
                    if (a != null && a != e.value) await save({...acts, e.key: a});
                  },
                ),
              MuseTile(
                key: const ValueKey('wifi_rule_add_current'),
                leading: reading.value
                    ? const SizedBox.square(
                        dimension: MuseIconSize.regular,
                        child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                      )
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
                        key: const ValueKey('wifi_rule_input'),
                        controller: input,
                        decoration: const InputDecoration(hintText: '输入 Wi‑Fi 名称', isDense: true),
                        onSubmitted: (v) async {
                          await add(v);
                          input.clear();
                        },
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('wifi_rule_add'),
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
              padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context) + MuseSpace.s16),
              child: Text(
                hint.value!,
                key: const ValueKey('wifi_rule_hint'),
                style: MuseType.caption(context).copyWith(color: MusePalette.orange),
              ),
            ),
          if (android && blocked.value)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context)),
              child: const Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(key: ValueKey('wifi_rule_open_permission'), onPressed: ChuanyunPlatform.openAppDetails, child: Text('去系统设置开启权限')),
              ),
            ),
          if (acts.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(MuseSpace.page(context) + MuseSpace.s16, MuseSpace.s4, MuseSpace.page(context) + MuseSpace.s16, 0),
              child: Text(
                '还没有 Wi‑Fi。添加后选连上它时要做什么。',
                key: const ValueKey('wifi_rule_empty'),
                style: MuseType.caption(context).copyWith(color: mt.text2),
              ),
            ),
        ],
      ),
    );
  }
}
