// Quick settings sheet, reworked for Muse VPN (fork of Hiddify, GPLv3) in plain Chinese,
// grouped-list style: each item is a title plus a one-line grey explanation.

import 'package:flutter/material.dart';
import 'package:hiddify/features/chain/overview/chain_quick_settings.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/lan_sharing_tile.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class QuickSettingsModal extends HookConsumerWidget {
  const QuickSettingsModal({super.key});

  static (String, String) _serviceModeText(ServiceMode mode) => switch (mode) {
    ServiceMode.tun => ('VPN（全局接管，推荐）', '接管手机上所有应用的网络，不用额外设置'),
    ServiceMode.proxy => ('仅代理', '只在本机开一个代理端口，需要应用自己设置代理才会生效'),
    ServiceMode.systemProxy => ('系统代理', '设置为系统代理，支持系统代理的应用会自动使用'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serviceMode = ref.watch(ConfigOptions.serviceMode);
    final routeMode = ref.watch(ConfigOptions.museRouteMode);
    final mixedPort = ref.watch(ConfigOptions.mixedPort);

    return ColoredBox(
      color: MuseColors.background(context),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                child: Text('快速设置', style: Theme.of(context).textTheme.titleMedium),
              ),
              MuseSection(
                header: '运行模式',
                footer: serviceMode == ServiceMode.proxy ? '代理地址：127.0.0.1:$mixedPort（HTTP / SOCKS 均可）' : null,
                children: [
                  for (final mode in ServiceMode.choices)
                    MuseChoiceTile(
                      title: _serviceModeText(mode).$1,
                      subtitle: _serviceModeText(mode).$2,
                      selected: serviceMode == mode,
                      onTap: () => ref.read(ConfigOptions.serviceMode.notifier).update(mode),
                    ),
                ],
              ),
              MuseSection(
                header: '全局路由',
                children: [
                  for (final mode in MuseRouteMode.values)
                    MuseChoiceTile(
                      title: mode.title,
                      subtitle: mode.explain,
                      selected: routeMode == mode,
                      onTap: () => ref.read(ConfigOptions.museRouteMode.notifier).update(mode),
                    ),
                ],
              ),
              const MuseSection(
                header: '局域网共享',
                children: [
                  LanSharingPreferenceWidget(
                    showLeading: false,
                    title: '局域网共享',
                    subtitle: '允许同一 WiFi 下的其他设备通过本机上网，会显示 IP 和端口',
                  ),
                ],
              ),
              const ChainQuickSettings(),
            ],
          ),
        ),
      ),
    );
  }
}
