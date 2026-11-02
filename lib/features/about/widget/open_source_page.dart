// 穿云 - 关于 › 开源许可与致谢: the license, where the source is and the GPL credits.
// 1.10.0: the credits moved here from 关于 (the only place in the app the upstream projects are named).
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
      title: '开源许可与致谢',
      body: MuseGroupedBody(
        children: [
          const MuseSection(
            children: [
              Padding(
                padding: EdgeInsets.all(MuseSpace.s16),
                child: Text(
                  '穿云基于开源项目 Hiddify（hiddify-app / hiddify-core，内核为 sing-box）修改，'
                  '以 GNU 通用公共许可证第 3 版（GPLv3）发布，仅供学习交流，不得用于商业用途。\n\n'
                  '感谢 Hiddify 与 sing-box 的作者和贡献者。',
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
            ],
          ),
          // the GPL credits — the only place in the app the upstream projects are named
          MuseSection(
            header: '致谢',
            footer: '穿云以 GPL-3.0 协议开源',
            children: [
              MuseTile(
                key: const ValueKey('about_credit_ui'),
                leading: const Icon(Icons.design_services_outlined),
                title: '界面设计参考 FlClash',
                subtitle: 'chen08209 · GPL-3.0',
                chevron: true,
                onTap: () => open('https://github.com/chen08209/FlClash'),
              ),
              MuseTile(
                key: const ValueKey('about_credit_base'),
                leading: const Icon(Icons.account_tree_outlined),
                title: '基于 Hiddify 开发',
                subtitle: 'GPL-3.0',
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
