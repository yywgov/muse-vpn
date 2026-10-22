// 穿云 1.4.1 - 命令行参数 / 控制链接: `Chuanyun.exe --connect [--node=名称]`, `--disconnect`, and the
// same as links `chuanyun://connect?node=名称` / `chuanyun://disconnect` (these also reach an
// already running 穿云: Windows hands the link to the open window). A node is matched by its tag
// or shown name; an unknown node just connects with the current one.
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/home/node_memory.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart' show museNodeName;
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The arguments 穿云 was started with (set by main).
MuseCliArgs museLaunchArgs = const MuseCliArgs();

/// Carries out [args] once the app is up.
Future<void> museApplyLaunchControl(Ref ref, MuseCliArgs args) async {
  if (args.isEmpty || (!args.connect && !args.disconnect)) return;
  try {
    // wait for the connection state to be known (start-up)
    for (var i = 0; i < 20 && ref.read(connectionNotifierProvider).valueOrNull == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final state = ref.read(connectionNotifierProvider).valueOrNull;
    final notifier = ref.read(connectionNotifierProvider.notifier);
    if (args.disconnect) {
      if (state is Connected) {
        ChuanyunPlatform.recordDisconnect('命令行/链接：断开');
        await notifier.toggleConnection();
      }
      return;
    }
    final node = args.node?.trim();
    if (node != null && node.isNotEmpty) {
      final group = ref.read(museNodeGroupProvider).valueOrNull;
      final match = group?.items.where((e) => !e.isGroup && (e.tag == node || museNodeName(e) == node)).firstOrNull;
      if (group != null && match != null) {
        if (ref.read(museRunningProvider)) {
          await museSelectNodeFrom(ref, group.tag, match.tag);
        } else {
          final profileId = ref.read(museActiveProfileIdProvider);
          if (profileId != null) {
            await ref.read(Preferences.museLastNodes.notifier).update(museRememberNode(ref.read(Preferences.museLastNodes), profileId, match.tag));
          }
        }
      }
    }
    if (state is Disconnected) {
      ChuanyunPlatform.recordDisconnect('命令行/链接：连接${node == null ? '' : '（$node）'}');
      await notifier.toggleConnection();
    }
  } catch (_) {}
}

/// Runs the start-up arguments once.
final museLaunchControlProvider = Provider<void>((ref) {
  final args = museLaunchArgs;
  museLaunchArgs = const MuseCliArgs();
  if (!args.isEmpty) unawaited(Future<void>.delayed(const Duration(seconds: 2), () => museApplyLaunchControl(ref, args)));
});
