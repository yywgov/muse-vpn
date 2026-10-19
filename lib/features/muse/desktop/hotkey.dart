// 穿云 1.2.3 Windows - 全局快捷键: Ctrl+Alt+P connects / disconnects from anywhere, like the
// tray's 连接/断开. On by default; 设置 › Windows switches it off. A key already taken by another
// app just leaves the shortcut unregistered.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/services.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// Shown next to the switch in 设置.
const museHotkeyLabel = 'Ctrl + Alt + P';

/// Whether Ctrl+Alt+P is registered with the plugin right now.
bool _museHotkeyRegistered = false;

final museHotkeyProvider = Provider<void>((ref) {
  if (!PlatformUtils.isWindows) return;
  final on = ref.watch(Preferences.museHotkey);
  final hotKey = HotKey(
    identifier: 'chuanyun-toggle',
    key: PhysicalKeyboardKey.keyP,
    modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );
  var busy = false;
  Future<void> register() async {
    // 1.2.4: never unregister a key that is not registered: the Windows plugin looks it up with
    // std::map::at and an unknown id takes the whole app down (1.2.3 crashed at start-up)
    if (_museHotkeyRegistered) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (_) {}
      _museHotkeyRegistered = false;
    }
    if (!on) return;
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) async {
          if (busy) return;
          busy = true;
          try {
            await ref.read(connectionNotifierProvider.notifier).toggleConnection();
          } catch (_) {
            // the connection notifier reports its own failures
          } finally {
            busy = false;
          }
        },
      );
      _museHotkeyRegistered = true;
    } catch (_) {
      // taken by another app: no shortcut, nothing else changes
    }
  }

  register();
  ref.onDispose(() {
    if (!_museHotkeyRegistered) return;
    _museHotkeyRegistered = false;
    hotKeyManager.unregister(hotKey).catchError((_) {});
  });
});
