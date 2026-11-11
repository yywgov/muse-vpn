import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/widget/rule_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 1.20.3 第 2 轮：「我的规则」页说明（规则从上往下匹配，拖动调整先后）。
const museMyRulesFooter = '从上往下匹配，先命中的生效；按住左侧把手拖动调整先后。局域网规则始终在最前、不能关闭。';

class RoutingOptionsPage extends HookConsumerWidget {
  const RoutingOptionsPage({super.key, required this.routeRule});

  // Import route rule from deep link
  final String? routeRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final rules = ref.watch(rulesNotifierProvider);
    final mt = MuseTheme.of(context);

    useMemoized(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (routeRule != null && context.mounted) {
          await ref.read(rulesNotifierProvider.notifier).importRulesFromDeepLink(routeRule!);
        }
      });
    });
    // 1.20.3 第 2 轮：穿云统一的页面（MuseScaffold + 分组卡片），加号放在标题栏，不再用浮动按钮
    return MuseScaffold(
      key: const ValueKey('my_rules_page'),
      // 入口在 设置 › 分流规则 ›「自定义规则」，页标题「我的规则」（原 Hiddify「路由」）
      title: '我的规则',
      actions: [
        IconButton(
          key: const ValueKey('my_rules_add'),
          tooltip: t.pages.settings.routing.routeRule.add,
          icon: const Icon(Icons.add_outlined),
          onPressed: () => context.goNamed('rule', pathParameters: {'orderId': 'new'}),
        ),
        PopupMenuButton<void>(
          key: const ValueKey('my_rules_more'),
          tooltip: '更多',
          icon: const Icon(Icons.more_horiz_outlined),
          itemBuilder: (_) {
            final notifier = ref.read(rulesNotifierProvider.notifier);
            final options = t.pages.settings.routing.routeRule.options;
            // 穿云 1.0: rules import/export (backup) removed here (分流规则 ⋯ has them); resetting stays
            return <PopupMenuEntry<void>>[PopupMenuItem(onTap: notifier.resetRules, child: Text(options.reset))];
          },
        ),
      ],
      body: MuseGroupedBody(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(MuseSpace.page(context) + MuseSpace.s16, MuseSpace.s4, MuseSpace.page(context) + MuseSpace.s16, MuseSpace.s4),
            child: Text(
              museMyRulesFooter,
              key: const ValueKey('my_rules_hint'),
              style: MuseType.caption(context).copyWith(color: mt.text2),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context), vertical: MuseSpace.s8),
            child: DecoratedBox(
              decoration: mt.cardDecoration(radius: MuseSection.radius),
              child: ClipRSuperellipse(
                borderRadius: MuseSection.radius,
                child: Material(
                  type: MaterialType.transparency,
                  // the built-in rules are always there, so the list is never empty
                  child: ReorderableListView.builder(
                    key: const ValueKey('my_rules_list'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, _, _) => Material(color: mt.card, child: child),
                    onReorderItem: (from, to) => ref.read(rulesNotifierProvider.notifier).reorder(from, from < to ? to + 1 : to),
                    itemBuilder: (context, index) => RuleTile(key: Key('$index'), index: index, rule: rules[index], divider: index > 0),
                    itemCount: rules.length,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
