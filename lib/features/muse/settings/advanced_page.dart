// 穿云 - 设置 > 高级: the one rarely needed knob that stays (TLS 分片 / 技巧).
// 1.0 removed the developer options (run mode, ports, core, test URL, backup).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AdvancedPage extends HookConsumerWidget {
  const AdvancedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MuseScaffold(
      title: '高级',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                title: 'TLS 分片 / 技巧',
                chevron: true,
                onTap: () => context.goNamed('tlsTricks'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
