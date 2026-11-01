// 穿云 1.9.0 #17 - 「规则」: 分流 and 订阅覆写 on one page (two tabs). The old entries
// (订阅 › 路由规则 / 覆写脚本, 设置 › 分流, settings search) all open this page.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/config/sub_override_page.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';

/// Tabs of 「规则」.
enum MuseRulesTab { routing, overrides }

class MuseRulesPage extends StatelessWidget {
  const MuseRulesPage({super.key, this.initialTab = MuseRulesTab.routing});

  final MuseRulesTab initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: MuseRulesTab.values.length,
      initialIndex: initialTab.index,
      child: MuseScaffold(
        title: '规则',
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
