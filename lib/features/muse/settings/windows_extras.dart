// 穿云 1.6.0 C8 - Windows settings pages: 按需运行 (Wi‑Fi list) and 快捷键 (record / clear each
// global hotkey, master switch). Opened from 设置 › 电脑. 1.6.0 C9: 按需运行 is also Android's
// (设置 › 通用); there it asks for 「位置信息」 first and explains when it is refused.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void _toast(WidgetRef ref, String text, {bool error = false}) {
  try {
    final n = ref.read(inAppNotificationControllerProvider);
    error ? n.showErrorToast(text) : n.showSuccessToast(text);
  } catch (_) {}
}

// ======================================================================= 按需运行

class MuseOnDemandPage extends HookConsumerWidget {
  const MuseOnDemandPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(MusePrefs.onDemand);
    final raw = ref.watch(MusePrefs.wifiRules);
    final ssids = museOnDemandSsids(raw);
    final input = useTextEditingController();
    final hint = useState<String?>(null);
    final reading = useState(false);
    final android = ref.watch(museOnDemandAndroidProvider);
    // 「不再询问」 after a refusal: only the app's settings page can grant it now
    final blocked = useState(false);

    /// Android: asks for 「位置信息」; false (with the explanation shown) when refused.
    Future<bool> ensurePermission() async {
      if (!android) return true;
      final answer = await ref.read(museWifiPermissionRequestProvider)();
      if (answer == null || answer == 'granted') {
        blocked.value = false;
        if (hint.value == museWifiPermissionHint) hint.value = null;
        return true;
      }
      blocked.value = answer == 'blocked';
      hint.value = museWifiPermissionHint;
      return false;
    }

    useEffect(() {
      if (android && on) {
        ChuanyunPlatform.wifiPermission().then((p) {
          if (context.mounted && p != null && p != 'granted') hint.value = museWifiPermissionHint;
        });
      }
      return null;
    }, const []);

    Future<void> save(List<String> list) =>
        ref.read(MusePrefs.wifiRules.notifier).update(museOnDemandWithSsids(raw, list));

    Future<void> add(String name) async {
      final n = name.trim();
      if (n.isEmpty) return;
      if (ssids.contains(n)) {
        _toast(ref, '「$n」已在列表里');
        return;
      }
      await save([...ssids, n]);
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
        _toast(ref, '现在没有连接 Wi‑Fi', error: true);
        return;
      }
      await add(r.ssid!);
    }

    return MuseScaffold(
      title: '按需运行',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: android
                ? '连上列表里的 Wi‑Fi（比如家里、公司）时自动暂停连接，离开后自动恢复。手动点了「连接」或「断开」以你的操作为准。'
                      '需要「位置信息」权限才能读到 Wi‑Fi 名称；穿云在后台时 Android 可能不提供，回到穿云时会立即检查。'
                : '连上列表里的 Wi‑Fi（比如家里、公司）时自动暂停连接，离开后自动恢复。手动点了「连接」或「断开」以你的操作为准。',
            children: [
              MuseSwitchTile(
                key: const ValueKey('on_demand_switch'),
                leading: const Icon(Icons.wifi_outlined),
                title: '按需运行',
                value: on,
                onChanged: (v) async {
                  if (v && !await ensurePermission()) return;
                  await ref.read(MusePrefs.onDemand.notifier).update(v);
                },
              ),
            ],
          ),
          MuseSection(
            header: '暂停连接的 Wi‑Fi',
            children: [
              for (final s in ssids)
                MuseTile(
                  key: ValueKey('on_demand_ssid_$s'),
                  leading: const Icon(Icons.wifi_lock_outlined),
                  title: s,
                  trailing: IconButton(
                    tooltip: '移除',
                    icon: const Icon(Icons.delete_outlined),
                    onPressed: () => save([
                      for (final x in ssids)
                        if (x != s) x,
                    ]),
                  ),
                ),
              MuseTile(
                key: const ValueKey('on_demand_add_current'),
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
                        key: const ValueKey('on_demand_input'),
                        controller: input,
                        decoration: const InputDecoration(hintText: '输入 Wi‑Fi 名称', isDense: true),
                        onSubmitted: (v) async {
                          await add(v);
                          input.clear();
                        },
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('on_demand_add'),
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
          // shown right away (a section footer would sit behind its ⓘ)
          if (hint.value != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s24),
              child: Text(
                hint.value!,
                key: const ValueKey('on_demand_hint'),
                style: MuseType.caption(context).copyWith(color: MusePalette.orange),
              ),
            ),
          if (android && blocked.value)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('on_demand_open_permission'),
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

// ======================================================================= 快捷键

class MuseHotkeysPage extends ConsumerWidget {
  const MuseHotkeysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(MusePrefs.hotkeysOn);
    final bindings = museParseHotkeys(ref.watch(MusePrefs.hotkeys));
    return MuseScaffold(
      title: '快捷键',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '全局快捷键在穿云隐藏到托盘时也能用。每个快捷键至少要带 Ctrl、Alt 或 Win 中的一个。',
            children: [
              MuseSwitchTile(
                key: const ValueKey('hotkeys_switch'),
                leading: const Icon(Icons.keyboard_outlined),
                title: '启用全局快捷键',
                value: on,
                onChanged: (v) => ref.read(MusePrefs.hotkeysOn.notifier).update(v),
              ),
            ],
          ),
          MuseSection(
            children: [
              for (final a in MuseHotkeyAction.values)
                MuseTile(
                  key: ValueKey('hotkey_${a.key}'),
                  title: a.title,
                  trailing: Text(bindings[a]?.label ?? '未设置'),
                  chevron: true,
                  onTap: () => museRecordHotkey(context, ref, a),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Records a new combination for [action] (the registered keys are released while the dialog is open).
Future<void> museRecordHotkey(BuildContext context, WidgetRef ref, MuseHotkeyAction action) async {
  final recording = ref.read(museHotkeyRecordingProvider.notifier);
  recording.state = true;
  try {
    final result = await showDialog<_RecordResult>(
      context: context,
      builder: (_) => _HotkeyRecorder(action: action, bindings: museParseHotkeys(ref.read(MusePrefs.hotkeys))),
    );
    if (result == null) return;
    final bindings = Map.of(museParseHotkeys(ref.read(MusePrefs.hotkeys)));
    if (result.clear) {
      bindings.remove(action);
    } else if (result.key != null) {
      bindings[action] = result.key!;
    }
    await ref.read(MusePrefs.hotkeys.notifier).update(museHotkeysToRaw(bindings));
  } finally {
    recording.state = false;
  }
}

class _RecordResult {
  const _RecordResult({this.key, this.clear = false});

  final MuseHotkey? key;
  final bool clear;
}

class _HotkeyRecorder extends StatefulWidget {
  const _HotkeyRecorder({required this.action, required this.bindings});

  final MuseHotkeyAction action;
  final Map<MuseHotkeyAction, MuseHotkey> bindings;

  @override
  State<_HotkeyRecorder> createState() => _HotkeyRecorderState();
}

class _HotkeyRecorderState extends State<_HotkeyRecorder> {
  MuseHotkey? _key;
  String? _problem;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    if (e.physicalKey == PhysicalKeyboardKey.escape && pressed.length <= 1) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final k = museHotkeyFromEvent(e.physicalKey, {...pressed, e.physicalKey});
    if (k == null) return KeyEventResult.handled;
    setState(() {
      _key = k;
      _problem = museHotkeyProblem(k, widget.action, widget.bindings);
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.bindings[widget.action];
    final shown = _key ?? current;
    return AlertDialog(
      key: const ValueKey('hotkey_recorder'),
      title: Text(widget.action.title),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_key == null ? '按下新的快捷键…' : '新的快捷键', style: MuseType.caption(context)),
            const SizedBox(height: MuseSpace.s8),
            Text(shown?.label ?? '未设置', key: const ValueKey('hotkey_recorder_value'), style: MuseType.title(context)),
            if (_problem != null) ...[
              const SizedBox(height: MuseSpace.s8),
              Text(
                _problem!,
                key: const ValueKey('hotkey_recorder_problem'),
                style: MuseType.caption(context).copyWith(color: MusePalette.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (current != null)
          TextButton(
            key: const ValueKey('hotkey_clear'),
            onPressed: () => Navigator.of(context).pop(const _RecordResult(clear: true)),
            child: const Text('清除'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          key: const ValueKey('hotkey_save'),
          onPressed: _key != null && _problem == null
              ? () => Navigator.of(context).pop(_RecordResult(key: _key))
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
