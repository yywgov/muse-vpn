// 穿云 1.12.0 - 从连接加的「仅本次」规则：只在内存里，断开连接即清空（不写入设置）。
// The lists themselves watch nothing (the config reads them, and must not pull in the
// connection state); [museTempRulesResetProvider], kept alive by the app, clears them on disconnect.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/quick_rules.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 仅本次：直连 / 走代理。
final museTempQuickRulesProvider = StateProvider<List<MuseQuickRule>>((ref) => const []);

/// 仅本次：走指定节点。
final museTempNodeRulesProvider = StateProvider<List<MuseNodeRule>>((ref) => const []);

/// Clears the 仅本次 rules when the connection ends.
final museTempRulesResetProvider = Provider<void>((ref) {
  ref.listen<bool>(serviceRunningProvider, (prev, running) {
    if (prev == true && !running) {
      ref.read(museTempQuickRulesProvider.notifier).state = const [];
      ref.read(museTempNodeRulesProvider.notifier).state = const [];
    }
  });
});
