// 穿云 1.3.0 - 首页 = dashboard: 「穿云」 title, a hero card (status, time · mode, big switch, current
// node → node picker) and a grid of equal tiles (网速 / 本次流量 / 剩余流量 / 到期 / 出口 IP / 去广告).
// Long-press a tile to reorder / hide. On a wide window the node list sits in a right column.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:hiddify/features/muse/data/port_override.dart';
import 'package:hiddify/features/muse/home/node_memory.dart' show museNodeSwitchingProvider;
import 'package:hiddify/features/muse/widget/muse_motion_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/activity/activity_page.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/background_guard.dart';
import 'package:hiddify/features/muse/home/changelog_dialog.dart';
import 'package:hiddify/features/muse/home/clipboard_import.dart';
import 'package:hiddify/features/muse/home/core_watchdog.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/first_guide.dart';
import 'package:hiddify/features/muse/home/health_banner.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/keep_alive_guide.dart';
import 'package:hiddify/features/muse/home/node_failover.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/home/route_map/route_share.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/connect_flow.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart' show MuseTrafficLog, museDayKey;
import 'package:hiddify/features/muse/logic/home_tiles.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/logic/service_probe.dart';
import 'package:hiddify/features/muse/logic/unlock_check.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/home/exit_detail_sheet.dart';
import 'package:hiddify/features/muse/settings/service_mode_switch.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_card.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_segmented.dart';
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart' show MuseAddAction;
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart' show OutboundGroup;
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

part 'dashboard_cards.dart';
part 'route_card.dart';

/// Content width from which the node list is shown as a right-hand column.
const museHomeSideListWidth = 1000.0;

class MuseHomePage extends HookConsumerWidget {
  const MuseHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(museHasProfileProvider);

    // 1.2.8: 更新说明, once per new version. 1.5.0: only for a feature release (x.Y); a small
    // update leaves a dot on 设置 › 关于 › 更新内容 instead.
    final appVersion = ref.watch(museAppVersionProvider);
    useEffect(() {
      if (hasProfile == null || appVersion == null) return null;
      final shown = ref.read(Preferences.museChangelogShown);
      final seen = ref.read(MusePrefs.changelogSeen);
      if (shown == appVersion) {
        // shown by a version before 1.5.0, which didn't record it as seen
        if (seen.isEmpty) Future.microtask(() => ref.read(MusePrefs.changelogSeen.notifier).update(appVersion));
        return null;
      }
      final notes = museChangelogToShow(version: appVersion, shown: shown, introDone: hasProfile);
      Future.microtask(() async {
        await ref.read(Preferences.museChangelogShown.notifier).update(appVersion);
        // a new user has nothing to compare with: nothing unread
        if (!hasProfile) await ref.read(MusePrefs.changelogSeen.notifier).update(appVersion);
        if (notes == null || !context.mounted) return;
        await showMuseChangelogDialog(context, ref, version: appVersion, notes: notes);
      });
      return null;
    }, [hasProfile, appVersion]);

    // 1.16.0 B10: 新用户一步引导 — once, on a new install only (decided before the 更新说明 effect
    // above records this version)
    final guideChecked = useRef(false);
    useEffect(() {
      if (hasProfile == null || guideChecked.value) return null;
      guideChecked.value = true;
      // read now, before the 更新说明 microtask records this version
      final shownBefore = ref.read(Preferences.museChangelogShown);
      Future.microtask(() {
        if (context.mounted) {
          return museMaybeShowFirstGuide(
            context,
            ref,
            hasProfile: hasProfile,
            changelogShown: shownBefore,
            qr: museFirstRunQr(),
          );
        }
      });
      return null;
    }, [hasProfile]);
    // the subscription added from the guide → 「现在连接？」 once
    ref.listen<bool?>(museHasProfileProvider, (prev, next) {
      if (prev != true && next == true && ref.read(museGuideAwaitConnectProvider) && context.mounted) {
        museGuideAskConnect(context, ref);
      }
    });

    // 1.3.0: a subscription link on the clipboard puts a dot on 添加 (no banner)
    useMuseClipboardWatcher(ref);
    // 1.19.1 A4 / A6: a computer window gets the desk layout. 1.19.2: no big 「穿云」 title on any
    // window or phone (the side bar's brand row and the window's title bar already say it) — the top
    // is one 48 high tool row (subscription · nodes, and 编辑首页) in its place.
    final desk = museDeskWide(context) && hasProfile == true;
    final Widget body;
    if (desk) {
      body = const MuseDeskHome();
    } else {
      final list = LayoutBuilder(
        builder: (context, constraints) {
          final dashboard = _Dashboard(hasProfile: hasProfile);
          if (constraints.maxWidth < museHomeSideListWidth || hasProfile != true) return dashboard;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: dashboard),
              SizedBox(width: MuseSize.sideColumn, child: _sideNodes(context)),
              const SizedBox(width: MuseSpace.s8),
            ],
          );
        },
      );
      body = hasProfile == true
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MuseDeskToolRow(speedTest: false),
                Expanded(child: list),
              ],
            )
          : list;
    }
    return MuseScaffold(
      large: true,
      title: Constants.appName,
      showAppBar: false,
      // no app bar: the page itself keeps clear of the status bar
      body: SafeArea(bottom: false, left: false, right: false, child: body),
    );
  }
}

/// The node list as a right-hand column (title 「节点」 over the embedded list).
Widget _sideNodes(BuildContext context) => Column(
  key: const ValueKey('home_side_nodes'),
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(MuseSpace.s16 + MuseSpace.s4, 0, MuseSpace.s16, MuseSpace.s4),
      child: Text('节点', style: MuseType.title(context)),
    ),
    const Expanded(child: MuseNodeList(embedded: true)),
  ],
);

/// 1.19.1 A4: 首页 on a computer window, laid out by the **window** width (1.19.0 compared the
/// content width with 1000, so a 1000–1219 window got the phone column stretched):
/// ≥ 900 two columns — 连接卡 + 路由图 on the left (58 %), the tiles on the right; ≥ 1280 the node
/// list as a third column. One scroll view (pull to refresh still works), no new timers.
class MuseDeskHome extends ConsumerWidget {
  const MuseDeskHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final three = width >= MuseDesk.threeColumn;
    final margin = MuseSpace.page(context);
    final scroll = RefreshIndicator(
      key: const ValueKey('home_pull_refresh'),
      onRefresh: () => museNodePull(ref),
      color: museBrandOf(context),
      notificationPredicate: (n) => n.depth == 0,
      child: ListView(
        key: const ValueKey('home_dashboard'),
        padding: EdgeInsets.fromLTRB(margin, MuseSpace.s4, three ? MuseSpace.s8 : margin, museScrollEndGap(context)),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: [
          const MuseHealthBanner(),
          Row(
            key: const ValueKey('home_desk_columns'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: (MuseDesk.leftShare * 100).round(),
                child: Column(
                  key: const ValueKey('home_desk_left'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1.19.1: 「能不能用、连到哪」 first on a computer. 1.20.0: the map is inside the card
                    const MuseHeroCard(),
                  ],
                ),
              ),
              const SizedBox(width: MuseHomeA.gap),
              Expanded(
                flex: 100 - (MuseDesk.leftShare * 100).round(),
                child: Column(
                  key: const ValueKey('home_desk_right'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const MuseTileGrid(),
                    const SizedBox(height: MuseSpace.s8),
                    Center(
                      child: TextButton.icon(
                        key: const ValueKey('home_edit_tiles'),
                        style: TextButton.styleFrom(foregroundColor: museBrandOf(context), shape: MuseShape.full),
                        onPressed: () => showMuseTileEditor(context),
                        icon: const Icon(Icons.dashboard_customize_outlined, size: MuseIconSize.small),
                        label: const Text('编辑首页'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MuseDeskToolRow(),
        Expanded(
          // 1.19.2: two columns only when the page itself (window minus the side bar) has room for
          // them; a narrower one gets the single column under the same tool row
          child: LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < MuseDesk.twoColumnContent) return const _Dashboard(hasProfile: true);
              return three
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: scroll),
                        SizedBox(width: MuseDesk.nodeColumn, child: _sideNodes(context)),
                        const SizedBox(width: MuseSpace.s8),
                      ],
                    )
                  : scroll;
            },
          ),
        ),
      ],
    );
  }
}

/// 1.19.1 A6: the desk 首页's top row in place of the big 「穿云」 title: 「订阅名 · 38 个节点」 on the
/// left, 测速 and 编辑首页 on the right (48 high).
class MuseDeskToolRow extends ConsumerWidget {
  const MuseDeskToolRow({super.key, this.speedTest = true});

  /// 1.19.2: the row also tops a phone's 首页 (in place of the 「穿云」 title), without 测速 there
  final bool speedTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final name = ref.watch(museActiveProfileNameProvider)?.trim();
    final group = ref.watch(museNodeGroupProvider).valueOrNull;
    final nodes = group?.items.where((e) => !e.isGroup).length;
    final running = ref.watch(museRunningProvider);
    final testing = ref.watch(museNodeTestStartedProvider) != null;
    final summary = [if (name != null && name.isNotEmpty) name, if (nodes != null) '$nodes 个节点'].join(' · ');
    final margin = MuseSpace.page(context);
    return SizedBox(
      key: const ValueKey('home_desk_toolbar'),
      height: MuseDesk.toolRow,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: margin, end: margin - MuseSpace.s8),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: summary,
                child: Text(
                  summary,
                  key: const ValueKey('home_desk_summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // 1.20.0 方向 A: 15 / w400 secondary — the card titles' weight, not a heading
                  style: MuseTextLevel.subheadline.style(context, color: mt.text2),
                ),
              ),
            ),
            const SizedBox(width: MuseSpace.s8),
            // ≥ 1280 the node column beside has its own 测速
            if (speedTest && MediaQuery.sizeOf(context).width < MuseDesk.threeColumn)
              TextButton.icon(
                key: const ValueKey('home_desk_speedtest'),
                style: TextButton.styleFrom(foregroundColor: museBrandOf(context), shape: MuseShape.full),
                // 测速 needs a running core (the same rule as on 节点)
                onPressed: running && !testing ? () => museRunNodeTest(ref) : null,
                icon: const Icon(Icons.speed_outlined, size: MuseIconSize.small),
                label: Text(testing ? '测速中' : '测速'),
              ),
            IconButton(
              key: const ValueKey('home_edit_button'),
              tooltip: '编辑首页',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showMuseTileEditor(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.hasProfile});

  final bool? hasProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final margin = MuseSpace.page(context);
    // 1.5.0: the dashboard's outline while the subscriptions are read
    if (hasProfile == null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(margin, MuseSpace.s4, margin, museScrollEndGap(context)),
        children: [MuseSkeleton.dashboard()],
      );
    }
    if (hasProfile == false) return const _EmptyState();
    // 1.19.0: 新首页 = 路由弧线图 + 经典首页的全部内容；经典首页 = 1.18 的首页原样
    // 1.20.0: the map is the connect card's middle now (MuseHeroCard reads the style itself)
    return RefreshIndicator(
      key: const ValueKey('home_pull_refresh'),
      onRefresh: () => museNodePull(ref),
      color: museBrandOf(context),
      notificationPredicate: (n) => n.depth == 0,
      child: ListView(
        key: const ValueKey('home_dashboard'),
        padding: EdgeInsets.fromLTRB(margin, MuseSpace.s4, margin, museScrollEndGap(context)),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: [
          // 1.13.0: 安全模式 / 被其他 VPN 断开 / 上次异常 / 连接没有成功 (only when one applies)
          const MuseHealthBanner(),
          const MuseHeroCard(),
          const SizedBox(height: MuseHomeA.gap),
          const MuseTileGrid(),
          const SizedBox(height: MuseSpace.s8),
          // 1.6.3: the editor at the end of the tiles too
          Center(
            child: TextButton.icon(
              key: const ValueKey('home_edit_tiles'),
              style: TextButton.styleFrom(foregroundColor: museBrandOf(context), shape: MuseShape.full),
              onPressed: () => showMuseTileEditor(context),
              icon: const Icon(Icons.dashboard_customize_outlined, size: MuseIconSize.small),
              label: const Text('编辑首页'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- hero card

/// 1.5.0: the core's status as the connect button sees it; [preparing] (config being built, the
/// core not asked yet) counts as connecting.
MuseLinkState museLinkStateOf(ConnectionStatus? status, {bool preparing = false}) => switch (status) {
  Connected() => MuseLinkState.connected,
  Connecting() => MuseLinkState.connecting,
  Disconnecting() => MuseLinkState.disconnecting,
  _ => preparing ? MuseLinkState.connecting : MuseLinkState.disconnected,
};

enum _HeroState { idle, connecting, connected }

class MuseHeroCard extends HookConsumerWidget {
  const MuseHeroCard({super.key});

  /// 1.6.0 C11: how many times the card was built (the perf test reads it).
  @visibleForTesting
  static int debugBuilds = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugBuilds++;
    final mt = MuseTheme.of(context);
    final connection = ref.watch(museConnectionProvider);
    // first time connected: one-time 「允许后台运行」 hint (1.10.0: the only background prompt left)
    ref.listen(museConnectionProvider, (prev, next) {
      if (prev?.valueOrNull is! Connected && next.valueOrNull is Connected) museMaybeShowKeepAliveGuide(context, ref);
    });
    // 1.4.1 Android: killed by the system in the background since the last start → recorded only
    // (1.10.0: no dialog)
    useEffect(() {
      if (!PlatformUtils.isAndroid) return null;
      unawaited(museCheckBackgroundKill(ref));
      return null;
    }, const []);
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;
    final recovering = ref.watch(museWatchdogRecoveringProvider);
    final failoverFrom = ref.watch(museFailoverFromProvider);
    final mode = ref.watch(ConfigOptions.museRouteMode);

    // 1.6.0 C11: the timer ticks in its own small widget (the card no longer rebuilds every second)

    final status = connection.valueOrNull;
    final connected = status is Connected;
    // 1.5.0: 准备配置 (the core not asked yet) already counts as connecting
    final preparing =
        ref.watch(museConnectPreparingProvider) && !(status?.isConnected ?? false) && !(status?.isSwitching ?? false);
    final link = museLinkStateOf(status, preparing: preparing);
    final busy = link == MuseLinkState.connecting || link == MuseLinkState.disconnecting;
    final recoveringNow = PlatformUtils.isWindows && recovering && status is Connecting;
    final failed = connection.hasError && !connected && !busy;
    final state = connected ? _HeroState.connected : (busy ? _HeroState.connecting : _HeroState.idle);
    final reach = ref.watch(museReachProvider);
    final stage = museConnectStageFor(
      link,
      preparing: preparing,
      reachChecking: reach == MuseReach.checking || reach == MuseReach.unknown,
    );
    final label = switch (link) {
      MuseLinkState.connected => '已连接',
      MuseLinkState.connecting when recoveringNow => '正在恢复',
      MuseLinkState.connecting => '连接中',
      MuseLinkState.disconnecting => '断开中',
      _ when failed => '连接失败',
      _ => '未连接',
    };
    // 1.5.0: the button as a state machine — 连接中 cancels, 断开中 ignores taps
    final action = museConnectActionFor(link);

    Future<void> toggle() async {
      final notifier = ref.read(connectionNotifierProvider.notifier);
      if (action == MuseConnectAction.ignore) return;
      if (action == MuseConnectAction.connect && ref.read(museActiveProfileIdProvider) == null) {
        await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
        return;
      }
      await notifier.toggleConnection();
    }

    // 1.20.0 方向 A: the card stays neutral in every state — colour lives on the map only (the
    // node's country), the ▶ glyph and the status lights
    final fg = mt.text1;
    final fg2 = mt.text2;
    final switchEnabled = action != MuseConnectAction.ignore;
    final desk = museDeskWide(context);
    final pad = desk ? MuseHomeA.padDesk : MuseHomeA.pad;
    final classic = ref.watch(MusePrefs.homeStyle) == 'classic';

    final statusRow = Row(
      children: [
        Flexible(
          child: AnimatedSwitcher(
            duration: museMotion(context),
            switchInCurve: museCurve(context),
            child: MuseSweep(
              key: ValueKey(label),
              active: link == MuseLinkState.connecting,
              child: Text(
                label,
                key: ValueKey(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MuseTextLevel.title1.style(
                  context,
                  color: failed ? MusePalette.red : fg,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        if (connected && recovering)
          Padding(
            padding: const EdgeInsets.only(left: MuseSpace.s8),
            child: Icon(
              Icons.autorenew_outlined,
              key: const ValueKey('watchdog_icon'),
              size: MuseIconSize.small,
              color: fg2,
            ),
          ),
        if (connected && failoverFrom != null)
          Padding(
            padding: const EdgeInsets.only(left: MuseSpace.s8),
            child: Icon(
              Icons.swap_horiz_outlined,
              key: const ValueKey('failover_icon'),
              size: MuseIconSize.small,
              color: fg2,
            ),
          ),
      ],
    );
    final second = MuseTextLevel.subheadline.style(context, color: fg2);
    final statusInfo = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: MuseSpace.s12,
      runSpacing: MuseSpace.s4,
      children: [
        // 1.5.0: 准备配置 → 启动核心 → 测试连通
        if (stage != null && !connected)
          AnimatedSwitcher(
            duration: museMotion(context),
            child: Text(
              '${stage.title}…',
              key: ValueKey('home_stage_${stage.name}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: second,
            ),
          )
        else if (since != null)
          MuseUptimeText(
            since: since,
            style: second.copyWith(fontFamily: MuseFont.family, fontFamilyFallback: MuseFont.fallback),
          ),
        if (stage == null || connected) _ModePill(mode: mode),
        if (stage == MuseConnectStage.testing && connected)
          Text(
            '${stage!.title}…',
            key: const ValueKey('home_stage_testing'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MuseTextLevel.footnote.style(context, color: fg2),
          ),
      ],
    );
    final startButton = MuseStartButton(
      key: const ValueKey('home_connect_switch'),
      on: connected || busy,
      semanticLabel: switch (action) {
        MuseConnectAction.cancel => '取消连接',
        MuseConnectAction.disconnect => '断开',
        _ => '连接',
      },
      onTap: switchEnabled ? toggle : null,
    );

    final header = Material(
      type: MaterialType.transparency,
      child: InkWell(
        // the whole top connects while disconnected
        onTap: state == _HeroState.idle && action == MuseConnectAction.connect ? toggle : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad - MuseHomeA.padEndTrim, classic ? pad : 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  key: const ValueKey('home_status_block'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    statusRow,
                    const SizedBox(height: MuseSpace.s8),
                    statusInfo,
                  ],
                ),
              ),
              const SizedBox(width: MuseSpace.s12),
              startButton,
            ],
          ),
        ),
      ),
    );

    final card = DecoratedBox(
      key: const ValueKey('home_hero_card'),
      decoration: mt.cardDecoration(radius: MuseHomeA.cardAll),
      child: ClipRSuperellipse(
        borderRadius: MuseHomeA.cardAll,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            // 1.20.0: the map is the card's middle (经典首页 keeps the 1.18 card without it)
            if (!classic) ...[MuseHeroMap(surface: mt.card), MuseHeroRouteNotes(padding: pad)],
            _HeroNodeRow(large: desk, pad: pad),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: '连接',
      child: KeyedSubtree(key: const ValueKey('home_connect_section'), child: card),
    );
  }
}

/// 「规则模式」 / 「全局模式」: tap to switch.
/// 1.6.0 C11: 已连接 time, ticking once a second on its own (only this text rebuilds).
class MuseUptimeText extends HookWidget {
  const MuseUptimeText({super.key, required this.since, this.style});

  final DateTime since;
  final TextStyle? style;

  @visibleForTesting
  static int debugBuilds = 0;

  /// 1.6.1: timers currently running (tests: none while hidden or in the background).
  @visibleForTesting
  static int debugActiveTimers = 0;

  @override
  Widget build(BuildContext context) {
    debugBuilds++;
    final tick = useState(0);
    // 1.6.1 省电: tick only while the page is on screen (another tab mutes its tickers) and the
    // app is in the foreground; coming back shows the right time at once.
    final visible = TickerMode.of(context);
    final life = useAppLifecycleState();
    final active = visible && (life == null || life == AppLifecycleState.resumed);
    useEffect(() {
      if (!active) return null;
      debugActiveTimers++;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => tick.value++);
      return () {
        timer.cancel();
        debugActiveTimers--;
      };
    }, [since, active]);
    return Text(
      museFormatDuration(DateTime.now().difference(since)),
      key: const ValueKey('home_timer'),
      maxLines: 1,
      style: style,
    );
  }
}

class _ModePill extends ConsumerWidget {
  const _ModePill({required this.mode});

  final MuseRouteMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    return Material(
      color: mt.inner,
      shape: MuseShape.full,
      child: InkWell(
        key: const ValueKey('home_mode_pill'),
        customBorder: MuseShape.full,
        onTap: () => ref
            .read(ConfigOptions.museRouteMode.notifier)
            .update(mode == MuseRouteMode.rule ? MuseRouteMode.global : MuseRouteMode.rule),
        // 1.20.0: 28 high at 1×, grows with the text (never clips at 2×)
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: MuseHomeA.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: museMotion(context),
                  child: Text(
                    '${mode.title}模式',
                    key: ValueKey(mode),
                    style: MuseTextLevel.footnote.style(context, color: mt.text1, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: MuseSpace.s4),
                Icon(Icons.swap_horiz_outlined, size: MuseHomeA.pillIcon, color: mt.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero card's start button.
/// 1.20.0 方向 A: a 56 neutral circle (the card's inner tone) — ▶ in the 已连接 colour (the one accent
/// while disconnected), ❚❚ in the text colour; the glyph cross-fades. The 1.18 circle ↔ rounded-square
/// morph is gone with the filled accent button (方向 A keeps one round shape).
class MuseStartButton extends StatefulWidget {
  const MuseStartButton({
    super.key,
    required this.on,
    required this.onTap,
    required this.semanticLabel,
    this.size = MuseHomeA.button,
  });

  final double size;

  final bool on;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  State<MuseStartButton> createState() => MuseStartButtonState();
}

/// 1.19.1：按压反馈——按下缩到 [MuseMotion.pressScale]（100ms），松开/取消 160ms 回 1.0；
/// 禁用（onTap == null）与关闭档不缩；精简档时长 ×0.6、平稳曲线。隐式动画，可从当前值重定向。
class MuseStartButtonState extends State<MuseStartButton> {
  bool _pressed = false;

  /// 测试用：当前是否处于按下状态。
  bool get pressed => _pressed;

  void _press(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  void didUpdateWidget(MuseStartButton old) {
    super.didUpdateWidget(old);
    if (widget.onTap == null) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.on;
    final onTap = widget.onTap;
    final mt = MuseTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final level = museMotionLevel(context);
    final canPress = onTap != null && level != MuseMotionLevel.off;
    final scale = canPress && _pressed ? MuseMotion.pressScale : 1.0;
    final glyph = on ? mt.text1 : museLinkedColor(scheme, mt.inner);
    return Semantics(
      button: true,
      toggled: on,
      enabled: onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onTapDown: canPress ? (_) => _press(true) : null,
        onTapUp: canPress ? (_) => _press(false) : null,
        onTapCancel: canPress ? () => _press(false) : null,
        child: AnimatedScale(
          key: const ValueKey('home_connect_press'),
          scale: scale,
          duration: museScaleDuration(level, _pressed ? MuseMotion.pressIn : MuseMotion.pressOut),
          curve: museCurve(context),
          child: DecoratedBox(
            key: const ValueKey('home_connect_shape'),
            decoration: ShapeDecoration(
              color: onTap == null ? mt.inner.withValues(alpha: 0.5) : mt.inner,
              shape: const CircleBorder(),
            ),
            child: SizedBox.square(
              dimension: widget.size,
              child: AnimatedSwitcher(
                duration: museDuration(context, MuseMotion.fast),
                switchInCurve: MuseMotion.curve,
                switchOutCurve: MuseMotion.exitCurve,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: child),
                ),
                child: Icon(
                  on ? Icons.pause_outlined : Icons.play_arrow_outlined,
                  key: ValueKey(on),
                  size: MuseHomeA.buttonGlyph,
                  color: onTap == null ? glyph.withValues(alpha: 0.5) : glyph,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.19.1: [child] with a hover tooltip of [message] (none when null).
Widget museMaybeTooltip(String? message, Widget child) =>
    message == null ? child : Tooltip(message: message, child: child);

/// 1.18.0 P3: the node-name sweep stops after this even if the core never answers.
const museSwitchSweepTimeout = Duration(seconds: 10);

/// Bottom row of the hero card: flag | current node | latency ›  (opens the node picker).
/// 1.20.0 方向 A: name 16 / w600 over 「地区 · 协议」 13, a status dot + the delay 15 with 「ms」 13 apart.
class _HeroNodeRow extends ConsumerWidget {
  const _HeroNodeRow({this.large = false, required this.pad});

  /// 1.19.1 A5: the desk card's row (name 17, delay 17; the full name on hover)
  final bool large;

  /// the card's side padding (the row lines up with the status above)
  final double pad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final group = ref.watch(museNodeGroupProvider).valueOrNull;
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;
    final item = group?.items.where((e) => e.tag == group.selected).firstOrNull;
    final shown = ref.watch(museShownPickProvider);
    final switching = ref.watch(museNodeSwitchingProvider);
    final fg = mt.text1;
    final fg2 = mt.text2;
    String text = '选择节点';
    String? flag;
    IconData icon = Icons.public_outlined;
    if (item != null) {
      final full = museNodeName(item);
      if (item.isGroup) {
        final rawName = full.split(' → ').first.trim();
        final kind = museGroupKind(type: item.type, name: rawName, selectedDisplay: item.groupSelectedTagDisplay);
        final sel = item.groupSelectedTagDisplay.trim();
        final rawPick = kind == '负载均衡' || sel.toLowerCase() == 'lowest-delay' || museBalanceStrategyName(sel) != null
            ? ''
            : sel;
        // 1.5.3: the pick reads like its row on 节点 (renamed / tidied)
        final pick = rawPick.isEmpty || museKnownGroupName(rawPick) != null ? rawPick : shown(rawPick);
        text = museCurrentNodeText(name: rawName, groupLabel: museGroupName(rawName), groupPick: museGroupName(pick));
        flag = pick.isEmpty ? null : museFlagEmoji(pick);
        icon = Icons.bolt_outlined;
        text = museStripFlags(text);
      } else {
        final name = shown(full);
        flag = museFlagEmoji(name) ?? museFlagEmoji(full);
        text = museStripFlags(name);
      }
    }
    final delay = item == null ? 0 : museFreshDelay(item, since);
    final showDelay = delay > 0 && ConnectionConst.isValidDelay(delay);
    // 1.11.0: the same look as a card on 节点 (A): region small above the bold name, the protocol
    // as a small tag, the delay as a coloured number with a small 「ms」
    final regionCode = item == null || item.isGroup ? null : museRegionCode(museNodeName(item));
    final protocol = item == null || item.isGroup ? '' : museNodeProtocolShort(item);
    final caption = item == null
        ? ''
        : item.isGroup
        ? '自动选择'
        : [if (regionCode != null) museCountryLabel(regionCode), if (protocol.isNotEmpty) protocol].join(' · ');
    final digits = TextStyle(fontFamily: MuseFont.family, fontFamilyFallback: MuseFont.fallback);
    final nameStyle = (large ? MuseTextLevel.headline : MuseTextLevel.callout)
        .style(context, color: fg, weight: FontWeight.w600)
        .merge(digits);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('home_current_node'),
        onTap: () => showMuseNodePicker(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: MuseSize.heroRow),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              pad,
              MuseHomeA.nodeRowTop,
              pad - MuseHomeA.nodeRowEndTrim,
              MuseHomeA.nodeRowBottom,
            ),
            child: Row(
              children: [
                MuseFlagBox(flag: flag, icon: icon, circle: true),
                const SizedBox(width: MuseSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1.18.0 P3: the name rolls when it changes and sweeps while switching
                      // 1.19.1 A5: the full name on hover when the desk row cuts it
                      museMaybeTooltip(
                        large ? text : null,
                        MuseRoll(
                          value: text,
                          child: MuseSweep(
                            active: switching != null,
                            timeout: museSwitchSweepTimeout,
                            child: Text(
                              text,
                              key: const ValueKey('home_node_name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                          ),
                        ),
                      ),
                      if (caption.isNotEmpty) ...[
                        const SizedBox(height: MuseSpace.s4 / 2),
                        Text(
                          caption,
                          key: const ValueKey('home_node_caption'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MuseTextLevel.footnote.style(context, color: fg2).merge(digits),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showDelay) ...[
                  const SizedBox(width: MuseSpace.s8),
                  Container(
                    width: MuseHomeA.delayDot,
                    height: MuseHomeA.delayDot,
                    decoration: BoxDecoration(color: MuseColors.delay(context, delay), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: MuseSpace.s4 + MuseSpace.s4 / 2),
                  MuseRoll(
                    value: delay,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text.rich(
                      key: const ValueKey('home_node_delay'),
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$delay',
                            style: (large ? MuseTextLevel.headline : MuseTextLevel.subheadline)
                                .style(context, color: fg, weight: FontWeight.w500)
                                .merge(digits),
                          ),
                          TextSpan(
                            text: '\u00A0ms',
                            style: MuseTextLevel.footnote.style(context, color: fg2).merge(digits),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: MuseSpace.s4 / 2),
                Icon(Icons.chevron_right_outlined, size: MuseIconSize.small, color: mt.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- tiles

/// The tile grid: every tile the same height, 2 columns on a phone, 3–4 on the desktop.
/// 1.4.0: the column count follows the number of tiles so no row is left with a lone tile (the
/// last row's tiles stretch); on Windows 网速 + 本次流量 are one 「流量」 tile.
class MuseTileGrid extends ConsumerWidget {
  const MuseTileGrid({super.key, this.mergeFlow});

  /// null = Windows only.
  final bool? mergeFlow;

  static const tileHeight = MuseHomeA.tile;
  static const tileHeightDesktop = MuseHomeA.tileDesk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(museSubInfoProvider);
    final windows = PlatformUtils.isWindows;
    final order = museParseTileOrder(ref.watch(Preferences.museHomeTileOrder));
    final hidden = museParseHiddenTiles(ref.watch(Preferences.museHomeTilesHidden));
    var tiles = museVisibleTiles(
      order,
      hidden,
      hasData: (t) => switch (t) {
        MuseHomeTile.remaining => museHasTrafficCap(info),
        MuseHomeTile.expiry => museHasExpiry(info),
        MuseHomeTile.takeover => windows,
        _ => true,
      },
    );
    if (mergeFlow ?? PlatformUtils.isWindows) tiles = museMergeFlowTiles(tiles);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = museTileColumnsFor(
          constraints.maxWidth,
          tiles.length,
          textScale: MediaQuery.textScalerOf(context).scale(MuseType.numberSize) / MuseType.numberSize,
        );
        final base = constraints.maxWidth >= 600 ? tileHeightDesktop : tileHeight;
        // 1.4.1: large text grows the row instead of overflowing the fixed tile height
        // 1.5.1: the 去广告 tile's segmented control needs a taller bottom slot
        final bottom = tiles.contains(MuseHomeTile.adBlock) || tiles.contains(MuseHomeTile.takeover)
            ? MuseSize.segmented
            : MuseSize.tileBottom;
        final height = math.max(base, museTileHeightFor(MediaQuery.textScalerOf(context), bottom: bottom));
        final rows = <Widget>[];
        for (final idx in museTileRows(tiles.length, columns)) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: MuseHomeA.gap));
          rows.add(
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < idx.length; j++) ...[
                    if (j > 0) const SizedBox(width: MuseHomeA.gap),
                    Expanded(child: RepaintBoundary(child: _tile(tiles[idx[j]]))),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(key: const ValueKey('home_tiles'), children: rows);
      },
    );
  }

  static Widget _tile(MuseHomeTile t) => switch (t) {
    MuseHomeTile.speed => const _SpeedTile(key: ValueKey('tile_speed')),
    MuseHomeTile.traffic => const _TrafficTile(key: ValueKey('tile_traffic')),
    MuseHomeTile.remaining => const _RemainingTile(key: ValueKey('tile_remaining')),
    MuseHomeTile.expiry => const _ExpiryTile(key: ValueKey('tile_expiry')),
    MuseHomeTile.exit => const _ExitTile(key: ValueKey('tile_exit')),
    MuseHomeTile.adBlock => const _AdBlockTile(key: ValueKey('tile_adblock')),
    MuseHomeTile.flow => const _FlowTile(key: ValueKey('tile_flow')),
    MuseHomeTile.services => const _ServicesTile(key: ValueKey('tile_services')),
    MuseHomeTile.groups => const _GroupsTile(key: ValueKey('tile_groups')),
    MuseHomeTile.connections => const _ConnectionsTile(key: ValueKey('tile_connections')),
    MuseHomeTile.lanIp => const _LanIpTile(key: ValueKey('tile_lanip')),
    MuseHomeTile.memory => const _MemoryTile(key: ValueKey('tile_memory')),
    MuseHomeTile.takeover => const _TakeoverTile(key: ValueKey('tile_takeover')),
  };
}

/// 1.4.1: height a tile needs at [scaler]: padding + title caption + big number + bottom element
/// (all scaled with the text) + a little slack.
/// 1.5.1: [bottom] is the tallest bottom element in the grid ([MuseSize.segmented] with 去广告).
/// 1.6.1: the title is a subheadline (15 / 20) now, not a caption.
/// 1.20.0 方向 A: padding 20, the title a footnote (13 / 18), the number 26 / 1.15 — the row grows with
/// the system font size (1.3×, 2×) instead of a fixed height.
double museTileHeightFor(TextScaler scaler, {double bottom = MuseSize.tileBottom}) =>
    MuseHomeA.pad * 2 + scaler.scale(MuseHomeA.titleBox + MuseHomeA.valueBox + bottom) + MuseSpace.s8;

/// 1.20.0 方向 A: 「↓ 2.0 KB/s」 → (lead 「↓」, number 「2.0」, unit 「KB/s」); 「28 天」 → (null, 「28」, 「天」);
/// anything else (「已用完」「检测中」「—」「🇯🇵 东京 02」) is one value. The last space splits the unit off.
(String?, String, String?) museSplitValue(String value) {
  var v = value.trim();
  String? lead;
  for (final a in const ['↓', '↑']) {
    if (v.startsWith(a)) {
      lead = a;
      v = v.substring(a.length).trimLeft();
      break;
    }
  }
  // only 「number unit」 splits (「🇯🇵 东京 02」 or 「192.168.1.23」 stay whole)
  final i = v.lastIndexOf(' ');
  if (i > 0) {
    final n = v.substring(0, i);
    final u = v.substring(i + 1);
    if (RegExp(r'^[-+]?[\d.,]+$').hasMatch(n) && u.isNotEmpty && !RegExp('[0-9]').hasMatch(u)) return (lead, n, u);
  }
  return (lead, v, null);
}

/// 1.20.0 方向 A: a tile's number — digits 26 / w600 tabular, the unit 14 in the secondary colour
/// after a no-break space, an arrow lead in the secondary colour; text values (「已用完」) 21 / w600.
Widget museTileValue(BuildContext context, String value, {Color? color, Key? key}) {
  final mt = MuseTheme.of(context);
  final (lead, number, unit) = museSplitValue(value);
  final digits = RegExp('[0-9]').hasMatch(number);
  final base = TextStyle(
    fontFamily: MuseFont.family,
    fontFamilyFallback: MuseFont.fallback,
    height: MuseHomeA.valueLine,
    fontFeatures: MuseType.tabular,
  );
  final big = base.copyWith(
    fontSize: digits ? MuseHomeA.value : MuseTextLevel.title3.size,
    fontWeight: FontWeight.w600,
    letterSpacing: digits ? MuseHomeA.valueTrack : 0,
    color: color ?? mt.text1,
  );
  final small = base.copyWith(fontSize: MuseHomeA.unit, fontWeight: FontWeight.w500, color: mt.text2);
  return Text.rich(
    key: key,
    TextSpan(
      children: [
        if (lead != null)
          TextSpan(
            text: '$lead\u00A0',
            style: big.copyWith(color: mt.text2, fontWeight: FontWeight.w400),
          ),
        TextSpan(text: number, style: big),
        if (unit != null) TextSpan(text: '\u00A0$unit', style: small),
      ],
    ),
    maxLines: 1,
  );
}

/// 1.20.0 方向 A: a tile's captions (title trailing, bottom line) — 13 secondary, tabular digits.
/// (The app's own face: an exit tile's flag emoji falls back glyph by glyph as before.)
TextStyle museTileCaption(BuildContext context) =>
    MuseTextLevel.footnote.style(context, color: MuseTheme.of(context).text2);

/// Max share of a tile row a trailing caption may take before it ellipsizes.
const _trailingShare = 0.6;

bool museHasTrafficCap(SubscriptionInfo? info) => info != null && info.total > 0 && !info.total.isInfinitSize();

bool museHasExpiry(SubscriptionInfo? info) {
  if (info == null) return false;
  final year = info.expire.year;
  return year > 1971 && year < 2100;
}

/// One tile: small title (+ optional trailing) → big number → bottom element.
class _Tile extends ConsumerWidget {
  const _Tile({
    required this.title,
    this.titleTrailing,
    required this.value,
    this.valueColor,
    required this.bottom,
    this.bottomHeight = MuseSize.tileBottom,
    this.onTap,
  });

  final String title;
  final Widget? titleTrailing;
  final String value;
  final Color? valueColor;
  final Widget bottom;

  /// 1.5.1: height of the bottom slot before text scaling
  final double bottomHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    // 1.4.0: 隐私模式 blurs the numbers (设置 › 外观)
    final masked = ref.watch(MusePrefs.privacyMask);
    return DecoratedBox(
      decoration: mt.cardDecoration(radius: MuseHomeA.cardAll),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: MuseHomeA.cardAll,
          onTap: onTap,
          onLongPress: () => showMuseTileEditor(context),
          child: Padding(
            padding: const EdgeInsets.all(MuseHomeA.pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 1.4.1: the trailing caption ellipsizes in a narrow tile / at large text
                LayoutBuilder(
                  builder: (context, c) {
                    final titleStyle = MuseTextLevel.footnote.style(context, color: mt.text2);
                    // 1.20.0: a short title (「网速」) leaves the rest of the row to the trailing caption,
                    // so 「↑ 1.0 KB/s」 is not cut at 800 px; a long title still keeps its share
                    final tp = TextPainter(
                      text: TextSpan(text: title, style: titleStyle),
                      textDirection: TextDirection.ltr,
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: 1,
                    )..layout();
                    final trailingMax = math.max(c.maxWidth * _trailingShare, c.maxWidth - tp.width - MuseSpace.s8);
                    tp.dispose();
                    return Row(
                      children: [
                        Expanded(
                          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                        ),
                        if (titleTrailing != null)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: trailingMax),
                            child: DefaultTextStyle.merge(
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: museTileCaption(context),
                              child: museMaybeMask(masked, titleTrailing!),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                AnimatedSwitcher(
                  duration: museMotion(context),
                  transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                  // 1.5.0: a long number shrinks to fit instead of ending in 「…」 (narrow tile, large text)
                  child: museMaybeMask(
                    masked,
                    FittedBox(
                      key: ValueKey(value),
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: museTileValue(context, value, color: valueColor),
                    ),
                  ),
                ),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(bottomHeight),
                  // one line: a caption never wraps into a clipped second line
                  child: DefaultTextStyle.merge(
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: museTileCaption(context),
                    child: museMaybeMask(masked, bottom),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.11.0: the 网速 tile is idle (shows 今日流量 instead) while disconnected, or connected with the
/// last few samples all under 1 KB/s (a short pause in traffic does not flip it back and forth).
bool museSpeedIdle({required bool running, required List<int> history}) {
  if (!running) return true;
  if (history.length < 3) return false;
  return history.skip(history.length - 3).every((v) => v < 1024);
}

/// 1.11.0: today's ↑ / ↓ bytes from the traffic log.
(int, int) museTodayTraffic(String rawLog, DateTime now) =>
    MuseTrafficLog.parse(rawLog).days[museDayKey(now)] ?? (0, 0);

class _SpeedTile extends ConsumerWidget {
  const _SpeedTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(museStatsProvider);
    final history = ref.watch(museSpeedHistoryProvider);
    if (museSpeedIdle(running: ref.watch(museRunningProvider), history: history)) {
      final (up, down) = museTodayTraffic(ref.watch(MusePrefs.trafficLog), DateTime.now());
      return _Tile(
        title: '今日流量',
        value: museBytes(up + down),
        bottom: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            '↑ ${museBytes(up)}   ↓ ${museBytes(down)}',
            key: const ValueKey('tile_speed_today'),
            maxLines: 1,
            style: museTileCaption(context),
          ),
        ),
        onTap: () => _showSessionSheet(context),
      );
    }
    return _Tile(
      title: '网速',
      titleTrailing: Text('↑ ${museSpeedText(stats.uplink.toInt())}', style: museTileCaption(context)),
      value: '↓ ${museSpeedText(stats.downlink.toInt())}',
      bottom: SizedBox.expand(child: museSpeedChart(context, ref, history)),
      onTap: () => _showSessionSheet(context),
    );
  }
}

/// 1.4.0 Windows: 网速 + 本次流量 — ↓ live speed (big) with the sparkline, ↑ speed and this
/// session's ↑ / ↓ totals as captions.
class _FlowTile extends ConsumerWidget {
  const _FlowTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(museStatsProvider);
    final history = ref.watch(museSpeedHistoryProvider);
    final up = stats.uplinkTotal.toInt();
    final down = stats.downlinkTotal.toInt();
    return _Tile(
      title: '流量',
      titleTrailing: Text('↑ ${museSpeedText(stats.uplink.toInt())}', style: museTileCaption(context)),
      value: '↓ ${museSpeedText(stats.downlink.toInt())}',
      bottom: Row(
        children: [
          Expanded(flex: 2, child: SizedBox.expand(child: museSpeedChart(context, ref, history))),
          const SizedBox(width: MuseSpace.s12),
          // 1.4.1: may shrink (ellipsis) in a narrow tile / large text instead of overflowing
          Flexible(
            flex: 3,
            child: Text(
              '本次 ↑ ${museBytes(up)}  ↓ ${museBytes(down)}',
              key: const ValueKey('flow_session'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: museTileCaption(context).copyWith(fontFeatures: MuseType.tabular),
            ),
          ),
        ],
      ),
      onTap: () => _showSessionSheet(context),
    );
  }
}

/// 1.19.0 P4：新首页上网速图按路由颜色堆叠成柱（每根柱 = 一次网速读数，按本次连接各类占比分段，
/// 其余流量用主色）；经典首页或还没有分类数据时退回原来的单色折线。只随已有网速读数重画，不另开计时器。
Widget museSpeedChart(BuildContext context, WidgetRef ref, List<int> history) {
  final hairline = MuseTheme.of(context).hairline;
  final brand = museBrandOf(context);
  final classic = ref.watch(MusePrefs.homeStyle) == 'classic';
  ref.watch(museRouteShareProvider.select((s) => s.signature));
  final shares = classic ? const <(MuseRouteKind, double)>[] : ref.read(museRouteShareProvider).shares();
  if (shares.isEmpty) return CustomPaint(painter: _SparklinePainter(history, brand, hairline));
  final colors = museRouteKindColors(Theme.of(context).colorScheme);
  return CustomPaint(
    key: const ValueKey('speed_stacked_bars'),
    painter: MuseStackedBarsPainter(history, [for (final (k, v) in shares) (colors[k]!, v)], brand, hairline),
  );
}

/// 堆叠速度柱：[segments] 为（颜色, 占比）从下往上，剩下的占比画成 [rest] 色。
class MuseStackedBarsPainter extends CustomPainter {
  MuseStackedBarsPainter(this.values, this.segments, this.rest, this.baseline);

  final List<int> values;
  final List<(Color, double)> segments;
  final Color rest;
  final Color baseline;

  /// 一根柱从下往上各段的高度（像素），总和 = [h]。
  static List<double> split(double h, List<double> shares) {
    final out = <double>[];
    var used = 0.0;
    for (final v in shares) {
      final seg = (h * v.clamp(0.0, 1.0)).clamp(0.0, h - used);
      out.add(seg);
      used += seg;
    }
    out.add(h - used);
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final y0 = size.height - 1;
    canvas.drawLine(
      Offset(0, y0),
      Offset(size.width, y0),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
    if (values.isEmpty) return;
    final maxV = math.max(values.reduce(math.max), 1);
    final slot = size.width / MuseSpeedHistory.length;
    final w = math.max(slot - MuseSize.barGap, 1.0);
    final start = size.width - slot * values.length;
    final shares = [for (final s in segments) s.$2];
    final paint = Paint();
    for (var i = 0; i < values.length; i++) {
      final h = (values[i] / maxV) * (size.height - 2);
      if (h <= 0) continue;
      final x = start + slot * i + MuseSize.barGap / 2;
      var y = y0;
      final parts = split(h, shares);
      for (var j = 0; j < parts.length; j++) {
        if (parts[j] <= 0) continue;
        paint.color = j < segments.length ? segments[j].$1 : rest;
        canvas.drawRect(Rect.fromLTWH(x, y - parts[j], w, parts[j]), paint);
        y -= parts[j];
      }
    }
  }

  @override
  bool shouldRepaint(MuseStackedBarsPainter old) =>
      old.values != values || old.rest != rest || old.segments.toString() != segments.toString();
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color, this.baseline);

  final List<int> values;
  final Color color;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final y0 = size.height - 1;
    if (values.length < 2) {
      canvas.drawLine(
        Offset(0, y0),
        Offset(size.width, y0),
        Paint()
          ..color = baseline
          ..strokeWidth = 1,
      );
      return;
    }
    final maxV = math.max(values.reduce(math.max), 1);
    final step = size.width / (MuseSpeedHistory.length - 1);
    final start = size.width - step * (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = start + step * i;
      final y = y0 - (values[i] / maxV) * (size.height - 2);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values || old.color != color;
}

class _TrafficTile extends ConsumerWidget {
  const _TrafficTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(museStatsProvider);
    final up = s.uplinkTotal.toInt();
    final down = s.downlinkTotal.toInt();
    return _Tile(
      title: '本次流量',
      value: museBytes(up + down),
      bottom: Align(
        alignment: Alignment.bottomLeft,
        child: Text('↑ ${museBytes(up)}   ↓ ${museBytes(down)}', maxLines: 1, style: museTileCaption(context)),
      ),
      onTap: () => _showSessionSheet(context),
    );
  }
}

class _RemainingTile extends ConsumerWidget {
  const _RemainingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final info = ref.watch(museSubInfoProvider);
    if (info == null) return const SizedBox.shrink();
    final remaining = info.remainingBW < 0 ? 0 : info.remainingBW;
    final share = info.total <= 0 ? 0.0 : (remaining / info.total).clamp(0.0, 1.0);
    final low = share < 0.1;
    return _Tile(
      title: '剩余流量',
      value: remaining <= 0 ? '已用完' : museBytes(remaining),
      valueColor: remaining <= 0 ? MusePalette.red : null,
      bottom: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Expanded(
              child: ClipRSuperellipse(
                borderRadius: MuseRadius.fullAll,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: share),
                  duration: museMotion(context),
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: MuseSize.progressBar,
                    backgroundColor: mt.inner,
                    color: low ? MusePalette.orange : museBrandOf(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: MuseSpace.s8),
            // 1.4.1: ellipsizes instead of overflowing in a narrow tile / at large text
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * _trailingShare),
              child: Text(
                '共 ${museBytes(info.total)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: museTileCaption(context),
              ),
            ),
          ],
        ),
      ),
      onTap: () => context.goNamed('config'),
    );
  }
}

class _ExpiryTile extends ConsumerWidget {
  const _ExpiryTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(museSubInfoProvider);
    if (info == null) return const SizedBox.shrink();
    final days = museDaysLeft(info.expire);
    final expired = info.isExpired || days < 0;
    final e = info.expire;
    return _Tile(
      title: '到期',
      value: expired ? '已到期' : '$days 天',
      valueColor: expired ? MusePalette.red : (days < 7 ? MusePalette.orange : null),
      bottom: Align(
        alignment: Alignment.bottomLeft,
        child: Text('${e.year}-${_two(e.month)}-${_two(e.day)}', style: museTileCaption(context)),
      ),
      onTap: () => context.goNamed('config'),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _ExitTile extends ConsumerWidget {
  const _ExitTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final running = ref.watch(museRunningProvider);
    final result = ref.watch(museExitProvider);
    final reach = ref.watch(museReachProvider);
    final info = result?.info;
    final String value;
    Widget bottom;
    if (!running) {
      value = '—';
      bottom = Text('未连接', style: museTileCaption(context));
    } else if (info != null) {
      value = museMaskIp(info.ip);
      final flag = museCountryFlag(info.country);
      bottom = Row(
        children: [
          Expanded(
            child: Text(
              reach == MuseReach.failed ? '无法访问外网' : '${flag ?? ''} ${museCountryLabel(info.country)}'.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: museTileCaption(context).copyWith(color: reach == MuseReach.failed ? MusePalette.orange : null),
            ),
          ),
          // 1.5.3: re-checking in the background; the last result stays
          if (result?.refreshing ?? false) ...[
            SizedBox(
              key: const ValueKey('exit_refreshing'),
              width: MuseSpace.s12,
              height: MuseSpace.s12,
              child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke, color: mt.text2),
            ),
            const SizedBox(width: MuseSpace.s8),
          ],
          InkResponse(
            key: const ValueKey('exit_copy'),
            radius: 16,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: info.ip));
              try {
                ref.read(inAppNotificationControllerProvider).showSuccessToast('已复制 IP');
              } catch (_) {}
            },
            child: Icon(Icons.copy_outlined, size: MuseIconSize.tiny, color: mt.text3),
          ),
        ],
      );
    } else if (result?.infoFailed ?? false) {
      value = '—';
      bottom = Text('获取失败', style: museTileCaption(context).copyWith(color: MusePalette.orange));
    } else {
      value = '检测中';
      bottom = Text(reach == MuseReach.failed ? '无法访问外网' : '…', style: museTileCaption(context));
    }
    return _Tile(
      title: '出口 IP',
      value: value,
      bottom: Align(alignment: Alignment.bottomLeft, child: bottom),
      // 1.12.0: 点开看出口详情（运营商 / ASN / IP 类型），诊断在详情里
      onTap: () => showMuseExitDetailSheet(context),
    );
  }
}

class _AdBlockTile extends ConsumerWidget {
  const _AdBlockTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = MuseAdBlockLevel.fromKey(ref.watch(Preferences.museAdBlockLevel));
    return _Tile(
      title: '去广告',
      value: level.title,
      bottomHeight: MuseSize.segmented,
      bottom: MuseSegmented<MuseAdBlockLevel>(
        key: const ValueKey('adblock_segmented'),
        values: MuseAdBlockLevel.values,
        selected: level,
        label: (l) => l.title,
        onChanged: (l) => ref.read(Preferences.museAdBlockLevel.notifier).update(l.key),
      ),
    );
  }
}

/// 网速 / 本次流量 details: this session's numbers (the traffic chart comes later).
Future<void> _showSessionSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  backgroundColor: MuseTheme.of(context).card,
  builder: (_) => const _SessionSheet(),
);

class _SessionSheet extends ConsumerWidget {
  const _SessionSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final s = ref.watch(museStatsProvider);
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;
    final rows = <(String, String)>[
      ('下载速度', museSpeedText(s.downlink.toInt())),
      ('上传速度', museSpeedText(s.uplink.toInt())),
      ('本次下载', museBytes(s.downlinkTotal.toInt())),
      ('本次上传', museBytes(s.uplinkTotal.toInt())),
      if (since != null) ('已连接', museFormatDuration(DateTime.now().difference(since))),
    ];
    return SafeArea(
      child: Padding(
        key: const ValueKey('session_sheet'),
        padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('本次连接', style: MuseType.title(context)),
            const SizedBox(height: MuseSpace.s12),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: MuseSpace.s8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(k, style: MuseType.body(context).copyWith(color: mt.text2)),
                    ),
                    Text(v, style: MuseType.body(context).copyWith(fontFeatures: MuseType.tabular)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 编辑首页 (top bar / end of the tiles) or long-press a tile: drag to reorder, switch to show / hide.
Future<void> showMuseTileEditor(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: MuseTheme.of(context).card,
  builder: (_) => const _TileEditor(),
);

class _TileEditor extends ConsumerWidget {
  const _TileEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final order = museParseTileOrder(ref.watch(Preferences.museHomeTileOrder));
    final hidden = museParseHiddenTiles(ref.watch(Preferences.museHomeTilesHidden));
    final windows = PlatformUtils.isWindows;
    final shown = [
      for (final t in order)
        if (museTileOnPlatform(t, windows: windows)) t,
    ];
    return SafeArea(
      child: Column(
        key: const ValueKey('tile_editor'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s8),
            child: Text('首页卡片', style: MuseType.title(context)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s8),
            child: Text(
              '打开开关显示卡片，关闭隐藏；按住左侧把手拖动排序',
              key: const ValueKey('tile_editor_hint'),
              style: MuseType.caption(context).copyWith(color: mt.text2),
            ),
          ),
          Flexible(
            child: ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              onReorder: (from, to) {
                final next = museReorderShownTiles(order, shown, from, to);
                ref.read(Preferences.museHomeTileOrder.notifier).update(museTileOrderToRaw(next));
              },
              children: [
                for (final (i, t) in shown.indexed)
                  ListTile(
                    key: ValueKey('tile_edit_${t.key}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_indicator_outlined, size: MuseIconSize.small, color: mt.text3),
                    ),
                    title: Text(t.title, style: MuseType.body(context)),
                    trailing: Switch.adaptive(
                      value: !hidden.contains(t),
                      activeTrackColor: museBrandOf(context),
                      onChanged: (_) async {
                        final next = museToggleHiddenTile(hidden, t);
                        await ref.read(Preferences.museHomeTilesHidden.notifier).update(museHiddenTilesToRaw(next));
                        // 出口检测 runs only while its tile is shown
                        if (t == MuseHomeTile.exit) {
                          await ref.read(Preferences.museExitCheck.notifier).update(!next.contains(t));
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: MuseSpace.s8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- empty state

/// 1.9.0 #18: the first-run choices (key, icon, label, action); 扫码 only where there is a camera
/// scanner (phones).
List<(String, IconData, String, MuseAddAction)> museFirstRunActions({required bool qr}) => [
  ('first_run_paste', Icons.content_paste_outlined, '粘贴链接', MuseAddAction.paste),
  if (qr) ('first_run_qr', Icons.qr_code_scanner_outlined, '扫码', MuseAddAction.qr),
  ('first_run_file', Icons.insert_drive_file_outlined, '从文件导入', MuseAddAction.file),
];

bool museFirstRunQr() => !PlatformUtils.isDesktop;

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context), vertical: MuseSpace.s32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            key: const ValueKey('home_empty_guide'),
            padding: const EdgeInsets.all(MuseSpace.s24),
            decoration: mt.cardDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: MuseSize.emptyArt,
                  height: MuseSize.emptyArt,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: museBrandOf(context).withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Assets.images.glyph.svg(
                    width: MuseSize.emptyIcon,
                    height: MuseSize.emptyIcon,
                    colorFilter: ColorFilter.mode(museBrandOf(context), BlendMode.srcIn),
                  ),
                ),
                const SizedBox(height: MuseSpace.s16),
                Text('还没有订阅', style: MuseType.title(context)),
                const SizedBox(height: MuseSpace.s8),
                // 1.9.0 #18: first run — three ways to add, the same import the add sheet uses
                Text('选一种方式导入订阅', style: MuseType.caption(context).copyWith(color: mt.text2)),
                const SizedBox(height: MuseSpace.s24),
                for (final (key, icon, label, action) in museFirstRunActions(qr: museFirstRunQr()))
                  Padding(
                    padding: const EdgeInsets.only(bottom: MuseSpace.s8),
                    child: SizedBox(
                      width: double.infinity,
                      height: MuseSize.button,
                      child: action == MuseAddAction.paste
                          ? FilledButton.icon(
                              key: ValueKey(key),
                              style: FilledButton.styleFrom(
                                backgroundColor: museBrandOf(context),
                                shape: MuseShape.full,
                              ),
                              onPressed: () =>
                                  ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(action: action),
                              icon: Icon(icon),
                              label: Text(label),
                            )
                          : OutlinedButton.icon(
                              key: ValueKey(key),
                              style: OutlinedButton.styleFrom(shape: MuseShape.full),
                              onPressed: () =>
                                  ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(action: action),
                              icon: Icon(icon),
                              label: Text(label),
                            ),
                    ),
                  ),
                TextButton(
                  key: const ValueKey('empty_add_button'),
                  onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                  child: Text('更多方式（手动输入等）', style: TextStyle(color: museBrandOf(context))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] blurred when [masked] (隐私模式).
Widget museMaybeMask(bool masked, Widget child) => masked
    ? ImageFiltered(
        key: const ValueKey('privacy_mask'),
        imageFilter: ImageFilter.blur(sigmaX: MuseSize.privacyBlur, sigmaY: MuseSize.privacyBlur),
        child: child,
      )
    : child;
