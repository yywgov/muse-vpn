// 穿云 - 订阅 tab: subscriptions + routing rules (1.3.0: named 订阅 everywhere).
// Part of 穿云 (Chuanyun), a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
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

    final offer = ref.watch(museClipboardOfferProvider) != null;
    return MuseScaffold(
      large: true,
      title: '订阅',
      actions: [
          IconButton(
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            icon: const Icon(Icons.sync_outlined),
            tooltip: t.pages.profiles.updateSubscriptions,
          ),
          IconButton(
            key: const ValueKey('profile_add_button'),
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            // a subscription link waits on the clipboard
            icon: Badge(isLabelVisible: offer, smallSize: 8, backgroundColor: MusePalette.brand, child: const Icon(Icons.add_outlined)),
            tooltip: '添加',
          ),
          const SizedBox(width: MuseSpace.s8),
        ],
      // 1.2.5: pull down to update every subscription (FlClash / Clash Verge Rev)
      body: RefreshIndicator(
        key: const ValueKey('config_pull_refresh'),
        color: MuseColors.brand,
        onRefresh: () async {
          try {
            await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
          } catch (_) {}
        },
        child: MuseGroupedBody(
        children: [
          MuseSection(
            dividerIndent: MuseSpace.s16,
            children: [
              ...asyncProfiles.when(
                data: (profiles) => profiles.isEmpty
                    ? [
                        MuseTile(
                          leading: const Icon(Icons.add_circle_outlined),
                          title: '添加订阅',
                          chevron: true,
                          onTap: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                        ),
                      ]
                    : [
                        for (final profile in profiles)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8, vertical: MuseSpace.s4),
                            child: ProfileTile(key: ValueKey(profile.id), profile: profile),
                          ),
                      ],
                // 1.5.0: skeleton rows instead of a spinner
                loading: () => [MuseSkeleton.rows(rows: 2)],
                error: (error, _) => [MuseTile(title: '读取订阅失败', subtitle: t.presentShortError(error))],
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseTile(
                leading: const Icon(Icons.route_outlined),
                title: '路由规则',
                chevron: true,
                onTap: () => context.goNamed('routingOptions'),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}
