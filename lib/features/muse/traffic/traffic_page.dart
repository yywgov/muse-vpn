// 穿云 1.22.0 F1-A - 流量: 底栏第三栏。「这条流量走哪」的看、改、查放在一处：
//   连接 = 原 设置 › 活动（实时 / 日志 / DNS / 统计，只建当前这一块，只跑它的数据流）
//   规则 = 原 设置 › 分流规则（分流模式、我的规则、规则来源、规则测试）
// 地址 /traffic?seg=connections|rules[&tab=connections|logs|dns|stats]；
// 旧地址 /settings/activity?tab=…、/settings/routing-options/…、/nodes/routing-options/… 都跳到这里，功能不删。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/muse/activity/activity_page.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show MuseRoutingPage, MuseRoutingMoreMenu;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_segmented.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 流量页的两段。
enum MuseTrafficSeg {
  connections('connections', '连接'),
  rules('rules', '规则');

  const MuseTrafficSeg(this.key, this.title);

  /// the `seg` query parameter
  final String key;
  final String title;

  static MuseTrafficSeg fromKey(String? key) => key == 'rules' ? MuseTrafficSeg.rules : MuseTrafficSeg.connections;
}

/// Route name / path of 流量 (a shell branch of its own).
const museTrafficRoute = 'traffic';
const museTrafficPath = '/traffic';

/// 打开流量页的「规则」段。
const museTrafficRulesLocation = '$museTrafficPath?seg=rules';

/// 流量页的标题（「连接」里四块的页标题也用它）。
const museTrafficTitle = '流量';

/// 「连接」段里第二排分段的叫法：第一块是实时连接，叫「实时」，免得和上面的「连接」重名。
String museTrafficTabLabel(MuseActivityTab t) => t == MuseActivityTab.connections ? '实时' : t.title;

class MuseTrafficPage extends HookConsumerWidget {
  const MuseTrafficPage({super.key, this.seg = MuseTrafficSeg.connections, this.tab = MuseActivityTab.connections});

  final MuseTrafficSeg seg;

  /// the block of 连接 that opens first
  final MuseActivityTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = useState(seg);
    useEffect(() {
      current.value = seg;
      return null;
    }, [seg, tab]);

    final segmented = MuseSegmented<MuseTrafficSeg>(
      key: const ValueKey('traffic_seg'),
      values: MuseTrafficSeg.values,
      selected: current.value,
      label: (s) => s.title,
      onChanged: (s) => current.value = s,
    );
    return MuseTrafficScope(
      segmented: segmented,
      child: switch (current.value) {
        MuseTrafficSeg.connections => MuseActivityPage(key: const ValueKey('traffic_connections'), initial: tab),
        MuseTrafficSeg.rules => MuseScaffold(
          key: const ValueKey('traffic_rules'),
          title: museTrafficTitle,
          actions: const [MuseRoutingMoreMenu()],
          body: MuseRoutingPage(
            embedded: true,
            header: Padding(
              padding: EdgeInsets.fromLTRB(MuseSpace.page(context), 0, MuseSpace.page(context), MuseSpace.s8),
              child: segmented,
            ),
          ),
        ),
      },
    );
  }
}

/// 1.22.0：活动的四块放在流量页里时，页标题改叫「流量」，顶上多一排「连接 / 规则」。
class MuseTrafficScope extends InheritedWidget {
  const MuseTrafficScope({super.key, required this.segmented, required super.child});

  /// the 连接 / 规则 switch
  final Widget segmented;

  static MuseTrafficScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MuseTrafficScope>();

  @override
  bool updateShouldNotify(MuseTrafficScope old) => old.segmented != segmented;
}

/// 跳到流量页的「规则」段（原 设置 › 分流规则）。
void museGoTrafficRules(BuildContext context) => context.go(museTrafficRulesLocation);
