// 穿云 1.3.0 - 节点 tab: the full node list (moved off 首页).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';

class MuseNodesPage extends StatelessWidget {
  const MuseNodesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MuseScaffold(
      large: true,
      title: '节点',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          // key kept for the e2e driver's scroll steps
          child: const MuseNodeList(listKey: ValueKey('home_node_list')),
        ),
      ),
    );
  }
}
