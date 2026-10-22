// 穿云 1.3.0 - 首页 = dashboard: 「穿云」 title, a hero card (status, time · mode, big switch, current
// node → node picker) and a grid of equal tiles (网速 / 本次流量 / 剩余流量 / 到期 / 出口 IP / 去广告).
// Long-press a tile to reorder / hide. On a wide window the node list sits in a right column.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:math' as math;

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
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/home/clipboard_import.dart';
import 'package:hiddify/features/muse/home/core_watchdog.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/keep_alive_guide.dart';
import 'package:hiddify/features/muse/home/node_failover.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Content width from which the node list is shown as a right-hand column.
const museHomeSideListWidth = 1000.0;

class MuseHomePage extends HookConsumerWidget {
  const MuseHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(museHasProfileProvider);

    // 1.2.8: 更新说明, once per new version
    final appVersion = ref.watch(museAppVersionProvider);
    useEffect(() {
      if (hasProfile == null || appVersion == null) return null;
      final shown = ref.read(Preferences.museChangelogShown);
      if (shown == appVersion) return null;
      final notes = museChangelogToShow(version: appVersion, shown: shown, introDone: hasProfile);
      Future.microtask(() async {
        await ref.read(Preferences.museChangelogShown.notifier).update(appVersion);
        if (notes == null || !context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            key: const ValueKey('changelog_dialog'),
            title: Text('穿云 $appVersion 更新内容'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final n in notes)
                    Padding(padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4), child: Text('· $n')),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('知道了'))],
          ),
        );
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
                width: 380,
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
    if (hasProfile == null) return const SizedBox.shrink();
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

enum _HeroState { idle, connecting, connected }

class MuseHeroCard extends HookConsumerWidget {
  const MuseHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final connection = ref.watch(museConnectionProvider);
    // first time connected: one-time 后台运行/自启动 guide
    ref.listen(museConnectionProvider, (prev, next) {
      if (prev?.valueOrNull is! Connected && next.valueOrNull is Connected) museMaybeShowKeepAliveGuide(context, ref);
    });
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;
    final recovering = ref.watch(museWatchdogRecoveringProvider);
    final failoverFrom = ref.watch(museFailoverFromProvider);
    final mode = ref.watch(ConfigOptions.museRouteMode);

    // tick every second while connected, for the timer
    final tick = useState(0);
    useEffect(() {
      if (since == null) return null;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => tick.value++);
      return timer.cancel;
    }, [since]);

    final status = connection.valueOrNull;
    final connected = status is Connected;
    final busy = status?.isSwitching ?? false;
    // Windows: while the keeper reconnects, the switch cancels the recovery
    final canCancelRecovery = PlatformUtils.isWindows && recovering && status is Connecting;
    final failed = connection.hasError && !connected;
    final state = connected ? _HeroState.connected : (busy ? _HeroState.connecting : _HeroState.idle);
    final label = switch (status) {
      Connected() => '已连接',
      Connecting() when canCancelRecovery => '正在恢复',
      Connecting() => '连接中',
      Disconnecting() => '断开中',
      _ when failed => '连接失败',
      _ => '未连接',
    };

    Future<void> toggle() async {
      final notifier = ref.read(connectionNotifierProvider.notifier);
      if (status is Connected || canCancelRecovery) {
        await notifier.toggleConnection();
        return;
      }
      if (ref.read(museActiveProfileIdProvider) == null) {
        await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
        return;
      }
      await notifier.toggleConnection();
    }

    final onBrand = state != _HeroState.idle;
    final fg = onBrand ? MusePalette.white : mt.text1;
    final fg2 = onBrand ? MusePalette.white.withValues(alpha: 0.78) : mt.text2;
    final switchEnabled = !busy || canCancelRecovery;

    final card = AnimatedContainer(
      duration: MuseMotion.fast,
      curve: MuseMotion.curve,
      decoration: switch (state) {
        _HeroState.idle => mt.cardDecoration(color: mt.heroIdle),
        _HeroState.connecting => BoxDecoration(
          borderRadius: MuseRadius.cardAll,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [mt.heroGradient.colors.first.withValues(alpha: 0.85), mt.heroGradient.colors.last.withValues(alpha: 0.85)],
          ),
        ),
        _HeroState.connected => BoxDecoration(
          borderRadius: MuseRadius.cardAll,
          gradient: mt.heroGradient,
          boxShadow: mt.cardDecoration().boxShadow,
        ),
      },
      child: ClipRRect(
        borderRadius: MuseRadius.cardAll,
        child: Stack(
          children: [
            if (state == _HeroState.connecting) const Positioned.fill(child: _Shimmer()),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                // the whole card connects while disconnected
                onTap: state == _HeroState.idle && !busy ? toggle : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s16, MuseSpace.s16, 0),
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
                                        duration: MuseMotion.fast,
                                        child: Text(
                                          label,
                                          key: ValueKey(label),
                                          maxLines: 1,
                                          style: MuseType.largeTitle(context).copyWith(color: failed ? MusePalette.red : fg),
                                        ),
                                      ),
                                    ),
                                    if (connected && recovering)
                                      Padding(
                                        padding: const EdgeInsets.only(left: MuseSpace.s8),
                                        child: Icon(Icons.autorenew_rounded, key: const ValueKey('watchdog_icon'), size: MuseIconSize.small, color: fg2),
                                      ),
                                    if (connected && failoverFrom != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: MuseSpace.s8),
                                        child: Icon(Icons.swap_horiz_rounded, key: const ValueKey('failover_icon'), size: MuseIconSize.small, color: fg2),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: MuseSpace.s4),
                                Row(
                                  children: [
                                    if (since != null) ...[
                                      Text(
                                        museFormatDuration(DateTime.now().difference(since)),
                                        key: const ValueKey('home_timer'),
                                        style: MuseType.caption(context).copyWith(color: fg2, fontSize: 13),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8),
                                        child: Text('·', style: MuseType.caption(context).copyWith(color: fg2)),
                                      ),
                                    ],
                                    _ModePill(mode: mode, onBrand: onBrand),
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
                            onTap: switchEnabled ? toggle : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: MuseSpace.s16),
                      Divider(height: 0.5, thickness: 0.5, color: onBrand ? MusePalette.white.withValues(alpha: 0.22) : mt.hairline),
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
      shape: const StadiumBorder(),
      child: InkWell(
        key: const ValueKey('home_mode_pill'),
        customBorder: const StadiumBorder(),
        onTap: () => ref
            .read(ConfigOptions.museRouteMode.notifier)
            .update(mode == MuseRouteMode.rule ? MuseRouteMode.global : MuseRouteMode.rule),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: MuseMotion.fast,
                child: Text(
                  '${mode.title}模式',
                  key: ValueKey(mode),
                  style: MuseType.caption(context).copyWith(color: fg, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: MuseSpace.s4),
              Icon(Icons.swap_horiz_rounded, size: 14, color: fg.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large switch on the hero card (64 × 36).
class _BigSwitch extends StatelessWidget {
  const _BigSwitch({super.key, required this.on, required this.onBrand, required this.onTap});

  final bool on;
  final bool onBrand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final track = on ? MusePalette.white : (mt.dark ? mt.inner : MusePalette.lightHairline);
    final knob = on ? MusePalette.brand : MusePalette.white;
    return Semantics(
      button: true,
      toggled: on,
      label: on ? '断开' : '连接',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: MuseMotion.fast,
          curve: MuseMotion.curve,
          width: 64,
          height: 36,
          padding: const EdgeInsets.all(MuseSpace.s4),
          decoration: BoxDecoration(color: track, borderRadius: MuseRadius.fullAll),
          child: AnimatedAlign(
            duration: MuseMotion.fast,
            curve: MuseMotion.curve,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: knob,
                shape: BoxShape.circle,
                boxShadow: on ? null : const [BoxShadow(color: MusePalette.knobShadow, blurRadius: 4, offset: Offset(0, 1))],
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
    final fg = onBrand ? MusePalette.white : mt.text1;
    final fg2 = onBrand ? MusePalette.white.withValues(alpha: 0.78) : mt.text2;
    String text = '选择节点';
    String? flag;
    IconData icon = Icons.public_rounded;
    if (item != null) {
      final full = museNodeName(item);
      if (item.isGroup) {
        final rawName = full.split(' → ').first.trim();
        final kind = museGroupKind(type: item.type, name: rawName, selectedDisplay: item.groupSelectedTagDisplay);
        final sel = item.groupSelectedTagDisplay.trim();
        final pick = kind == '负载均衡' || sel.toLowerCase() == 'lowest-delay' || museBalanceStrategyName(sel) != null ? '' : sel;
        text = museCurrentNodeText(name: rawName, groupLabel: museGroupName(rawName), groupPick: museGroupName(pick));
        flag = pick.isEmpty ? null : museFlagEmoji(pick);
        icon = Icons.bolt_rounded;
        text = museStripFlags(text);
      } else {
        flag = museFlagEmoji(full);
        text = museStripFlags(full);
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
          height: 56,
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
                Icon(Icons.chevron_right_rounded, size: MuseIconSize.small, color: fg2),
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
class MuseTileGrid extends ConsumerWidget {
  const MuseTileGrid({super.key});

  static const tileHeight = 124.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(museSubInfoProvider);
    final order = museParseTileOrder(ref.watch(Preferences.museHomeTileOrder));
    final hidden = museParseHiddenTiles(ref.watch(Preferences.museHomeTilesHidden));
    final tiles = museVisibleTiles(
      order,
      hidden,
      hasData: (t) => switch (t) {
        MuseHomeTile.remaining => museHasTrafficCap(info),
        MuseHomeTile.expiry => museHasExpiry(info),
        _ => true,
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = museTileColumns(constraints.maxWidth);
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += columns) {
          final slice = tiles.sublist(i, math.min(i + columns, tiles.length));
          if (rows.isNotEmpty) rows.add(const SizedBox(height: MuseSpace.s12));
          rows.add(
            SizedBox(
              height: tileHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const SizedBox(width: MuseSpace.s12),
                    Expanded(child: j < slice.length ? _tile(slice[j]) : const SizedBox.shrink()),
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
  };
}

bool museHasTrafficCap(SubscriptionInfo? info) => info != null && info.total > 0 && !info.total.isInfinitSize();

bool museHasExpiry(SubscriptionInfo? info) {
  if (info == null) return false;
  final year = info.expire.year;
  return year > 1971 && year < 2100;
}

/// One tile: small title (+ optional trailing) → big number → bottom element.
class _Tile extends ConsumerWidget {
  const _Tile({required this.title, this.titleTrailing, required this.value, this.valueColor, required this.bottom, this.onTap});

  final String title;
  final Widget? titleTrailing;
  final String value;
  final Color? valueColor;
  final Widget bottom;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
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
                Row(
                  children: [
                    Expanded(child: Text(title, maxLines: 1, style: MuseType.caption(context))),
                    ?titleTrailing,
                  ],
                ),
                AnimatedSwitcher(
                  duration: MuseMotion.fast,
                  transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                  child: Text(
                    value,
                    key: ValueKey(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MuseType.title(context).copyWith(fontSize: 22, color: valueColor),
                  ),
                ),
                SizedBox(height: 20, child: bottom),
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

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color, this.baseline);

  final List<int> values;
  final Color color;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final y0 = size.height - 1;
    if (values.length < 2) {
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0), Paint()..color = baseline..strokeWidth = 1);
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
      bottom: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: MuseRadius.fullAll,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: share),
                duration: MuseMotion.fast,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: mt.inner,
                  color: low ? MusePalette.orange : MusePalette.brand,
                ),
              ),
            ),
          ),
          const SizedBox(width: MuseSpace.s8),
          Text('共 ${museBytes(info.total)}', style: MuseType.caption(context)),
        ],
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
          InkResponse(
            key: const ValueKey('exit_copy'),
            radius: 16,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: info.ip));
              try {
                ref.read(inAppNotificationControllerProvider).showSuccessToast('已复制 IP');
              } catch (_) {}
            },
            child: Icon(Icons.copy_rounded, size: 16, color: mt.text3),
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

/// A small pill segmented control (关 / 温和 / 强力).
class MuseSegmented<T> extends StatelessWidget {
  const MuseSegmented({super.key, required this.values, required this.selected, required this.label, required this.onChanged});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: mt.inner, borderRadius: MuseRadius.fullAll),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: MuseMotion.fast,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == selected ? (mt.dark ? MusePalette.brand : MusePalette.white) : MusePalette.transparent,
                    borderRadius: MuseRadius.fullAll,
                    boxShadow: v == selected && !mt.dark
                        ? const [BoxShadow(color: MusePalette.lightShadow, blurRadius: 4, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: Text(
                    label(v),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: v == selected ? FontWeight.w600 : FontWeight.w500,
                      color: v == selected ? (mt.dark ? MusePalette.white : MusePalette.brand) : mt.text2,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
                    Expanded(child: Text(k, style: MuseType.body(context).copyWith(color: mt.text2))),
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
          ReorderableListView(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            onReorder: (from, to) {
              final tile = order[from];
              final next = museMoveTileTo(order, tile, to > from ? to - 1 : to);
              ref.read(Preferences.museHomeTileOrder.notifier).update(museTileOrderToRaw(next));
            },
            children: [
              for (final (i, t) in order.indexed)
                ListTile(
                  key: ValueKey('tile_edit_${t.key}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: Icon(Icons.drag_indicator_rounded, size: MuseIconSize.small, color: mt.text3),
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
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: MusePalette.brand.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Assets.images.glyph.svg(
                    width: 40,
                    height: 40,
                    colorFilter: const ColorFilter.mode(MusePalette.brand, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(height: MuseSpace.s16),
                Text('还没有订阅', style: MuseType.title(context)),
                const SizedBox(height: MuseSpace.s24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey('empty_add_button'),
                    style: FilledButton.styleFrom(backgroundColor: MusePalette.brand, shape: const StadiumBorder()),
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
