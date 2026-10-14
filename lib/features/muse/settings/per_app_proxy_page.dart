// 穿云 - 设置 > 分应用代理: which apps go through 穿云 at all (Android VPN app list).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/widget/shimmer_skeleton.dart';
import 'package:hiddify/features/app_based_routing/data/auto_selection_repository.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';
import 'package:hiddify/features/app_based_routing/overview/app_based_routing_notifier.dart';
import 'package:hiddify/features/app_based_routing/overview/app_list_notifier.dart';
import 'package:hiddify/features/app_based_routing/overview/auto_selection_notifier.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PerAppProxyPage extends ConsumerWidget {
  const PerAppProxyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(Preferences.perAppProxyModeInUse);
    final savedMode = ref.watch(Preferences.perAppProxyMode);
    final service = ref.read(appBasedRoutingProvider.notifier);

    return MuseScaffold(
      title: '分应用代理',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseSwitchTile(
                leading: const Icon(Icons.apps_rounded),
                title: '分应用代理',
                value: mode != null,
                onChanged: service.setEnabled,
              ),
            ],
          ),
          if (mode != null) ...[
            MuseSection(
              header: '模式',
              children: [
                MuseChoiceTile(
                  title: '以下 App 不走代理',
                  subtitle: '除了列表里的 App，其余都经过穿云（推荐）',
                  selected: savedMode == AppProxyMode.exclude,
                  onTap: () => service.changeMode(AppProxyMode.exclude),
                ),
                MuseChoiceTile(
                  title: '仅以下 App 走代理',
                  subtitle: '只有列表里的 App 经过穿云，其余全部直连',
                  selected: savedMode == AppProxyMode.include,
                  onTap: () => service.changeMode(AppProxyMode.include),
                ),
              ],
            ),
            MuseSection(
              header: mode.listTitle(ref.watch(translationsProvider).requireValue),
              children: [_AppListRow(mode: mode), _AutoSelection(mode: mode)],
            ),
          ],
        ],
      ),
    );
  }
}

class _AppListRow extends ConsumerWidget {
  const _AppListRow({required this.mode});

  final AppProxyMode mode;

  static const _maxLogos = 10;
  static const _loadingLogo = ClipOval(child: ShimmerSkeleton(width: 24, height: 24));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final appBasedRouting = t.pages.settings.routing.appBasedRouting;
    final flags = ref.watch(AppListProvider(mode)).valueOrNull;
    // the text sits close to the logos and is smaller than a list title; the row is 48 dp, like auto selection
    ListTile row({required Widget leading, required Widget title}) => ListTile(
      minTileHeight: 48,
      horizontalTitleGap: 8,
      titleTextStyle: theme.textTheme.bodyMedium,
      leading: leading,
      title: title,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.goNamed('appList'),
    );

    // placeholders until the list loads, at the loaded row's height, so nothing jumps
    if (flags == null) {
      return row(
        leading: _LogoStack(children: List.filled(3, _loadingLogo)),
        title: const Align(alignment: AlignmentDirectional.centerStart, child: ShimmerSkeleton(width: 56, height: 14)),
      );
    }
    bool active(int flag) => !PkgFlag.forceDeselection.check(flag);
    // your own picks get a logo first
    final apps = [
      for (final entry in flags.entries)
        if (active(entry.value) && PkgFlag.userSelection.check(entry.value)) entry.key,
      for (final entry in flags.entries)
        if (active(entry.value) && !PkgFlag.userSelection.check(entry.value)) entry.key,
    ];
    if (apps.isEmpty) {
      final color = theme.colorScheme.primary;
      return row(
        // an empty slot the size of a logo
        leading: _LogoStack(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: Icon(Icons.add_rounded, size: 16, color: color),
            ),
          ],
        ),
        title: Text(appBasedRouting.chooseApps, style: TextStyle(color: color)),
      );
    }
    final logoApps = apps.take(_maxLogos).toList();
    // decoded at the screen's density, so the logos stay sharp
    final logoPx = (24 * MediaQuery.devicePixelRatioOf(context)).round();
    return row(
      // each logo fills its place when it loads; the text is final already
      leading: _LogoStack(
        children: [
          for (final pkg in logoApps)
            switch (ref.watch(appLogoProvider(pkg))) {
              AsyncData(value: final icon?) => ClipOval(
                child: Image.memory(icon, width: 24, height: 24, cacheWidth: logoPx, cacheHeight: logoPx),
              ),
              AsyncLoading() => _loadingLogo,
              _ => const Icon(Icons.android_rounded),
            },
        ],
      ),
      // 穿云 1.2.1: the total, not "另外 N 个" next to the logos
      title: Text(museAppCountLabel(apps.length)),
    );
  }
}

/// App logos laid over each other, each in a ring of the page color so it stays clear.
class _LogoStack extends StatelessWidget {
  const _LogoStack({required this.children});

  final List<Widget> children;

  // a 24 dp logo in a 2 dp ring
  static const _size = 28.0;
  static const _step = 16.0;

  @override
  Widget build(BuildContext context) {
    final ring = MuseColors.card(context);
    return SizedBox(
      width: _size + (children.length - 1) * _step,
      height: _size,
      child: Stack(
        children: [
          for (final (index, child) in children.indexed)
            PositionedDirectional(
              start: index * _step,
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

/// 「共 N 个 App」 under the per-app list.
String museAppCountLabel(int n) => '共 $n 个 App';

class _AutoSelection extends HookConsumerWidget {
  const _AutoSelection({required this.mode});

  final AppProxyMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final autoSelection = t.pages.settings.routing.appBasedRouting.autoSelection;
    final theme = Theme.of(context);
    final service = ref.read(appBasedRoutingProvider.notifier);
    final loading = ref.watch(autoSelectionLoadingProvider);
    final isOn = ref.watch(Preferences.autoAppsSelectionRegion) != null;
    final lastUpdate = ref.watch(Preferences.autoAppsSelectionLastUpdate);
    final issue = ref.watch(autoSelectionIssueProvider);
    // 穿云 1.2.1: no refresh button — opening the page brings a list older than a day up to date
    useEffect(() {
      Future.microtask(service.refreshIfStale);
      return null;
    }, const []);

    final Widget? status = switch (issue) {
      AutoSelectionResult.notFound => _AutoSelectionIssue(
        icon: Icons.cloud_off_rounded,
        text: autoSelection.noList,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      AutoSelectionResult.failure => _AutoSelectionIssue(
        icon: Icons.error_outline_rounded,
        text: autoSelection.loadFailed,
        color: theme.colorScheme.error,
      ),
      _ when isOn && lastUpdate != null => Text(
        // in hours, since the day a clock change falls in has 23 or 25 of them
        autoSelection.updated(
          n: (DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(lastUpdate)).inHours / 24).round(),
        ),
      ),
      _ => null,
    };

    // the switch already spaces the row, so the status is its subtitle;
    // smaller text and padding keep the row 48 dp with or without the status, so turning it on moves nothing
    return ListTile(
      minTileHeight: 48,
      minVerticalPadding: 6,
      titleTextStyle: theme.textTheme.bodyMedium,
      subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      title: Text(mode == AppProxyMode.exclude ? '常用国内 App 不走代理' : '常用海外 App 走代理（在线列表）'),
      subtitle: status,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // the bar takes the switch's place and keeps its space, so nothing moves
          Stack(
            alignment: Alignment.center,
            children: [
              Visibility(
                visible: !loading,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Switch(value: isOn, onChanged: service.setAutoSelection),
              ),
              if (loading)
                const SizedBox(
                  width: 52,
                  child: LinearProgressIndicator(borderRadius: BorderRadius.all(Radius.circular(2))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AutoSelectionIssue extends StatelessWidget {
  const _AutoSelectionIssue({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const Gap(4),
        Flexible(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

