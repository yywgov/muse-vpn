// 穿云 1.11.0 - Android home-screen widget: tells it the node in use and its delay, only when one of
// them changed (the widget redraws on that and on connection changes, never on a timer).
// Part of 穿云 (GPLv3).

import 'package:flutter/foundation.dart' show listEquals;
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart' show museParseFavorites;
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

/// 1.16.0 R25: the widget's 常用节点 — the first [max] favourite nodes in the list's order
/// (tag, shown name). Groups and nodes no longer in the subscription are skipped.
List<(String, String)> museWidgetFavs(OutboundGroup? group, Set<String> favorites, {int max = 3, String Function(String raw)? shown}) {
  if (group == null || favorites.isEmpty) return const [];
  final out = <(String, String)>[];
  for (final item in group.items) {
    if (out.length >= max) break;
    if (item.isGroup || !favorites.contains(item.tag)) continue;
    final full = museNodeName(item);
    out.add((item.tag, museStripFlags(shown?.call(full) ?? full)));
  }
  return out;
}

final museWidgetSyncProvider = Provider<void>((ref) {
  (String, int)? last;
  List<(String, String)>? lastFavs;
  void push() {
    final group = ref.read(museNodeGroupProvider).valueOrNull;
    final shown = ref.read(museShownPickProvider);
    final next = museWidgetNode(group, since: ref.read(museConnectedSinceProvider).valueOrNull, shown: shown);
    final favs = museWidgetFavs(group, museParseFavorites(ref.read(Preferences.museFavoriteNodes)), shown: shown);
    // sent only when something the widget shows changed (no timer)
    if (next == last && lastFavs != null && listEquals(favs, lastFavs)) return;
    last = next;
    lastFavs = favs;
    ChuanyunPlatform.updateWidget(node: next.$1, delay: next.$2, favs: favs);
  }

  ref.listen(museNodeGroupProvider, (_, _) => push());
  ref.listen(museConnectedSinceProvider, (_, _) => push());
  ref.listen(Preferences.museFavoriteNodes, (_, _) => push());
  push();
});
