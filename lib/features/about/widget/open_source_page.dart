// 穿云 - 关于 › 开源许可 · 源代码: the GPL credit and where the source is.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class OpenSourcePage extends ConsumerWidget {
  const OpenSourcePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(String url) => UriUtils.tryLaunch(Uri.parse(url));
    return MuseScaffold(
      title: '开源许可',
      body: MuseGroupedBody(
        children: [
          const MuseSection(
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '穿云基于开源项目 Hiddify（hiddify-app / hiddify-core，内核为 sing-box）修改，'
                  '以 GNU 通用公共许可证第 3 版（GPLv3）发布，仅供学习交流，不得用于商业用途。\n\n'
                  '感谢 Hiddify 与 sing-box 的作者和贡献者。',
                ),
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseTile(
                leading: const Icon(Icons.code_rounded),
                title: '穿云源代码',
                chevron: true,
                onTap: () => open(Constants.githubUrl),
              ),
              MuseTile(
                leading: const Icon(Icons.memory_rounded),
                title: '穿云内核源代码',
                chevron: true,
                onTap: () => open('https://github.com/yywgov/muse-core'),
              ),
              MuseTile(
                leading: const Icon(Icons.description_outlined),
                title: 'GPLv3 许可证',
                chevron: true,
                onTap: () => open(Constants.licenseUrl),
              ),
              MuseTile(
                leading: const Icon(Icons.favorite_outline_rounded),
                title: 'Hiddify',
                chevron: true,
                onTap: () => open('https://github.com/hiddify/hiddify-app'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
