// 穿云 1.12.0 - 节点页「自动最快」下方的「范围」：全部地区（默认）或只在某个地区里挑最快。
// 只在选中自动最快时显示；改动走热重载，不加测速、不加定时器。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The regions to offer: those of [codes] (one per node, null = unknown), most nodes first.
List<(String, int)> museAutoRegionChoices(Iterable<String?> codes) {
  final count = <String, int>{};
  for (final c in codes) {
    if (c == null || c.isEmpty) continue;
    count[c] = (count[c] ?? 0) + 1;
  }
  final list = count.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  return list;
}

/// What the row says for region [code] ('' = 全部地区).
String museAutoRegionLabel(String code) =>
    code.isEmpty ? '全部地区' : '${museCountryFlag(code) ?? ''} ${museCountryLabel(code)}'.trim();

class MuseAutoRegionRow extends ConsumerWidget {
  const MuseAutoRegionRow({super.key, required this.regions});

  /// region code of every node in the list (null = unknown)
  final List<String?> regions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(MusePrefs.autoRegion);
    final mt = MuseTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('auto_region_row'),
        icon: Icon(Icons.public_outlined, size: MuseIconSize.small, color: mt.text2),
        label: Text('自动最快的范围：${museAutoRegionLabel(code)}', style: MuseType.caption(context).copyWith(color: mt.text2)),
        onPressed: () => _pick(context, ref, code),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, String current) async {
    final choices = museAutoRegionChoices(regions);
    final picked = await showMuseSnapSheet<String>(
      context,
      title: '自动最快的范围',
      builder: (ctx, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s8),
            child: Text('只在选定地区的节点里挑最快的；该地区没有节点时仍用全部节点。', style: MuseType.caption(ctx)),
          ),
          RadioListTile<String>(
            key: const ValueKey('auto_region_all'),
            value: '',
            groupValue: current,
            title: const Text('全部地区（默认）'),
            onChanged: (v) => Navigator.pop(ctx, v),
          ),
          for (final (c, n) in choices)
            RadioListTile<String>(
              key: ValueKey('auto_region_$c'),
              value: c,
              groupValue: current,
              title: Text('${museAutoRegionLabel(c)} · $n 个节点'),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await ref.read(MusePrefs.autoRegion.notifier).update(picked);
  }
}
