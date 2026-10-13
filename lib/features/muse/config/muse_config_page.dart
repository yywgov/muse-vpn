// 穿云 - config tab (配置): subscriptions/profiles + routing.
// Part of 穿云 (Chuanyun), a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseConfigPage extends HookConsumerWidget {
  const MuseConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final asyncProfiles = ref.watch(profilesNotifierProvider);

    return Scaffold(
      backgroundColor: MuseColors.background(context),
      appBar: AppBar(
        backgroundColor: MuseColors.background(context),
        scrolledUnderElevation: 0,
        title: const Text('配置'),
        actions: [
          IconButton(
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            icon: const Icon(Icons.sync_rounded),
            tooltip: t.pages.profiles.updateSubscriptions,
          ),
          IconButton(
            onPressed: () => ref.read(dialogNotifierProvider.notifier).showSortProfiles(),
            icon: const Icon(Icons.sort_rounded),
            tooltip: t.common.sort,
          ),
          IconButton(
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加订阅/配置',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '订阅 / 配置',
            footer: '点击切换当前使用的配置；右侧 ⋮ 菜单可更新、编辑、分享或删除。全局路由模式在「首页」切换。',
            children: [
              ...asyncProfiles.when(
                data: (profiles) => profiles.isEmpty
                    ? [
                        MuseTile(
                          leading: const Icon(Icons.add_circle_outline_rounded),
                          title: '添加订阅或配置',
                          subtitle: '订阅链接、剪贴板、二维码',
                          chevron: true,
                          onTap: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                        ),
                      ]
                    : [
                        for (final profile in profiles)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: ProfileTile(key: ValueKey(profile.id), profile: profile),
                          ),
                      ],
                loading: () => [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (error, _) => [MuseTile(title: '读取配置失败', subtitle: t.presentShortError(error))],
              ),
            ],
          ),
          MuseSection(
            header: '规则',
            children: [
              MuseTile(
                leading: const Icon(Icons.route_rounded),
                title: '路由规则',
                chevron: true,
                onTap: () => context.goNamed('routingOptions'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
