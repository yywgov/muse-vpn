// 穿云 1.11.0 - Android home-screen widget: tells it the node in use and its delay, only when one of
// them changed (the widget redraws on that and on connection changes, never on a timer).
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart' show museFreshDelay, museNodeName, museShownPickProvider, museStripFlags;
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What the widget shows for [group]'s pick: (node text, delay in ms or 0).
(String, int) museWidgetNode(OutboundGroup? group, {DateTime? since, String Function(String raw)? shown}) {
  final item = group?.items.where((e) => e.tag == group.selected).firstOrNull;
  if (item == null) return ('', 0);
  final full = museNodeName(item);
  final String text;
  if (item.isGroup) {
    final rawName = full.split(' → ').first.trim();
    final pick = item.groupSelectedTagDisplay.trim();
    text = pick.isEmpty ? museGroupName(rawName) : '${museGroupName(rawName)} · ${museStripFlags(shown?.call(pick) ?? pick)}';
  } else {
    text = museStripFlags(shown?.call(full) ?? full);
  }
  final delay = museFreshDelay(item, since);
  return (text, ConnectionConst.isValidDelay(delay) ? delay : 0);
}

final museWidgetSyncProvider = Provider<void>((ref) {
  (String, int)? last;
  void push() {
    final next = museWidgetNode(
      ref.read(museNodeGroupProvider).valueOrNull,
      since: ref.read(museConnectedSinceProvider).valueOrNull,
      shown: ref.read(museShownPickProvider),
    );
    if (next == last) return;
    last = next;
    ChuanyunPlatform.updateWidget(node: next.$1, delay: next.$2);
  }

  ref.listen(museNodeGroupProvider, (_, _) => push());
  ref.listen(museConnectedSinceProvider, (_, _) => push());
  push();
});
