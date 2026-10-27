// 穿云 1.6.0 C8 - 全局快捷键 (Windows): 连接/断开、显示/隐藏窗口、切换规则/全局、测延迟、更新全部订阅、
// 复制终端代理命令、退出. Nothing is bound by default (so nothing is registered and start-up does no
// extra work); each binding needs Ctrl, Alt or Win, may not collide with another one or with a
// common system shortcut, and the whole feature has an on/off switch. Registered with
// hotkey_manager (MIT) only on Windows, after the first frame. Every action calls the same
// notifier methods as the buttons in the window (desktop_actions.dart).
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/desktop/desktop_actions.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart' as hk;

enum MuseHotkeyAction {
  toggleConnection('connection', '连接 / 断开'),
  showWindow('window', '显示 / 隐藏窗口'),
  toggleMode('mode', '切换 规则 / 全局'),
  urlTest('urltest', '测延迟'),
  updateProfiles('update', '更新全部订阅'),
  copyEnv('env', '复制终端代理命令'),
  quit('quit', '退出');

  const MuseHotkeyAction(this.key, this.title);

  final String key;
  final String title;

  static MuseHotkeyAction? fromKey(String key) => values.where((e) => e.key == key).firstOrNull;

  MuseDesktopAction get desktopAction => switch (this) {
    toggleConnection => MuseDesktopAction.toggleConnection,
    showWindow => MuseDesktopAction.toggleWindow,
    toggleMode => MuseDesktopAction.toggleMode,
    urlTest => MuseDesktopAction.urlTest,
    updateProfiles => MuseDesktopAction.updateProfiles,
    copyEnv => MuseDesktopAction.copyEnv,
    quit => MuseDesktopAction.quit,
  };
}

/// One key combination: modifiers + one non-modifier key (USB HID usage of the physical key).
class MuseHotkey {
  const MuseHotkey({this.ctrl = false, this.alt = false, this.shift = false, this.win = false, required this.usage});

  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool win;
  final int usage;

  PhysicalKeyboardKey get physicalKey => PhysicalKeyboardKey(usage);

  bool get hasModifier => ctrl || alt || win;

  @override
  bool operator ==(Object other) =>
      other is MuseHotkey &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.shift == shift &&
      other.win == win &&
      other.usage == usage;

  @override
  int get hashCode => Object.hash(ctrl, alt, shift, win, usage);

  /// "ctrl+alt+0x7001e"
  String toRaw() =>
      [if (ctrl) 'ctrl', if (alt) 'alt', if (shift) 'shift', if (win) 'win', '0x${usage.toRadixString(16)}'].join('+');

  static MuseHotkey? parse(String raw) {
    final parts = raw.split('+').map((e) => e.trim().toLowerCase()).toList();
    if (parts.isEmpty) return null;
    final last = parts.removeLast();
    final usage = last.startsWith('0x') ? int.tryParse(last.substring(2), radix: 16) : int.tryParse(last);
    if (usage == null) return null;
    for (final p in parts) {
      if (!const {'ctrl', 'alt', 'shift', 'win'}.contains(p)) return null;
    }
    return MuseHotkey(
      ctrl: parts.contains('ctrl'),
      alt: parts.contains('alt'),
      shift: parts.contains('shift'),
      win: parts.contains('win'),
      usage: usage,
    );
  }

  /// "Ctrl + Alt + K"
  String get label =>
      [if (ctrl) 'Ctrl', if (alt) 'Alt', if (shift) 'Shift', if (win) 'Win', museKeyLabel(physicalKey)].join(' + ');
}

/// Keys that can be bound: letters, digits, F1–F12 and a few named keys.
final Map<PhysicalKeyboardKey, String> museBindableKeys = {
  for (var i = 0; i < 26; i++) PhysicalKeyboardKey(0x00070004 + i): String.fromCharCode(0x41 + i),
  for (var i = 0; i < 9; i++) PhysicalKeyboardKey(0x0007001e + i): '${i + 1}',
  PhysicalKeyboardKey.digit0: '0',
  for (var i = 0; i < 12; i++) PhysicalKeyboardKey(0x0007003a + i): 'F${i + 1}',
  PhysicalKeyboardKey.space: 'Space',
  PhysicalKeyboardKey.enter: 'Enter',
  PhysicalKeyboardKey.home: 'Home',
  PhysicalKeyboardKey.end: 'End',
  PhysicalKeyboardKey.pageUp: 'PageUp',
  PhysicalKeyboardKey.pageDown: 'PageDown',
  PhysicalKeyboardKey.arrowUp: '↑',
  PhysicalKeyboardKey.arrowDown: '↓',
  PhysicalKeyboardKey.arrowLeft: '←',
  PhysicalKeyboardKey.arrowRight: '→',
  PhysicalKeyboardKey.minus: '-',
  PhysicalKeyboardKey.equal: '=',
  PhysicalKeyboardKey.comma: ',',
  PhysicalKeyboardKey.period: '.',
  PhysicalKeyboardKey.slash: '/',
  PhysicalKeyboardKey.backquote: '`',
};

String museKeyLabel(PhysicalKeyboardKey key) => museBindableKeys[key] ?? '?';

bool museIsModifierKey(PhysicalKeyboardKey key) => {
  PhysicalKeyboardKey.controlLeft,
  PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.altLeft,
  PhysicalKeyboardKey.altRight,
  PhysicalKeyboardKey.shiftLeft,
  PhysicalKeyboardKey.shiftRight,
  PhysicalKeyboardKey.metaLeft,
  PhysicalKeyboardKey.metaRight,
}.contains(key);

/// System / everyday shortcuts that are refused.
final Set<MuseHotkey> museReservedHotkeys = {
  for (final k in ['A', 'C', 'V', 'X', 'Z', 'Y', 'S', 'F', 'W', 'T', 'N', 'P', 'R', 'Q'])
    MuseHotkey(ctrl: true, usage: 0x00070004 + k.codeUnitAt(0) - 0x41),
  MuseHotkey(ctrl: true, alt: true, usage: PhysicalKeyboardKey.delete.usbHidUsage),
  MuseHotkey(alt: true, usage: PhysicalKeyboardKey.f4.usbHidUsage),
  MuseHotkey(alt: true, usage: PhysicalKeyboardKey.tab.usbHidUsage),
  for (final k in ['L', 'D', 'E', 'R', 'I', 'S', 'V', 'X', 'A', 'M'])
    MuseHotkey(win: true, usage: 0x00070004 + k.codeUnitAt(0) - 0x41),
};

/// Why [key] can't be used for [action] (null = fine).
String? museHotkeyProblem(MuseHotkey key, MuseHotkeyAction action, Map<MuseHotkeyAction, MuseHotkey> bindings) {
  if (!museBindableKeys.containsKey(key.physicalKey)) return '不支持这个键，请用字母、数字或 F1–F12';
  if (!key.hasModifier) return '至少要带 Ctrl、Alt 或 Win 中的一个';
  if (museReservedHotkeys.contains(key)) return '${key.label} 是系统或常用快捷键，换一个吧';
  for (final e in bindings.entries) {
    if (e.key != action && e.value == key) return '已被「${e.key.title}」使用';
  }
  return null;
}

/// The combination a key-down [key] makes while [pressed] keys are held (null = only modifiers so far).
MuseHotkey? museHotkeyFromEvent(PhysicalKeyboardKey key, Set<PhysicalKeyboardKey> pressed) {
  if (museIsModifierKey(key)) return null;
  bool any(List<PhysicalKeyboardKey> keys) => keys.any(pressed.contains);
  return MuseHotkey(
    ctrl: any(const [PhysicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlRight]),
    alt: any(const [PhysicalKeyboardKey.altLeft, PhysicalKeyboardKey.altRight]),
    shift: any(const [PhysicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftRight]),
    win: any(const [PhysicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaRight]),
    usage: key.usbHidUsage,
  );
}

/// `{"connection": "ctrl+alt+0x7001e"}`; unknown actions / broken entries are dropped.
Map<MuseHotkeyAction, MuseHotkey> museParseHotkeys(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final out = <MuseHotkeyAction, MuseHotkey>{};
    for (final e in m.entries) {
      final a = MuseHotkeyAction.fromKey(e.key);
      final k = e.value is String ? MuseHotkey.parse(e.value as String) : null;
      if (a != null && k != null) out[a] = k;
    }
    return out;
  } catch (_) {
    return const {};
  }
}

String museHotkeysToRaw(Map<MuseHotkeyAction, MuseHotkey> bindings) => bindings.isEmpty
    ? ''
    : jsonEncode({
        for (final a in MuseHotkeyAction.values)
          if (bindings[a] != null) a.key: bindings[a]!.toRaw(),
      });

/// What actually registers the keys (hotkey_manager on Windows; a fake in tests).
abstract class MuseHotkeyBackend {
  Future<void> apply(Map<MuseHotkeyAction, MuseHotkey> bindings, void Function(MuseHotkeyAction action) onPressed);
}

class _SystemHotkeyBackend implements MuseHotkeyBackend {
  bool _touched = false;

  @override
  Future<void> apply(
    Map<MuseHotkeyAction, MuseHotkey> bindings,
    void Function(MuseHotkeyAction action) onPressed,
  ) async {
    // nothing bound and nothing registered before: don't even load the plugin
    if (bindings.isEmpty && !_touched) return;
    _touched = true;
    await hk.hotKeyManager.unregisterAll();
    for (final e in bindings.entries) {
      final k = e.value;
      final key = hk.HotKey(
        identifier: 'muse-${e.key.key}',
        key: k.physicalKey,
        modifiers: [
          if (k.ctrl) hk.HotKeyModifier.control,
          if (k.alt) hk.HotKeyModifier.alt,
          if (k.shift) hk.HotKeyModifier.shift,
          if (k.win) hk.HotKeyModifier.meta,
        ],
      );
      try {
        // the Windows side needs a virtual-key code: keys without one throw here and are skipped
        key.logicalKey;
        await hk.hotKeyManager.register(key, keyDownHandler: (_) => onPressed(e.key));
      } catch (_) {}
    }
  }
}

final museHotkeyBackendProvider = Provider<MuseHotkeyBackend>((_) => _SystemHotkeyBackend());

/// true while 设置 records a new combination (the registered keys are released meanwhile)
final museHotkeyRecordingProvider = StateProvider<bool>((_) => false);

/// tests run the provider off Windows
final museHotkeysForceProvider = Provider<bool>((_) => false);

/// What the hotkeys do (desktop_actions.dart); overridable in tests.
final museHotkeyHandlerProvider = Provider<void Function(MuseHotkeyAction action)>(
  (ref) =>
      (a) => unawaited(museRunDesktopAction(ref, a.desktopAction, fromHotkey: true)),
);

/// The bindings in effect right now (empty while off / recording).
Map<MuseHotkeyAction, MuseHotkey> museActiveHotkeys({required bool on, required bool recording, required String raw}) =>
    on && !recording ? museParseHotkeys(raw) : const {};

final museHotkeysProvider = Provider<void>((ref) {
  if (!PlatformUtils.isWindows && !ref.watch(museHotkeysForceProvider)) return;
  final active = museActiveHotkeys(
    on: ref.watch(MusePrefs.hotkeysOn),
    recording: ref.watch(museHotkeyRecordingProvider),
    raw: ref.watch(MusePrefs.hotkeys),
  );
  final backend = ref.read(museHotkeyBackendProvider);
  final handler = ref.read(museHotkeyHandlerProvider);
  unawaited(Future<void>.microtask(() => backend.apply(active, handler)).catchError((_) {}));
});
