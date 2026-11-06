// 穿云 1.12.0 - 订阅更新后对新增节点测一次速：更新成功且有新增节点时记下它们；只在已连接且
// 穿云在前台时测（一次，交给内核的测速队列）；在后台或未连接时只记着，等回到前台且已连接再测。
// 由事件触发（订阅更新、节点列表变化、回到前台），不加定时器、不轮询。开关在 订阅 › 更多。
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart' show museNodeName;
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Names of new nodes waiting for their first test.
final museNewNodesProvider = StateProvider<Set<String>>((ref) => const {});

/// Records [added] (node names of an update of the active subscription) when the switch is on.
void museNoteNewNodes(Ref ref, Iterable<String> added) {
  if (added.isEmpty || !ref.read(MusePrefs.testNewNodes)) return;
  final c = ref.read(museNewNodesProvider.notifier);
  c.state = {...c.state, ...added};
}

/// The tags in [group] of the nodes named in [pending] (by tag or by the shown name).
List<String> museNewNodeTags(OutboundGroup? group, Set<String> pending) {
  if (group == null || pending.isEmpty) return const [];
  return [
    for (final e in group.items)
      if (!e.isGroup && (pending.contains(e.tag) || pending.contains(museNodeName(e)))) e.tag,
  ];
}

/// Whether to test now: connected, app in front, and the new nodes are in the running list.
bool museShouldTestNewNodes({required bool running, required bool foreground, required List<String> tags}) =>
    running && foreground && tags.isNotEmpty;

final museNewNodeTestProvider = Provider<void>((ref) {
  var busy = false;
  Future<void> maybeTest() async {
    if (busy) return;
    final pending = ref.read(museNewNodesProvider);
    if (pending.isEmpty) return;
    final state = WidgetsBinding.instance.lifecycleState;
    final foreground = state == null || state == AppLifecycleState.resumed;
    final tags = museNewNodeTags(ref.read(museNodeGroupProvider).valueOrNull, pending);
    if (!museShouldTestNewNodes(running: ref.read(museRunningProvider), foreground: foreground, tags: tags)) return;
    busy = true;
    ref.read(museNewNodesProvider.notifier).state = const {};
    try {
      final n = ref.read(proxiesOverviewNotifierProvider.notifier);
      for (final t in tags.take(200)) {
        try {
          await n.urlTest(t);
        } catch (_) {}
      }
    } finally {
      busy = false;
    }
  }

  ref.listen(museNewNodesProvider, (_, _) => unawaited(maybeTest()));
  ref.listen(museNodeGroupProvider, (_, _) => unawaited(maybeTest()));
  ref.listen<bool>(museRunningProvider, (_, _) => unawaited(maybeTest()));
  AppLifecycleListener? life;
  try {
    life = AppLifecycleListener(onResume: () => unawaited(maybeTest()));
  } catch (_) {}
  ref.onDispose(() => life?.dispose());
});
