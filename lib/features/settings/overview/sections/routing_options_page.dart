import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/widget/rule_tile.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RoutingOptionsPage extends HookConsumerWidget {
  const RoutingOptionsPage({super.key, required this.routeRule});

  // Import route rule from deep link
  final String? routeRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final rules = ref.watch(rulesNotifierProvider);

    useMemoized(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (routeRule != null && context.mounted) {
          await ref.read(rulesNotifierProvider.notifier).importRulesFromDeepLink(routeRule!);
        }
      });
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.routing.title),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (_) {
              final notifier = ref.read(rulesNotifierProvider.notifier);
              final options = t.pages.settings.routing.routeRule.options;
              return <PopupMenuEntry>[
                PopupMenuItem(onTap: notifier.importRulesFromClipboard, child: Text(options.import.clipboard)),
                PopupMenuItem(onTap: notifier.importRulesFromJsonFile, child: Text(options.import.file)),
                const PopupMenuDivider(),
                PopupMenuItem(onTap: notifier.exportJsonToClipboard, child: Text(options.export.clipboard)),
                PopupMenuItem(onTap: notifier.saveRulesAsJsonFile, child: Text(options.export.file)),
                const PopupMenuDivider(),
                PopupMenuItem(onTap: notifier.resetRules, child: Text(options.reset)),
              ];
            },
          ),
          const Gap(8),
        ],
      ),
      // the built-in rules are always there, so the list is never empty
      body: ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 56 + 16 + 16),
        buildDefaultDragHandles: false,
        header: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PinnedOptions(),
          ],
        ),
        onReorder: ref.read(rulesNotifierProvider.notifier).reorder,
        itemBuilder: (context, index) => RuleTile(key: Key('$index'), index: index, rule: rules[index]),
        itemCount: rules.length,
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: t.pages.settings.routing.routeRule.add,
        onPressed: () => context.goNamed('rule', pathParameters: {'orderId': 'new'}),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

/// Options for every rule, so they head the rules and can't be moved.
class _PinnedOptions extends ConsumerWidget {
  const _PinnedOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final routing = t.pages.settings.routing;
    const divider = Divider(height: 1, indent: 16, endIndent: 16);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MenuOption(
          title: routing.balancerStrategy.title,
          selected: ref.watch(ConfigOptions.balancerStrategy),
          choices: BalancerStrategy.values,
          present: (value) => value.present(t),
          onSelected: ref.read(ConfigOptions.balancerStrategy.notifier).update,
        ),
        divider,
        SwitchListTile.adaptive(
          title: Text(routing.resolveDestination),
          value: ref.watch(ConfigOptions.resolveDestination),
          onChanged: ref.read(ConfigOptions.resolveDestination.notifier).update,
        ),
        divider,
        _MenuOption(
          title: routing.ipv6Route,
          selected: ref.watch(ConfigOptions.ipv6Mode),
          choices: IPv6Mode.values,
          present: (value) => value.present(t),
          onSelected: ref.read(ConfigOptions.ipv6Mode.notifier).update,
        ),
        const Divider(height: 3, thickness: 3),
      ],
    );
  }
}

/// A choice on one line: the value sits at the end, and its menu opens there.
class _MenuOption<T> extends HookWidget {
  const _MenuOption({
    required this.title,
    required this.selected,
    required this.choices,
    required this.present,
    required this.onSelected,
  });

  final String title;
  final T selected;
  final List<T> choices;
  final String Function(T value) present;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final menu = useMemoized(GlobalKey<PopupMenuButtonState<T>>.new);
    return ListTile(
      title: Text(title),
      // the row takes the tap, so all of it ripples
      onTap: () => menu.currentState?.showButtonMenu(),
      trailing: IgnorePointer(
        // a popup menu, so back closes it and not the page
        child: PopupMenuButton<T>(
          key: menu,
          position: PopupMenuPosition.under,
          onSelected: onSelected,
          itemBuilder: (_) => [
            for (final choice in choices)
              PopupMenuItem(
                value: choice,
                child: Row(
                  children: [
                    Expanded(child: Text(present(choice))),
                    if (choice == selected) const Icon(Icons.check_rounded),
                  ],
                ),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(present(selected), style: theme.textTheme.bodyMedium?.copyWith(color: color)),
              Icon(Icons.arrow_drop_down_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
