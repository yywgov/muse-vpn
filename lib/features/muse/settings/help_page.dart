// 穿云 1.9.0 - 设置 › 帮助与隐私: glossary cards (#234), what is stored / never sent (#192) and the
// clipboard switch (#191). All text ships with the app, so it works offline (#238).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/help_content.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseHelpPage extends HookConsumerWidget {
  const MuseHelpPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final mt = MuseTheme.of(context);
    final terms = museGlossarySearch(query.value);
    return MuseScaffold(
      title: '帮助与隐私',
      body: MuseGroupedBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s8),
            child: TextField(
              key: const ValueKey('help_search'),
              onChanged: (v) => query.value = v,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '搜索名词，如 TUN、全局、节点',
                prefixIcon: Icon(Icons.search_outlined, size: MuseIconSize.small),
              ),
            ),
          ),
          MuseSection(
            header: '名词解释',
            dividerIndent: MuseSpace.s16,
            children: [
              if (terms.isEmpty) const MuseTile(key: ValueKey('help_empty'), title: '没有找到相关名词'),
              for (final t in terms)
                MuseTile(
                  key: ValueKey('term_${t.term}'),
                  title: t.term,
                  subtitle: t.meaning,
                  subtitleMaxLines: 6,
                ),
            ],
          ),
          MuseSection(
            header: '穿云保存什么',
            dividerIndent: MuseSpace.s16,
            children: [
              for (final (k, v) in musePrivacyStored) MuseTile(title: k, subtitle: v, subtitleMaxLines: 5),
            ],
          ),
          MuseSection(
            header: '不会做的事',
            children: [
              for (final line in musePrivacyNever)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16, vertical: MuseSpace.s12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_outlined, size: MuseIconSize.small, color: mt.text3),
                      const SizedBox(width: MuseSpace.s12),
                      Expanded(child: Text(line, style: MuseType.body(context))),
                    ],
                  ),
                ),
            ],
          ),
          MuseSection(
            header: '剪贴板',
            children: [
              MuseSwitchTile(
                key: const ValueKey('clear_clipboard_switch'),
                leading: const Icon(Icons.content_paste_off_outlined),
                title: '导入后清空剪贴板',
                info: '从剪贴板导入订阅链接后，立即清空剪贴板（链接里带有密钥）',
                value: ref.watch(MusePrefs.clearClipboardAfterImport),
                onChanged: (v) => ref.read(MusePrefs.clearClipboardAfterImport.notifier).update(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
