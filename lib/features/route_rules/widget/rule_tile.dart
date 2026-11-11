import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/per_app_bypass.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/utils/platform_utils.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:protobuf/protobuf.dart';

class RuleTile extends HookConsumerWidget {
  const RuleTile({super.key, required this.index, required this.rule, this.divider = false});

  final Rule rule;
  final int index;

  /// 1.20.3 第 2 轮：在穿云分组卡片里，除第一行外上方画一条细线
  final bool divider;

  Map detailChipsValue() {
    final map = rule.toProto3Json()! as Map<String, dynamic>;
    map.removeWhere((key, value) => ['list_order', 'enabled', 'name', 'outbound'].contains(key));
    map.updateAll(
      (key, value) => value is List
          ? value.length
          : value is ProtobufEnum
          ? value.name
          : value,
    );
    return map;
  }

  Map<String, String> mergeTranslation(List<Map<String, String>> translations) {
    return Map.fromEntries(translations.expand((map) => map.entries).toList());
  }

  Future handleDelete(BuildContext context, WidgetRef ref) async {
    final t = ref.watch(translationsProvider).requireValue;
    final result = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(
          title: t.dialogs.confirmation.routeRule.delete.title,
          message: t.dialogs.confirmation.routeRule.delete.msg(rulename: rule.name),
          positiveBtnTxt: t.common.delete,
        );
    if (result == true) {
      await ref.read(rulesNotifierProvider.notifier).deleteRule(rule.listOrder);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final mt = MuseTheme.of(context);
    final builtin = BuiltinRule.of(rule);
    final region = ref.watch(ConfigOptions.region);
    final names = mergeTranslation([t.pages.settings.routing.routeRule.rule.tileTitle, t.pages.settings.routing.routeRule.rule.network, t.pages.settings.routing.routeRule.rule.outbound]);
    // 1.20.3 第 2 轮：条件写成一行灰字（原横向滚动的白色小块），和穿云其他设置行同一套样式
    final conditions = [for (final e in detailChipsValue().entries) '${names[e.key] ?? e.key} ${names['${e.value}'] ?? e.value}'].join(' · ');
    final outbound = t.pages.settings.routing.routeRule.rule.outbound[rule.outbound.name] ?? rule.outbound.name;
    final locked = builtin == BuiltinRule.bypassLan;
    final note = museBypassedNote(museBypassedPackages(rule.packageNames, ref.watch(musePerAppStateProvider).valueOrNull ?? (mode: null, active: const <String>{})));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (divider) Divider(height: MuseSize.hairline, thickness: MuseSize.hairline, indent: 52, color: mt.hairline),
        GestureDetector(
          onSecondaryTapUp: builtin == null && PlatformUtils.isDesktop
              ? (details) {
                  final offset = details.globalPosition;
                  showMenu(
                    context: context,
                    position: RelativeRect.fromLTRB(offset.dx, offset.dy, offset.dx, offset.dy),
                    items: [PopupMenuItem(child: Text(t.pages.settings.routing.routeRule.delete), onTap: () async => await handleDelete(context, ref))],
                  );
                }
              : null,
          child: MergeSemantics(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
              minLeadingWidth: MuseIconSize.regular,
              horizontalTitleGap: MuseSpace.s16,
              minVerticalPadding: MuseSpace.s12,
              // a built-in rule can only be switched and moved
              onTap: builtin != null ? null : () => context.goNamed('rule', pathParameters: {'orderId': rule.listOrder.toString()}),
              onLongPress: builtin != null ? null : () async => await handleDelete(context, ref),
              // 1.5.0: 局域网 stays first and on — no handle, a lock instead of the switch
              leading: locked
                  ? const MuseRowIcon(Icons.lock_outlined, key: ValueKey('lan_rule_locked'))
                  : ReorderableDragStartListener(
                      index: index,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Tooltip(message: '拖动调整先后', child: MuseRowIcon(Icons.drag_handle_outlined)),
                      ),
                    ),
              title: Text(builtin?.present(t, region) ?? rule.name, style: MuseTextLevel.callout.style(context)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      text: outbound,
                      children: [
                        if (builtin != null) ...[
                          const TextSpan(text: ' · '),
                          TextSpan(
                            text: t.pages.settings.routing.builtinRules.tag,
                            style: TextStyle(color: museBrandOf(context)),
                          ),
                        ],
                        if (conditions.isNotEmpty) TextSpan(text: ' · $conditions'),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MuseTextLevel.footnote.style(context, color: mt.text2),
                  ),
                  // 穿云 1.20.3：包名规则里有被分应用代理设为不走代理的应用时，说明它对这些应用不生效
                  if (note != null)
                    Padding(
                      key: const ValueKey('rule_bypassed_note'),
                      padding: const EdgeInsets.only(top: MuseSpace.s4),
                      child: Text(note, style: MuseTextLevel.footnote.style(context, color: MusePalette.red)),
                    ),
                ],
              ),
              trailing: Switch(value: locked || rule.enabled, onChanged: locked ? null : (value) async => await ref.read(rulesNotifierProvider.notifier).updateEnabled(value, rule.listOrder)),
            ),
          ),
        ),
      ],
    );
  }
}
