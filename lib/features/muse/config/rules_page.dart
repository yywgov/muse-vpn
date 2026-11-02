// 穿云 1.9.0 #17 - 「规则」: 分流 and 订阅覆写 on one page (two tabs).
// 1.10.0: the only entry is 订阅 › 规则 (plus settings search); 编辑覆写 JSON sits in the ⋯ menu
// at the top right (it was 「高级」 inside each subscription's 覆写), 去广告 is on the 分流 tab.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/config/sub_override_page.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tabs of 「规则」.
enum MuseRulesTab { routing, overrides }

class MuseRulesPage extends ConsumerWidget {
  const MuseRulesPage({super.key, this.initialTab = MuseRulesTab.routing});

  final MuseRulesTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
    return DefaultTabController(
      length: MuseRulesTab.values.length,
      initialIndex: initialTab.index,
      child: MuseScaffold(
        title: '规则',
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
        body: Column(
          children: [
            TabBar(
              key: const ValueKey('rules_tabs'),
              labelColor: museBrandOf(context),
              indicatorColor: museBrandOf(context),
              tabs: const [
                Tab(key: ValueKey('rules_tab_routing'), text: '分流'),
                Tab(key: ValueKey('rules_tab_overrides'), text: '订阅覆写'),
              ],
            ),
            const Expanded(child: TabBarView(children: [MuseRoutingPage(embedded: true), MuseOverrideList()])),
          ],
        ),
      ),
    );
  }
}

/// Opens 「规则」 on [tab].
Future<void> museOpenRules(BuildContext context, {MuseRulesTab tab = MuseRulesTab.routing}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MuseRulesPage(initialTab: tab)));
