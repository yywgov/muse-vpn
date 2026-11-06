// 穿云 1.3.0 - 节点 tab: the full node list (moved off 首页). 1.10.0: no 当前节点 card above it.
// 1.11.0: A 双列卡片 (node_rows.dart MuseNodeCard / MuseNodeModeBar).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseNodesPage extends ConsumerWidget {
  const MuseNodesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1.11.0: the A 双列卡片 layout uses the full width (more columns on a wide window)
    return const MuseScaffold(
      large: true,
      title: '节点',
      // key kept for the e2e driver's scroll steps
      body: MuseNodeList(listKey: ValueKey('home_node_list')),
    );
  }
}
