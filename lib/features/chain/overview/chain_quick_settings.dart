// Chain (前置/出口代理) part of the quick settings sheet.
// Reworked for Muse VPN (fork of Hiddify, GPLv3): plain Chinese, grouped-list rows,
// same providers and menus as before (ChainModeButton / ConfigOptions.chainStatus).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/chain/overview/chain_mode_button.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChainQuickSettings extends HookConsumerWidget {
  const ChainQuickSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(hasAnyProfileProvider).value ?? false;

    Widget button(Widget child) => ConstrainedBox(constraints: const BoxConstraints(maxWidth: 130), child: child);

    return MuseSection(
      header: '链式代理（一般不用开）',
      footer: '两项同时只能开一个。点右侧按钮选择 WARP / Psiphon 或关闭。',
      children: [
        MuseTile(
          title: '前置代理',
          subtitle: '先经过 WARP/Psiphon 再连到你的节点；节点被封、连不上时再试，一般不用开',
          trailing: button(const ChainModeButton.unblocker(showConfiguration: true)),
        ),
        MuseTile(
          title: '出口代理',
          subtitle: '先连你的节点，再从 WARP/Psiphon 出去，网站看到的是它的 IP；一般不用开',
          trailing: button(const ChainModeButton.extraSecurity(showConfiguration: true)),
        ),
        if (hasProfile)
          MuseTile(
            title: '链式代理详细设置',
            subtitle: 'WARP 密钥、Psiphon 地区等',
            chevron: true,
            onTap: () {
              context.pop();
              context.goNamed('chainOptions');
            },
          ),
      ],
    );
  }
}
