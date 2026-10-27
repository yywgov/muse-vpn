// 穿云 1.3.0 - 首页 = dashboard: 「穿云」 title, a hero card (status, time · mode, big switch, current
// node → node picker) and a grid of equal tiles (网速 / 本次流量 / 剩余流量 / 到期 / 出口 IP / 去广告).
// Long-press a tile to reorder / hide. On a wide window the node list sits in a right column.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/background_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/home/changelog_dialog.dart';
import 'package:hiddify/features/muse/home/clipboard_import.dart';
import 'package:hiddify/features/muse/home/core_watchdog.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/keep_alive_guide.dart';
import 'package:hiddify/features/muse/home/node_failover.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/connect_flow.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_segmented.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_skeleton.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/service_probe.dart';
import 'package:hiddify/features/muse/settings/service_mode_switch.dart';
import 'package:hiddify/features/muse/widget/muse_card.dart';
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';

part 'dashboard_cards.dart';

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

    // 1.3.0: a subscription link on the clipboard puts a dot on 添加 (no banner)
    useMuseClipboardWatcher(ref);

    return MuseScaffold(
      large: true,
      title: Constants.appName,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final dashboard = _Dashboard(hasProfile: hasProfile);
          if (constraints.maxWidth < museHomeSideListWidth || hasProfile != true) return dashboard;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: dashboard),
              SizedBox(
                width: MuseSize.sideColumn,
                child: Column(
                  key: const ValueKey('home_side_nodes'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(MuseSpace.s16 + MuseSpace.s4, 0, MuseSpace.s16, MuseSpace.s4),
                      child: Text('节点', style: MuseType.title(context)),
                    ),
                    const Expanded(child: MuseNodeList(embedded: true)),
                  ],
                ),
              ),
              const SizedBox(width: MuseSpace.s8),
            ],
          );
        },
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
        padding: EdgeInsets.fromLTRB(margin, MuseSpace.s4, margin, MuseSpace.s32),
        children: [MuseSkeleton.dashboard()],
      );
    }
    if (hasProfile == false) return const _EmptyState();
    return RefreshIndicator(
      key: const ValueKey('home_pull_refresh'),
      onRefresh: () => museNodePull(ref),
      color: MusePalette.brand,
      notificationPredicate: (n) => n.depth == 0,
      child: ListView(
        key: const ValueKey('home_dashboard'),
        padding: EdgeInsets.fromLTRB(margin, MuseSpace.s4, margin, MuseSpace.s32),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: const [
          MuseHeroCard(),
          SizedBox(height: MuseSpace.s12),
          MuseTileGrid(),
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
    // first time connected: one-time 后台运行/自启动 guide
    ref.listen(museConnectionProvider, (prev, next) {
      if (prev?.valueOrNull is! Connected && next.valueOrNull is Connected) museMaybeShowKeepAliveGuide(context, ref);
    });
    // 1.4.1 Android: killed by the system in the background since the last start → the steps
    useEffect(() {
      if (!PlatformUtils.isAndroid) return null;
      unawaited(
        museCheckBackgroundKill(ref).then((killed) {
          if (killed && context.mounted) unawaited(showMuseBackgroundGuide(context, killed: true));
        }),
      );
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

    final onBrand = state != _HeroState.idle;
    // 1.4.0: roomier on the desktop
    final heroPad = MediaQuery.sizeOf(context).width >= 720 ? MuseSpace.s24 : MuseSpace.s16;
    final fg = onBrand ? MusePalette.white : mt.text1;
    final fg2 = onBrand ? MusePalette.white.withValues(alpha: 0.78) : mt.text2;
    final switchEnabled = action != MuseConnectAction.ignore;

    final card = AnimatedContainer(
      duration: museMotion(context),
      curve: MuseMotion.curve,
      decoration: switch (state) {
        _HeroState.idle => mt.cardDecoration(color: mt.heroIdle),
        _HeroState.connecting => BoxDecoration(
          borderRadius: MuseRadius.cardAll,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              mt.heroGradient.colors.first.withValues(alpha: 0.85),
              mt.heroGradient.colors.last.withValues(alpha: 0.85),
            ],
          ),
        ),
        _HeroState.connected => BoxDecoration(
          borderRadius: MuseRadius.cardAll,
          gradient: mt.heroGradient,
          boxShadow: mt.cardDecoration().boxShadow,
        ),
      },
      child: ClipRSuperellipse(
        borderRadius: MuseRadius.cardAll,
        child: Stack(
          children: [
            // 1.5.0: no moving shimmer when the system asks for reduced motion
            if (state == _HeroState.connecting && !museReduceMotion(context)) const Positioned.fill(child: _Shimmer()),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    // the whole card connects while disconnected
                    onTap: state == _HeroState.idle && action == MuseConnectAction.connect ? toggle : null,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(heroPad, heroPad, heroPad, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: AnimatedSwitcher(
                                            duration: museMotion(context),
                                            child: Text(
                                              label,
                                              key: ValueKey(label),
                                              maxLines: 1,
                                              style: MuseType.largeTitle(
                                                context,
                                              ).copyWith(color: failed ? MusePalette.red : fg),
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
                                    ),
                                    const SizedBox(height: MuseSpace.s8),
                                    // 1.5.0: wraps instead of overflowing (narrow phone, large text)
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: MuseSpace.s8,
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
                                              style: MuseType.body(context).copyWith(color: fg2),
                                            ),
                                          )
                                        else if (since != null) ...[
                                          MuseUptimeText(
                                            since: since,
                                            style: MuseType.body(
                                              context,
                                            ).copyWith(color: fg2, fontFeatures: MuseType.tabular),
                                          ),
                                          Text('·', style: MuseType.caption(context).copyWith(color: fg2)),
                                        ],
                                        if (stage == null || connected) _ModePill(mode: mode, onBrand: onBrand),
                                        if (stage == MuseConnectStage.testing && connected)
                                          Text(
                                            '${stage!.title}…',
                                            key: const ValueKey('home_stage_testing'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: MuseType.caption(context).copyWith(color: fg2),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: MuseSpace.s12),
                              _BigSwitch(
                                key: const ValueKey('home_connect_switch'),
                                on: connected || busy,
                                onBrand: onBrand,
                                semanticLabel: switch (action) {
                                  MuseConnectAction.cancel => '取消连接',
                                  MuseConnectAction.disconnect => '断开',
                                  _ => '连接',
                                },
                                onTap: switchEnabled ? toggle : null,
                              ),
                            ],
                          ),
                          SizedBox(height: heroPad),
                          Divider(
                            height: MuseSize.hairline,
                            thickness: MuseSize.hairline,
                            color: onBrand ? MusePalette.white.withValues(alpha: 0.22) : mt.hairline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _HeroNodeRow(onBrand: onBrand),
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    debugBuilds++;
    final tick = useState(0);
    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => tick.value++);
      return timer.cancel;
    }, [since]);
    return Text(
      museFormatDuration(DateTime.now().difference(since)),
      key: const ValueKey('home_timer'),
      maxLines: 1,
      style: style,
    );
  }
}

class _ModePill extends ConsumerWidget {
  const _ModePill({required this.mode, required this.onBrand});

  final MuseRouteMode mode;
  final bool onBrand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final fg = onBrand ? MusePalette.white : mt.text1;
    return Material(
      color: onBrand ? MusePalette.white.withValues(alpha: 0.18) : mt.inner,
      shape: MuseShape.full,
      child: InkWell(
        key: const ValueKey('home_mode_pill'),
        customBorder: MuseShape.full,
        onTap: () => ref
            .read(ConfigOptions.museRouteMode.notifier)
            .update(mode == MuseRouteMode.rule ? MuseRouteMode.global : MuseRouteMode.rule),
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
                  style: MuseType.caption(context).copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: MuseSpace.s4),
              Icon(Icons.swap_horiz_outlined, size: MuseIconSize.tiny, color: fg.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large switch on the hero card (64 × 36).
class _BigSwitch extends StatelessWidget {
  const _BigSwitch({
    super.key,
    required this.on,
    required this.onBrand,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool on;
  final bool onBrand;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final track = on ? MusePalette.white : (mt.dark ? mt.inner : MusePalette.lightHairline);
    final knob = on ? MusePalette.brand : MusePalette.white;
    return Semantics(
      button: true,
      toggled: on,
      enabled: onTap != null,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: museMotion(context),
          curve: MuseMotion.curve,
          width: MuseSize.switchWidth,
          height: MuseSize.switchHeight,
          padding: const EdgeInsets.all(MuseSpace.s4),
          decoration: BoxDecoration(color: track, borderRadius: MuseRadius.fullAll),
          child: AnimatedAlign(
            duration: museMotion(context),
            curve: MuseMotion.curve,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: MuseSize.switchKnob,
              height: MuseSize.switchKnob,
              decoration: BoxDecoration(
                color: knob,
                shape: BoxShape.circle,
                boxShadow: on
                    ? null
                    : const [BoxShadow(color: MusePalette.knobShadow, blurRadius: 4, offset: Offset(0, 1))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft light band moving across the card while connecting.
class _Shimmer extends HookWidget {
  const _Shimmer();

  @override
  Widget build(BuildContext context) {
    final c = useAnimationController(duration: const Duration(milliseconds: 1600));
    useEffect(() {
      c.repeat();
      return null;
    }, const []);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) => CustomPaint(painter: _ShimmerPainter(c.value)),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final x = -w * 0.5 + t * w * 2;
    final rect = Rect.fromLTWH(x - w * 0.25, 0, w * 0.5, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            MusePalette.white.withValues(alpha: 0),
            MusePalette.white.withValues(alpha: 0.16),
            MusePalette.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}

/// Bottom row of the hero card: flag | current node | latency ›  (opens the node picker).
class _HeroNodeRow extends ConsumerWidget {
  const _HeroNodeRow({required this.onBrand});

  final bool onBrand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final group = ref.watch(museNodeGroupProvider).valueOrNull;
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;
    final item = group?.items.where((e) => e.tag == group.selected).firstOrNull;
    final shown = ref.watch(museShownPickProvider);
    final fg = onBrand ? MusePalette.white : mt.text1;
    final fg2 = onBrand ? MusePalette.white.withValues(alpha: 0.78) : mt.text2;
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
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('home_current_node'),
        onTap: () => showMuseNodePicker(context),
        child: SizedBox(
          height: MuseSize.heroRow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
            child: Row(
              children: [
                MuseFlagBox(flag: flag, icon: icon, onBrand: onBrand),
                const SizedBox(width: MuseSpace.s12),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MuseType.body(context).copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                ),
                if (showDelay)
                  Text(
                    '$delay ms',
                    style: MuseType.body(context).copyWith(color: fg2, fontFeatures: MuseType.tabular),
                  ),
                Icon(Icons.chevron_right_outlined, size: MuseIconSize.small, color: fg2),
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

  static const tileHeight = 124.0;
  static const tileHeightDesktop = 136.0;

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
          if (rows.isNotEmpty) rows.add(const SizedBox(height: MuseSpace.s12));
          rows.add(
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < idx.length; j++) ...[
                    if (j > 0) const SizedBox(width: MuseSpace.s12),
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
double museTileHeightFor(TextScaler scaler, {double bottom = MuseSize.tileBottom}) {
  const caption = 12 * 1.3; // MuseType.caption line
  const number = 24 * 1.2; // MuseType.number line
  return MuseSpace.s16 * 2 + scaler.scale(caption + number + bottom) + MuseSpace.s8;
}

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
      decoration: mt.cardDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: MuseRadius.cardAll,
          onTap: onTap,
          onLongPress: () => showMuseTileEditor(context),
          child: Padding(
            padding: const EdgeInsets.all(MuseSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 1.4.1: the trailing caption ellipsizes in a narrow tile / at large text
                LayoutBuilder(
                  builder: (context, c) => Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MuseType.caption(context),
                        ),
                      ),
                      if (titleTrailing != null)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: c.maxWidth * _trailingShare),
                          child: DefaultTextStyle.merge(
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            child: museMaybeMask(masked, titleTrailing!),
                          ),
                        ),
                    ],
                  ),
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
                      child: Text(value, maxLines: 1, style: MuseType.number(context).copyWith(color: valueColor)),
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

class _SpeedTile extends ConsumerWidget {
  const _SpeedTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(museStatsProvider);
    final history = ref.watch(museSpeedHistoryProvider);
    return _Tile(
      title: '网速',
      titleTrailing: Text('↑ ${museSpeedText(stats.uplink.toInt())}', style: MuseType.caption(context)),
      value: '↓ ${museSpeedText(stats.downlink.toInt())}',
      bottom: SizedBox.expand(
        child: CustomPaint(painter: _SparklinePainter(history, MusePalette.brand, MuseTheme.of(context).hairline)),
      ),
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
      titleTrailing: Text('↑ ${museSpeedText(stats.uplink.toInt())}', style: MuseType.caption(context)),
      value: '↓ ${museSpeedText(stats.downlink.toInt())}',
      bottom: Row(
        children: [
          Expanded(
            flex: 2,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparklinePainter(history, MusePalette.brand, MuseTheme.of(context).hairline),
            ),
          ),
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
              style: MuseType.caption(context).copyWith(fontFeatures: MuseType.tabular),
            ),
          ),
        ],
      ),
      onTap: () => _showSessionSheet(context),
    );
  }
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
        child: Text('↑ ${museBytes(up)}   ↓ ${museBytes(down)}', maxLines: 1, style: MuseType.caption(context)),
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
                    color: low ? MusePalette.orange : MusePalette.brand,
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
                style: MuseType.caption(context),
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
        child: Text('${e.year}-${_two(e.month)}-${_two(e.day)}', style: MuseType.caption(context)),
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
      bottom = Text('未连接', style: MuseType.caption(context));
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
              style: MuseType.caption(context).copyWith(color: reach == MuseReach.failed ? MusePalette.orange : null),
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
      bottom = Text('获取失败', style: MuseType.caption(context).copyWith(color: MusePalette.orange));
    } else {
      value = '检测中';
      bottom = Text(reach == MuseReach.failed ? '无法访问外网' : '…', style: MuseType.caption(context));
    }
    return _Tile(
      title: '出口 IP',
      value: value,
      bottom: Align(alignment: Alignment.bottomLeft, child: bottom),
      onTap: () => showMuseDiagnoseSheet(context),
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

/// Long-press a tile: drag to reorder, switch to show / hide.
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
                      activeTrackColor: MusePalette.brand,
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
                  decoration: BoxDecoration(color: MusePalette.brand.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Assets.images.glyph.svg(
                    width: MuseSize.emptyIcon,
                    height: MuseSize.emptyIcon,
                    colorFilter: ColorFilter.mode(MusePalette.brand, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(height: MuseSpace.s16),
                Text('还没有订阅', style: MuseType.title(context)),
                const SizedBox(height: MuseSpace.s24),
                SizedBox(
                  width: double.infinity,
                  height: MuseSize.button,
                  child: FilledButton(
                    key: const ValueKey('empty_add_button'),
                    style: FilledButton.styleFrom(backgroundColor: MusePalette.brand, shape: MuseShape.full),
                    onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                    child: const Text('添加订阅'),
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

/// [child] blurred when [masked] (隐私模式).
Widget museMaybeMask(bool masked, Widget child) => masked
    ? ImageFiltered(
        key: const ValueKey('privacy_mask'),
        imageFilter: ImageFilter.blur(sigmaX: MuseSize.privacyBlur, sigmaY: MuseSize.privacyBlur),
        child: child,
      )
    : child;
