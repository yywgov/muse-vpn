// 穿云 - 关于 › 开源许可: the license, where the source is and the upstream project.
// 1.10.0: the credits moved here from 关于. 1.20.3: the 致谢 group is gone; Hiddify's licence
// (additional term 3) still wants the upstream named and linked, so the note on top stays and
// 「上游项目 Hiddify」 sits in 许可与源代码. The font licence files (assets/fonts/OFL-*.txt) stay bundled.
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
                padding: EdgeInsets.all(MuseSpace.s16),
                child: Text(
                  '穿云基于开源项目 Hiddify（hiddify-app / hiddify-core，内核为 sing-box）修改，'
                  '以 GNU 通用公共许可证第 3 版（GPLv3）发布，仅供学习交流，不得用于商业用途。',
                ),
              ),
            ],
          ),
          MuseSection(
            header: '许可与源代码',
            children: [
              MuseTile(
                key: const ValueKey('open_source_code'),
                leading: const Icon(Icons.code_outlined),
                title: '穿云源代码',
                chevron: true,
                onTap: () => open(Constants.githubUrl),
              ),
              MuseTile(
                leading: const Icon(Icons.memory_outlined),
                title: '穿云内核源代码',
                chevron: true,
                onTap: () => open('https://github.com/yywgov/muse-core'),
              ),
              MuseTile(
                key: const ValueKey('open_source_license'),
                leading: const Icon(Icons.description_outlined),
                title: 'GPLv3 许可证',
                chevron: true,
                onTap: () => open(Constants.licenseUrl),
              ),
              // 1.20.3: the upstream project, named and linked (Hiddify licence, additional term 3)
              MuseTile(
                key: const ValueKey('open_source_upstream'),
                leading: const Icon(Icons.account_tree_outlined),
                title: '上游项目 Hiddify',
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
