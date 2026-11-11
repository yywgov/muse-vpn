// 穿云 1.6.0 C8 - Windows settings page: 快捷键 (record / clear each global hotkey, master switch).
// Opened from 设置 › 电脑. 1.20.3: the old 按需运行 page (no entry since the 1.20.3 Wi‑Fi 规则 page)
// was removed; 按需运行 now lives on 设置 › 启动与断线 › Wi‑Fi 规则 (wifi_mode_page.dart).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ======================================================================= 快捷键

/// 1.17.0 B13
const museHotkeyTakenText = '这个组合已被其他程序占用，暂未生效，换一个吧';

class MuseHotkeysPage extends ConsumerWidget {
  const MuseHotkeysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(MusePrefs.hotkeysOn);
    final bindings = museParseHotkeys(ref.watch(MusePrefs.hotkeys));
    final taken = ref.watch(museHotkeysTakenProvider);
    return MuseScaffold(
      title: '快捷键',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '全局快捷键在穿云隐藏到托盘时也能用。默认一个都没设置，不会和其他软件抢按键；每个快捷键至少要带 Ctrl、Alt 或 Win 中的一个。关掉开关即全部停用。',
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
                  // 1.17.0 B13: another program already holds this combination
                  subtitle: on && taken.contains(a) ? museHotkeyTakenText : null,
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
