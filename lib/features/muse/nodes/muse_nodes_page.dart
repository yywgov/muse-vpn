// 穿云 1.3.0 - 节点 tab: the full node list (moved off 首页). 1.10.0: no 当前节点 card above it.
// 1.11.0: A 双列卡片 (node_rows.dart MuseNodeCard / MuseNodeModeBar).
// 1.20.2：订阅并入节点页——标题就是当前订阅（「订阅名 ▾」，点开订阅弹层）；没有订阅时这一页给「添加订阅」与导入方式。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/nodes/subs_sheet.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseNodesPage extends ConsumerWidget {
  const MuseNodesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(museHasProfileProvider) == false) {
      return const MuseScaffold(key: ValueKey('nodes_empty_page'), large: true, title: '节点', body: MuseNodesEmpty());
    }
    // 1.11.0: the A 双列卡片 layout uses the full width (more columns on a wide window)
    // 1.20.1：标题与搜索 / 测速 / ⋯ 在同一行（由列表画）
    return const MuseScaffold(
      large: true,
      showAppBar: false,
      title: '节点',
      // key kept for the e2e driver's scroll steps
      body: MuseNodeList(listKey: ValueKey('home_node_list'), title: '节点', subSwitcher: true),
    );
  }
}
