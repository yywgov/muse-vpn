// 穿云 - 订阅 tab: subscriptions + routing rules (1.3.0: named 订阅 everywhere).
// Part of 穿云 (Chuanyun), a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/muse/config/rules_page.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/profile_tools.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show musePick;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseConfigPage extends HookConsumerWidget {
  const MuseConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final asyncProfiles = ref.watch(profilesNotifierProvider);

    final offer = ref.watch(museClipboardOfferProvider) != null;
    return MuseScaffold(
      large: true,
      title: '订阅',
      actions: [
          IconButton(
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            icon: const Icon(Icons.sync_outlined),
            tooltip: t.pages.profiles.updateSubscriptions,
          ),
          // 1.6.0 C6: arrange the subscriptions by dragging
          if ((asyncProfiles.valueOrNull?.length ?? 0) > 1)
            IconButton(
              key: const ValueKey('profile_order_button'),
              onPressed: () => showMuseProfileOrder(context, ref, asyncProfiles.requireValue),
              icon: const Icon(Icons.swap_vert_outlined),
              tooltip: '排序',
            ),
          // 1.10.0: 订阅自动更新 moved here from the 设置 home page (same preference)
          PopupMenuButton<String>(
            key: const ValueKey('profile_more'),
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_outlined),
            onSelected: (v) async {
              // 1.12.0: 更新后测新节点
              if (v == 'test_new_nodes') {
                await ref.read(MusePrefs.testNewNodes.notifier).update(!ref.read(MusePrefs.testNewNodes));
                return;
              }
              if (v != 'auto_update') return;
              final hours = ref.read(Preferences.museAutoUpdateHours);
              final picked = await musePick<int>(
                context,
                '订阅自动更新',
                [for (final h in museAutoUpdateChoices) (h, museAutoUpdateLabel(h))],
                hours,
              );
              if (picked != null) await ref.read(Preferences.museAutoUpdateHours.notifier).update(picked);
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                key: const ValueKey('auto_update_hours'),
                value: 'auto_update',
                child: Text('订阅自动更新：${museAutoUpdateLabel(ref.read(Preferences.museAutoUpdateHours))}'),
              ),
              CheckedPopupMenuItem<String>(
                key: const ValueKey('test_new_nodes'),
                value: 'test_new_nodes',
                checked: ref.read(MusePrefs.testNewNodes),
                child: const Text('更新后测速新增节点'),
              ),
            ],
          ),
          IconButton(
            key: const ValueKey('profile_add_button'),
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            // a subscription link waits on the clipboard
            icon: Badge(isLabelVisible: offer, smallSize: 8, backgroundColor: museBrandOf(context), child: const Icon(Icons.add_outlined)),
            tooltip: '添加',
          ),
          const SizedBox(width: MuseSpace.s8),
        ],
      // 1.2.5: pull down to update every subscription (FlClash / Clash Verge Rev)
      body: RefreshIndicator(
        key: const ValueKey('config_pull_refresh'),
        color: museBrandOf(context),
        onRefresh: () async {
          try {
            await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
          } catch (_) {}
        },
        child: MuseGroupedBody(
        children: [
          MuseSection(
            dividerIndent: MuseSpace.s16,
            children: [
              ...asyncProfiles.when(
                data: (profiles) => profiles.isEmpty
                    ? [
                        MuseTile(
                          leading: const Icon(Icons.add_circle_outlined),
                          title: '添加订阅',
                          chevron: true,
                          onTap: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                        ),
                      ]
                    : [_MuseProfileGrid(profiles: profiles)],
                // 1.5.0: skeleton rows instead of a spinner
                loading: () => [MuseSkeleton.rows(rows: 2)],
                error: (error, _) => [MuseTile(title: '读取订阅失败', subtitle: t.presentShortError(error))],
              ),
            ],
          ),
          MuseSection(
            children: [
              // 1.9.0 #17: 路由规则 and 订阅覆写 are one 「规则」 page (分流 / 订阅覆写 tabs)
              MuseTile(
                key: const ValueKey('profile_rules_entry'),
                leading: const Icon(Icons.rule_outlined),
                title: '规则',
                subtitle: '分流 · 订阅修改',
                chevron: true,
                onTap: () => museOpenRules(context),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

/// 1.6.0 C6: subscriptions in the user's order; cards in 1–3 columns (one per 300 px).
class _MuseProfileGrid extends ConsumerWidget {
  const _MuseProfileGrid({required this.profiles});

  final List<ProfileEntity> profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = {for (final p in profiles) p.id: p};
    final ordered = [for (final id in museOrderIds(profiles.map((e) => e.id).toList(), ref.watch(MusePrefs.profileOrder))) byId[id]!];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = museProfileColumns(box.maxWidth);
        final rows = <Widget>[];
        for (var i = 0; i < ordered.length; i += columns) {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + columns; j++)
                    Expanded(
                      child: j < ordered.length
                          ? Padding(
                              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8, vertical: MuseSpace.s4),
                              child: ProfileTile(key: ValueKey(ordered[j].id), profile: ordered[j]),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          );
        }
        return Column(key: ValueKey('profile_grid_$columns'), children: rows);
      },
    );
  }
}

/// 1.6.0 C6: drag the subscriptions into order (saved as ids; nothing is deleted).
Future<void> showMuseProfileOrder(BuildContext context, WidgetRef ref, List<ProfileEntity> profiles) async {
  final byId = {for (final p in profiles) p.id: p};
  final start = museOrderIds(profiles.map((e) => e.id).toList(), ref.read(MusePrefs.profileOrder));
  final result = await showDialog<List<String>>(
    context: context,
    builder: (context) => _MuseProfileOrderDialog(ids: start, names: {for (final e in byId.entries) e.key: e.value.name}),
  );
  if (result != null) await ref.read(MusePrefs.profileOrder.notifier).update(result.join(','));
}

class _MuseProfileOrderDialog extends StatefulWidget {
  const _MuseProfileOrderDialog({required this.ids, required this.names});

  final List<String> ids;
  final Map<String, String> names;

  @override
  State<_MuseProfileOrderDialog> createState() => _MuseProfileOrderDialogState();
}

class _MuseProfileOrderDialogState extends State<_MuseProfileOrderDialog> {
  late final List<String> _ids = [...widget.ids];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('订阅排序'),
      content: SizedBox(
        width: MuseSize.dialogWidth,
        child: ReorderableListView.builder(
          key: const ValueKey('profile_order_list'),
          shrinkWrap: true,
          itemCount: _ids.length,
          onReorder: (from, to) => setState(() {
            final id = _ids.removeAt(from);
            _ids.insert(to > from ? to - 1 : to, id);
          }),
          itemBuilder: (context, i) => ListTile(
            key: ValueKey('profile_order_${_ids[i]}'),
            title: Text(widget.names[_ids[i]] ?? _ids[i], maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(key: const ValueKey('profile_order_save'), onPressed: () => Navigator.of(context).pop(_ids), child: const Text('保存')),
      ],
    );
  }
}
