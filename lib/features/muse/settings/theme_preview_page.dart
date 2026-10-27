// 穿云 1.6.0 C10 (C7 顺延) - 外观 › 主题预览: small, static copies of the main pieces (首页 card,
// 节点 cards, a settings list, a dialog, buttons) in the current 深浅色 / 主题色 / 文字缩放, so a
// change can be judged without leaving 外观. Nothing here is live data and nothing can be changed.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_card.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';

class MuseThemePreviewPage extends StatelessWidget {
  const MuseThemePreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final caption = MuseType.caption(context).copyWith(color: mt.text2);

    Widget node(String name, String delay, Color color, {bool selected = false}) => Expanded(
      child: MuseCard(
        selected: selected,
        padding: const EdgeInsets.all(MuseSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.body(context)),
            const SizedBox(height: MuseSpace.s4),
            Text(delay, style: MuseType.caption(context).copyWith(color: color, fontFeatures: MuseType.tabular)),
          ],
        ),
      ),
    );

    return MuseScaffold(
      title: '主题预览',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '首页',
            children: [
              Padding(
                padding: const EdgeInsets.all(MuseSpace.s12),
                child: MuseCard(
                  key: const ValueKey('preview_home_card'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('已连接', style: MuseType.title(context)),
                            const SizedBox(height: MuseSpace.s4),
                            Text('示例节点 · 规则', style: caption),
                          ],
                        ),
                      ),
                      Switch(value: true, onChanged: (_) {}),
                    ],
                  ),
                ),
              ),
            ],
          ),
          MuseSection(
            header: '节点',
            children: [
              Padding(
                padding: const EdgeInsets.all(MuseSpace.s12),
                child: Row(
                  key: const ValueKey('preview_nodes'),
                  children: [
                    node('示例节点 A', '86 ms', MusePalette.green, selected: true),
                    const SizedBox(width: MuseSpace.s8),
                    node('示例节点 B', '240 ms', MusePalette.orange),
                    const SizedBox(width: MuseSpace.s8),
                    node('示例节点 C', '超时', MusePalette.red),
                  ],
                ),
              ),
            ],
          ),
          MuseSection(
            header: '列表',
            children: [
              MuseSwitchTile(
                key: const ValueKey('preview_switch'),
                leading: const Icon(Icons.autorenew_outlined),
                title: '开关示例',
                value: true,
                onChanged: (_) {},
              ),
              const MuseTile(leading: Icon(Icons.palette_outlined), title: '选项示例', trailing: Text('当前值'), chevron: true),
              MuseChoiceTile(title: '单选示例', selected: true, onTap: () {}),
            ],
          ),
          MuseSection(
            header: '弹窗与按钮',
            children: [
              Padding(
                padding: const EdgeInsets.all(MuseSpace.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // the dialog surface, drawn in place (not a route)
                    Material(
                      key: const ValueKey('preview_dialog'),
                      color: scheme.surfaceContainerHigh,
                      shape: MuseShape.of(MuseRadius.card),
                      child: Padding(
                        padding: const EdgeInsets.all(MuseSpace.s16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('弹窗标题', style: MuseType.title(context)),
                            const SizedBox(height: MuseSpace.s8),
                            Text('弹窗正文示例，确认或取消。', style: MuseType.body(context)),
                            const SizedBox(height: MuseSpace.s12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(onPressed: () {}, child: const Text('取消')),
                                const SizedBox(width: MuseSpace.s8),
                                FilledButton(onPressed: () {}, child: const Text('确定')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: MuseSpace.s12),
                    Wrap(
                      spacing: MuseSpace.s8,
                      runSpacing: MuseSpace.s8,
                      children: [
                        FilledButton(onPressed: () {}, child: const Text('主要按钮')),
                        OutlinedButton(onPressed: () {}, child: const Text('次要按钮')),
                        TextButton(onPressed: () {}, child: const Text('文字按钮')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
