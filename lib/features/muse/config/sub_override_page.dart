// 穿云 1.9.0 #15 - 订阅覆写 editor (form). 1.10.0: the raw JSON moved to 「规则」 › ⋯ › 编辑覆写 JSON
// (MuseOverrideJsonPage below); the editor no longer has a 「高级」 section.
// Saved by profile id; applied at connect / hot reload, never written into the subscription.
// Part of 穿云 (GPLv3).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/sub_override.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Reads one profile's override.
MuseSubOverride museOverrideOf(WidgetRef ref, String id) => museParseOverrides(ref.watch(MusePrefs.subOverrides))[id] ?? const MuseSubOverride();

/// Saves one profile's override (other profiles' entries stay as they are).
Future<void> museSaveOverride(WidgetRef ref, String id, MuseSubOverride o) async {
  final all = museParseOverrides(ref.read(MusePrefs.subOverrides))..[id] = o;
  await ref.read(MusePrefs.subOverrides.notifier).update(museEncodeOverrides(all));
}

/// One-line summary for the list (empty = none).
String museOverrideSummary(MuseSubOverride o) {
  if (o.rules.isEmpty && o.nodes.isEmpty && o.groups.isEmpty && o.edits.isEmpty && o.chains.isEmpty) return '未设置';
  final parts = [
    if (o.rules.isNotEmpty) '规则 ${o.rules.length}',
    if (o.nodes.isNotEmpty) '节点 ${o.nodes.length}',
    if (o.groups.isNotEmpty) '代理组 ${o.groups.length}',
    // 1.14.0 R21
    if (o.edits.isNotEmpty) '修改 ${o.edits.length}',
    // 1.15.0 R22
    if (o.chains.isNotEmpty) '前置 ${o.chains.length}',
  ];
  return '${o.enabled ? '' : '已停用 · '}${parts.join(' · ')}';
}

class MuseSubOverridePage extends HookConsumerWidget {
  const MuseSubOverridePage({super.key, required this.profileId, required this.profileName});

  final String profileId;
  final String profileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = museOverrideOf(ref, profileId);
    final mt = MuseTheme.of(context);
    Future<void> save(MuseSubOverride next) => museSaveOverride(ref, profileId, next);

    return MuseScaffold(
      title: '覆写 · $profileName',
      // 1.20.2：编辑覆写 JSON（原在 规则 › ⋯）——这个订阅自己的
      actions: [
        PopupMenuButton<String>(
          key: const ValueKey('override_more'),
          tooltip: '更多',
          icon: const Icon(Icons.more_horiz_outlined),
          onSelected: (_) => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => MuseOverrideJsonPage(profileId: profileId, profileName: profileName)),
          ),
          itemBuilder: (_) => const [PopupMenuItem(key: ValueKey('override_more_json'), value: 'json', child: Text('编辑覆写 JSON'))],
        ),
      ],
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '覆写在连接时合成，不修改订阅本身；订阅更新后照样生效。标准内核与兼容内核都会使用。',
            children: [
              SwitchListTile(
                key: const ValueKey('override_enabled'),
                title: Text('启用覆写', style: MuseType.body(context)),
                value: o.enabled,
                onChanged: (v) => save(o.copyWith(enabled: v)),
              ),
            ],
          ),
          MuseSection(
            header: '自定义规则',
            footer: '排在「局域网」之后、其他分流规则之前。',
            children: [
              for (var i = 0; i < o.rules.length; i++)
                MuseTile(
                  key: ValueKey('override_rule_$i'),
                  title: o.rules[i].value,
                  subtitle: '${o.rules[i].match.label} → ${o.rules[i].target.label}',
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: Icon(Icons.delete_outlined, size: MuseIconSize.small, color: mt.text2),
                    onPressed: () => save(o.copyWith(rules: [...o.rules]..removeAt(i))),
                  ),
                ),
              MuseTile(
                key: const ValueKey('override_add_rule'),
                leading: const Icon(Icons.add_outlined),
                title: '添加规则',
                onTap: () async {
                  final r = await showDialog<MuseOverrideRule>(context: context, builder: (_) => const _RuleDialog());
                  if (r != null) await save(o.copyWith(rules: [...o.rules, r]));
                },
              ),
            ],
          ),
          MuseSection(
            header: '代理组',
            footer: '按名称筛选订阅里的节点（正则，留空为全部）；与订阅自带的组同名时不添加。',
            children: [
              for (var i = 0; i < o.groups.length; i++)
                MuseTile(
                  key: ValueKey('override_group_$i'),
                  title: o.groups[i].name,
                  subtitle: '${o.groups[i].urlTest ? '自动选择' : '手动选择'}${o.groups[i].filter.isEmpty ? ' · 全部节点' : ' · ${o.groups[i].filter}'}',
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: Icon(Icons.delete_outlined, size: MuseIconSize.small, color: mt.text2),
                    onPressed: () => save(o.copyWith(groups: [...o.groups]..removeAt(i))),
                  ),
                ),
              MuseTile(
                key: const ValueKey('override_add_group'),
                leading: const Icon(Icons.add_outlined),
                title: '添加代理组',
                onTap: () async {
                  final g = await showDialog<MuseOverrideGroup>(context: context, builder: (_) => const _GroupDialog());
                  if (g != null) await save(o.copyWith(groups: [...o.groups, g]));
                },
              ),
            ],
          ),
          _NodesSection(key: ValueKey('override_nodes_${o.nodes.join('|')}'), initial: o.nodes, onSave: (n) => save(o.copyWith(nodes: n))),
        ],
      ),
    );
  }
}

class _NodesSection extends HookWidget {
  const _NodesSection({super.key, required this.initial, required this.onSave});

  final List<String> initial;
  final Future<void> Function(List<String>) onSave;

  @override
  Widget build(BuildContext context) {
    final c = useTextEditingController(text: initial.join('\n'));
    return MuseSection(
      header: '追加节点',
      footer: '每行一个分享链接（vless:// 、ss:// 等），连接时加到这个订阅的节点后面。',
      children: [
        Padding(
          padding: const EdgeInsets.all(MuseSpace.s12),
          child: TextField(
            key: const ValueKey('override_nodes_field'),
            controller: c,
            minLines: 2,
            maxLines: 6,
            style: MuseType.caption(context),
            decoration: const InputDecoration(hintText: 'vless://…'),
          ),
        ),
        MuseTile(
          key: const ValueKey('override_nodes_save'),
          leading: const Icon(Icons.save_outlined),
          title: '保存节点',
          onTap: () => onSave(museOverrideLinks(c.text)),
        ),
      ],
    );
  }
}

/// 1.10.0: one subscription's override as JSON (「规则」 › ⋯ › 编辑覆写 JSON). No script runs: the same
/// data the form edits, e.g. pasted from another device.
class MuseOverrideJsonPage extends HookConsumerWidget {
  const MuseOverrideJsonPage({super.key, required this.profileId, required this.profileName});

  final String profileId;
  final String profileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = museOverrideOf(ref, profileId);
    final c = useTextEditingController(text: const JsonEncoder.withIndent('  ').convert(value.toJson()));
    final error = useState<String?>(null);
    return MuseScaffold(
      title: '覆写 JSON · $profileName',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '与「订阅覆写」里的表单是同一份数据',
            children: [
              Padding(
                padding: const EdgeInsets.all(MuseSpace.s12),
                child: TextField(
                  key: const ValueKey('override_json_field'),
                  controller: c,
                  minLines: 6,
                  maxLines: 20,
                  style: MuseType.caption(context),
                  decoration: InputDecoration(errorText: error.value),
                ),
              ),
              MuseTile(
                key: const ValueKey('override_json_apply'),
                leading: const Icon(Icons.check_outlined),
                title: '应用',
                onTap: () async {
                  try {
                    final j = jsonDecode(c.text);
                    if (j is! Map) throw const FormatException();
                    error.value = null;
                    await museSaveOverride(ref, profileId, MuseSubOverride.fromJson(j));
                    if (context.mounted) Navigator.of(context).maybePop();
                  } catch (_) {
                    error.value = '不是有效的覆写 JSON';
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 1.10.0: 「规则」 › ⋯ › 编辑覆写 JSON — picks the subscription when there are several.
Future<void> museOpenOverrideJson(BuildContext context, List<ProfileEntity> profiles) async {
  if (profiles.isEmpty) return;
  var p = profiles.first;
  if (profiles.length > 1) {
    final picked = await showDialog<ProfileEntity>(
      context: context,
      builder: (c) => SimpleDialog(
        key: const ValueKey('override_json_pick'),
        title: const Text('编辑哪个订阅的覆写'),
        children: [
          for (final e in profiles)
            SimpleDialogOption(key: ValueKey('override_json_pick_${e.id}'), onPressed: () => Navigator.of(c).pop(e), child: Text(e.name)),
        ],
      ),
    );
    if (picked == null) return;
    p = picked;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MuseOverrideJsonPage(profileId: p.id, profileName: p.name)));
}

class _RuleDialog extends HookWidget {
  const _RuleDialog();

  @override
  Widget build(BuildContext context) {
    final match = useState(MuseOverrideMatch.domainSuffix);
    final target = useState(MuseOverrideTarget.proxy);
    final c = useTextEditingController();
    return AlertDialog(
      title: const Text('添加规则'),
      content: SizedBox(
        width: MuseSize.dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<MuseOverrideMatch>(
              key: const ValueKey('override_rule_match'),
              initialValue: match.value,
              decoration: const InputDecoration(labelText: '匹配'),
              items: [for (final m in MuseOverrideMatch.values) DropdownMenuItem(value: m, child: Text(m.label))],
              onChanged: (v) => match.value = v ?? match.value,
            ),
            TextField(
              key: const ValueKey('override_rule_value'),
              controller: c,
              decoration: const InputDecoration(labelText: '内容', hintText: '如 example.com 或 1.2.3.0/24'),
            ),
            DropdownButtonFormField<MuseOverrideTarget>(
              key: const ValueKey('override_rule_target'),
              initialValue: target.value,
              decoration: const InputDecoration(labelText: '去向'),
              items: [for (final t in MuseOverrideTarget.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (v) => target.value = v ?? target.value,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(
          key: const ValueKey('override_rule_ok'),
          onPressed: () {
            final v = c.text.trim();
            if (v.isEmpty) return;
            Navigator.of(context).pop(MuseOverrideRule(match: match.value, value: v, target: target.value));
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _GroupDialog extends HookWidget {
  const _GroupDialog();

  @override
  Widget build(BuildContext context) {
    final name = useTextEditingController();
    final filter = useTextEditingController();
    final urlTest = useState(false);
    return AlertDialog(
      title: const Text('添加代理组'),
      content: SizedBox(
        width: MuseSize.dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(key: const ValueKey('override_group_name'), controller: name, decoration: const InputDecoration(labelText: '名称')),
            TextField(
              key: const ValueKey('override_group_filter'),
              controller: filter,
              decoration: const InputDecoration(labelText: '节点筛选（正则，可留空）', hintText: '如 香港|HK'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动选择（延迟最低）'),
              value: urlTest.value,
              onChanged: (v) => urlTest.value = v,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(
          key: const ValueKey('override_group_ok'),
          onPressed: () {
            final n = name.text.trim();
            if (n.isEmpty) return;
            Navigator.of(context).pop(MuseOverrideGroup(name: n, urlTest: urlTest.value, filter: filter.text.trim()));
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

/// The subscriptions, each opening its 覆写 (the 「订阅覆写」 part of 「规则」).
class MuseOverrideList extends ConsumerWidget {
  const MuseOverrideList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
    final all = museParseOverrides(ref.watch(MusePrefs.subOverrides));
    return MuseGroupedBody(
      children: [
        MuseSection(
          footer: '为单个订阅添加规则、节点和代理组。覆写在连接时合成，订阅本身不改，更新订阅后保留。',
          children: [
            if (profiles.isEmpty) const MuseTile(key: ValueKey('override_list_empty'), title: '还没有订阅'),
            for (final p in profiles)
              MuseTile(
                key: ValueKey('override_profile_${p.id}'),
                leading: const Icon(Icons.tune_outlined),
                title: p.name,
                trailing: Text(museOverrideSummary(all[p.id] ?? const MuseSubOverride())),
                chevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => MuseSubOverridePage(profileId: p.id, profileName: p.name)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
