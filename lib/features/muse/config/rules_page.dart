// 穿云 1.9.0 #17 - 「规则」: 分流 and 订阅覆写 on one page (two tabs).
// 1.10.0: the only entry is 订阅 › 规则 (plus settings search); 编辑覆写 JSON sits in the ⋯ menu
// at the top right (it was 「高级」 inside each subscription's 覆写), 去广告 is on the 分流 tab.
// 1.20.2：订阅页并入节点页后拆成两页——「分流规则」（设置 › 网络 下面，全局设置）与「订阅覆写」一览
// （设置搜索「订阅覆写」；单个订阅的覆写在订阅弹层每行 ⋮ › 订阅覆写）。「编辑覆写 JSON」在覆写一览页和
// 单个订阅覆写页右上 ⋯ 里。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/config/sub_override_page.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What 「规则」 opens: 分流规则 or the 订阅覆写 list.
enum MuseRulesTab { routing, overrides }

/// 1.20.2：「分流规则」（[initialTab] = routing）或「订阅覆写」一览（overrides）。
class MuseRulesPage extends StatelessWidget {
  const MuseRulesPage({super.key, this.initialTab = MuseRulesTab.routing});

  final MuseRulesTab initialTab;

  @override
  Widget build(BuildContext context) => switch (initialTab) {
    MuseRulesTab.routing => const MuseScaffold(
      key: ValueKey('rules_routing_page'),
      title: '分流规则',
      body: MuseRoutingPage(embedded: true),
    ),
    MuseRulesTab.overrides => const MuseOverrideListPage(),
  };
}

/// Opens 「分流规则」 or the 「订阅覆写」 list.
Future<void> museOpenRules(BuildContext context, {MuseRulesTab tab = MuseRulesTab.routing}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MuseRulesPage(initialTab: tab)));

/// 1.20.2：所有订阅的覆写一览（设置搜索「订阅覆写」）；右上 ⋯ ›「编辑覆写 JSON」。
class MuseOverrideListPage extends ConsumerWidget {
  const MuseOverrideListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
    return MuseScaffold(
      key: const ValueKey('rules_overrides_page'),
      title: '订阅覆写',
      actions: [
        PopupMenuButton<String>(
          key: const ValueKey('rules_more'),
          tooltip: '更多',
          icon: const Icon(Icons.more_horiz_outlined),
          onSelected: (v) {
            if (v == 'override_json') museOpenOverrideJson(context, profiles);
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              key: const ValueKey('rules_more_override_json'),
              value: 'override_json',
              enabled: profiles.isNotEmpty,
              child: const Text('编辑覆写 JSON'),
            ),
          ],
        ),
      ],
      body: const MuseOverrideList(),
    );
  }
}
