// 穿云 1.3.0 - 节点 tab: the full node list (moved off 首页).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/node_style.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseNodesPage extends ConsumerWidget {
  const MuseNodesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1.6.0 C5: 卡片 uses the full width (more columns); 列表 stays a readable column
    final grid = MuseNodeLayout.fromKey(ref.watch(MusePrefs.nodeLayout)) == MuseNodeLayout.grid;
    return MuseScaffold(
      large: true,
      title: '节点',
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: grid ? double.infinity : MuseSize.nodeListMax),
          // key kept for the e2e driver's scroll steps
          child: const MuseNodeList(listKey: ValueKey('home_node_list'), pinCurrent: true),
        ),
      ),
    );
  }
}
