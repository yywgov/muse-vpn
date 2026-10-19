// 穿云 - 首页: big connect button, route mode and node cards (style B).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/home/bad_nodes.dart';
import 'package:hiddify/features/muse/home/clipboard_import.dart';
import 'package:hiddify/features/muse/home/core_watchdog.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/node_failover.dart';
import 'package:hiddify/features/muse/home/keep_alive_guide.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 1.2.5: bumped by the 首页 pull-down gesture; the node list runs 测速 when it changes.
final museNodeTestRequestProvider = StateProvider<int>((ref) => 0);

class MuseHomePage extends HookConsumerWidget {
  const MuseHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(hasAnyProfileProvider).value ?? false;
    final running = ref.watch(serviceRunningProvider);

    // 1.2.5: pull down — 测速 while connected, otherwise update the subscriptions
    Future<void> onPull() async {
      if (!hasProfile) return;
      if (running) {
        ref.read(museNodeTestRequestProvider.notifier).state++;
        await Future<void>.delayed(const Duration(milliseconds: 900));
      } else {
        try {
          await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
        } catch (_) {}
      }
    }

    return MuseScaffold(
      titleWidget: const _Header(),
      actions: [
        IconButton(
          key: const ValueKey("profile_add_button"),
          tooltip: '添加订阅/配置',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
        ),
        const SizedBox(width: 4),
      ],
      // 1.2.1: the connect button and its status stay put above the list, so scrolling the
      // nodes never slides 「已连接 · 计时」 under the title bar and cuts it in half; the list
      // fades out at its top edge instead of ending in a hard line.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              const _ConnectSection(),
              Expanded(
                child: ShaderMask(
                  key: const ValueKey('home_node_list'),
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                    stops: [0, 0.03],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: RefreshIndicator(
                    key: const ValueKey('home_pull_refresh'),
                    onRefresh: onPull,
                    color: MuseColors.brand,
                    notificationPredicate: (n) => hasProfile && n.depth == 0,
                    child: ListView(
                      padding: const EdgeInsets.only(top: 4, bottom: 24),
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      children: [
                        const MuseClipboardImportBanner(),
                        const _RouteModeSelector(),
                        // 1.2.3: exit IP / region and Google · ChatGPT · Netflix
                        const MuseExitCard(),
                        if (hasProfile) const _NodesSection() else const _EmptyProfileSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 穿云 + 剩余流量 · 到期日 from the active subscription (hidden when the provider sends none).
class _Header extends ConsumerWidget {
  const _Header();

  static String _gb(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 100) return '${gb.toStringAsFixed(0)} GB';
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final info = profile is RemoteProfileEntity ? profile.subInfo : null;
    final parts = <String>[];
    if (info != null) {
      if (info.total > 0 && !info.total.isInfinitSize()) {
        parts.add(info.remainingBW <= 0 ? '流量已用完' : '剩余 ${_gb(info.remainingBW)}');
      }
      final year = info.expire.year;
      if (year > 1971 && year < 2100) {
        parts.add(info.isExpired ? '已到期' : '${info.expire.month}月${info.expire.day}日到期');
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          Constants.appName,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1),
        ),
        if (parts.isNotEmpty) ...[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: MuseColors.secondaryText(context)),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectSection extends HookConsumerWidget {
  const _ConnectSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connection = ref.watch(connectionNotifierProvider);
    // first time connected: one-time 后台运行/自启动 guide
    ref.listen(connectionNotifierProvider, (prev, next) {
      if (prev?.valueOrNull is! Connected && next.valueOrNull is Connected) {
        museMaybeShowKeepAliveGuide(context, ref);
      }
    });
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();
    final secondary = MuseColors.secondaryText(context);
    final recovering = ref.watch(museWatchdogRecoveringProvider);
    final failoverFrom = ref.watch(museFailoverFromProvider);

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
    // 穿云 1.2.2 Windows: while the keeper reconnects, a tap cancels the recovery
    final canCancelRecovery = PlatformUtils.isWindows && recovering && status is Connecting;
    final String label = switch (status) {
      Connected() => '已连接',
      Connecting() when canCancelRecovery => '正在恢复连接…（点按取消）',
      Connecting() => '正在连接…',
      Disconnecting() => '正在断开…',
      _ when connection.hasError => '连接失败',
      _ => '未连接',
    };

    // same flow as the original connection button
    Future<void> toggle() async {
      if (status is Connected || canCancelRecovery) {
        await ref.read(connectionNotifierProvider.notifier).toggleConnection();
        return;
      }
      if (ref.read(activeProfileProvider).valueOrNull == null) {
        await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
        return;
      }
      await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    }

    return Padding(
      key: const ValueKey('home_connect_section'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        children: [
          _ConnectButton(connected: connected, busy: busy, onTap: busy && !canCancelRecovery ? null : toggle),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                if (since != null) TextSpan(text: '  ·  ${museFormatDuration(DateTime.now().difference(since))}'),
                // 穿云 1.2: state as icons, no text — core restarting / standing in for a dead node
                if (connected && recovering)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.autorenew_rounded, key: const ValueKey('watchdog_icon'), size: 18, color: theme.colorScheme.tertiary),
                    ),
                  ),
                if (connected && failoverFrom != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.swap_horiz_rounded, key: const ValueKey('failover_icon'), size: 18, color: theme.colorScheme.tertiary),
                    ),
                  ),
              ],
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: connection.hasError && !connected ? theme.colorScheme.error : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            key: const ValueKey('home_speed_text'),
            // empty while disconnected: keeps the button from jumping when the speeds appear
            // 1.2.5: plus this connection's traffic (本次), like Shadowrocket / Stash's dashboard
            connected
                ? '↑ ${stats.uplink.toInt().speed()}   ↓ ${stats.downlink.toInt().speed()}'
                      '   ·   本次 ${museBytes(stats.uplinkTotal.toInt() + stats.downlinkTotal.toInt())}'
                : '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (connected) const _CurrentNodeLine(),
        ],
      ),
    );
  }
}

/// 1.2.5: 「当前 🇯🇵 东京 02 · 86 ms」 under the speeds, so the node in use is visible however
/// long the list is or wherever it sorted to (Shadowrocket / Stash keep it on the home card).
class _CurrentNodeLine extends ConsumerWidget {
  const _CurrentNodeLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final group = ref.watch(proxiesOverviewNotifierProvider).valueOrNull;
    final item = group?.items.where((e) => e.tag == group.selected).firstOrNull;
    if (item == null) return const SizedBox.shrink();
    final full = item.tagDisplay.isNotEmpty ? item.tagDisplay : item.tag;
    final String text;
    if (item.isGroup) {
      final rawName = full.split(' → ').first.trim();
      final kind = museGroupKind(type: item.type, name: rawName, selectedDisplay: item.groupSelectedTagDisplay);
      final sel = item.groupSelectedTagDisplay.trim();
      final pick = kind == '负载均衡' || sel.toLowerCase() == 'lowest-delay' || museBalanceStrategyName(sel) != null ? '' : sel;
      text = museCurrentNodeText(name: rawName, groupLabel: museGroupName(rawName), groupPick: museGroupName(pick));
    } else {
      text = museCurrentNodeText(name: full);
    }
    if (text.isEmpty) return const SizedBox.shrink();
    final delay = item.urlTestDelay;
    final showDelay = delay > 0 && ConnectionConst.isValidDelay(delay);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        key: const ValueKey('home_current_node'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '当前  $text',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: MuseColors.secondaryText(context)),
            ),
          ),
          if (showDelay) ...[
            const SizedBox(width: 6),
            Container(width: 6, height: 6, decoration: BoxDecoration(color: MuseColors.delay(context, delay), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(
              '$delay ms',
              style: theme.textTheme.bodySmall?.copyWith(
                color: MuseColors.secondaryText(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// When the user last tapped the connect button: the connect/disconnect animation plays only
/// for a change the user asked for, never for a state restored when the app comes back.
DateTime? _museLastToggleTap;

bool _museUserToggledRecently() {
  final tap = _museLastToggleTap;
  return tap != null && DateTime.now().difference(tap) < const Duration(seconds: 30);
}

/// The big round button with the 穿云 glyph (1.1 animation, no haptics):
/// - 连接中: a light arc circles the button;
/// - 连上: the glow spreads out once, then stays lit;
/// - 断开: the glow pulls back and the button fades to grey.
/// A state that is already there when the page builds (e.g. returning to the app) is shown as is.
class _ConnectButton extends HookWidget {
  const _ConnectButton({required this.connected, required this.busy, required this.onTap});

  final bool connected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final spin = useAnimationController(duration: const Duration(milliseconds: 1200));
    final burst = useAnimationController(duration: const Duration(milliseconds: 750));
    final glow = useAnimationController(duration: const Duration(milliseconds: 450), initialValue: connected ? 1 : 0);
    final previous = usePrevious(connected);

    useEffect(() {
      if (busy) {
        spin.repeat();
      } else {
        spin
          ..stop()
          ..value = 0;
      }
      return null;
    }, [busy]);

    useEffect(() {
      if (previous == null || previous == connected || !_museUserToggledRecently()) {
        glow.value = connected ? 1 : 0;
        return null;
      }
      if (connected) {
        glow.forward(from: 0);
        burst.forward(from: 0);
      } else {
        burst.value = 0;
        glow.reverse(from: 1);
      }
      return null;
    }, [connected]);

    // 1.2.1: 112 dp (was 168): two to three more node rows fit on the first screen, and the
    // button is still a large, easy target
    const size = 112.0;
    final active = connected || busy;
    final off = MuseColors.isTrueBlack(context) ? const Color(0xFF1C1C1C) : (dark ? const Color(0xFF1E2A4D) : const Color(0xFFDDE5F4));
    final glyphColor = active ? Colors.white : (dark ? const Color(0xFF8A94B3) : const Color(0xFF7B8AA8));

    void tap() {
      _museLastToggleTap = DateTime.now();
      onTap?.call();
    }

    return Semantics(
      button: true,
      label: connected ? '断开' : '连接',
      child: RepaintBoundary(
        child: SizedBox(
          width: size + 32,
          height: size + 32,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: active ? 1 : 0),
            duration: const Duration(milliseconds: 260),
            builder: (context, a, child) => AnimatedBuilder(
              animation: Listenable.merge([spin, burst, glow]),
              builder: (context, child) {
                final glowAlpha = busy ? 0.22 : 0.55 * glow.value;
                return CustomPaint(
                  painter: _ConnectRingPainter(
                    spin: busy ? spin.value : null,
                    burst: burst.isAnimating ? burst.value : null,
                    radius: size / 2,
                  ),
                  child: Center(
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(off, MuseColors.brandLight, a)!,
                            Color.lerp(off, MuseColors.brandDeep, a)!,
                          ],
                        ),
                        boxShadow: [
                          if (glowAlpha > 0.01)
                            BoxShadow(
                              color: MuseColors.brand.withValues(alpha: glowAlpha),
                              blurRadius: 40,
                              spreadRadius: 6,
                            ),
                        ],
                      ),
                      child: child,
                    ),
                  ),
                );
              },
              child: child,
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap == null ? null : tap,
                customBorder: const CircleBorder(),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Assets.images.glyph.svg(
                      key: ValueKey(glyphColor),
                      width: 62,
                      height: 62,
                      colorFilter: ColorFilter.mode(glyphColor, BlendMode.srcIn),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rotating arc while connecting and the ring that spreads out once on connect.
class _ConnectRingPainter extends CustomPainter {
  _ConnectRingPainter({required this.spin, required this.burst, required this.radius});

  final double? spin;
  final double? burst;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (spin != null) {
      final rect = Rect.fromCircle(center: center, radius: radius + 8);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [MuseColors.brandLight.withValues(alpha: 0), MuseColors.brandLight],
          transform: GradientRotation(spin! * 2 * math.pi),
        ).createShader(rect);
      canvas.drawArc(rect, spin! * 2 * math.pi, math.pi * 1.4, false, paint);
    }
    if (burst != null) {
      final t = Curves.easeOut.transform(burst!);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + 4 * (1 - t)
        ..color = MuseColors.brandLight.withValues(alpha: 0.55 * (1 - t));
      canvas.drawCircle(center, radius + 3 + 12 * t, paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectRingPainter old) => old.spin != spin || old.burst != burst || old.radius != radius;
}

/// 规则 / 全局 as a pill segmented control.
class _RouteModeSelector extends ConsumerWidget {
  const _RouteModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(ConfigOptions.museRouteMode);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Column(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: MuseColors.card(context), borderRadius: BorderRadius.circular(24)),
            child: Row(
              children: [
                for (final m in MuseRouteMode.values)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => ref.read(ConfigOptions.museRouteMode.notifier).update(m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: m == mode ? MuseColors.brand : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          m.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: m == mode ? Colors.white : theme.colorScheme.onSurface,
                            fontWeight: m == mode ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyProfileSection extends ConsumerWidget {
  const _EmptyProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final secondary = MuseColors.secondaryText(context);
    // keeps the add notifier (and its success/error toasts) alive while an import runs
    ref.listen(addProfileNotifierProvider, (_, _) {});

    // 1.2.5: one tap imports what is on the clipboard (Karing / Shadowrocket first-run style);
    // nothing usable there opens the full 添加 sheet instead
    Future<void> paste() async {
      String? text;
      try {
        text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
      } catch (_) {}
      if (text == null || text.isEmpty) {
        try {
          ref.read(inAppNotificationControllerProvider).showInfoToast('剪贴板是空的，先复制订阅链接');
        } catch (_) {}
        return;
      }
      await ref.read(addProfileNotifierProvider.notifier).addClipboard(text);
    }

    return Padding(
      key: const ValueKey('home_empty_guide'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(color: MuseColors.card(context), borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: MuseColors.brand.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: const Icon(Icons.link_rounded, color: MuseColors.brandLight, size: 28),
            ),
            const SizedBox(height: 12),
            Text('还没有订阅', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              '复制服务商给你的订阅链接，点「粘贴导入」即可',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('empty_paste_button'),
                onPressed: paste,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('粘贴导入'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('empty_more_button'),
                onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                icon: Icon(PlatformUtils.isDesktop ? Icons.edit_rounded : Icons.qr_code_scanner_rounded, size: 18),
                // no camera scanning on the desktop
                label: Text(PlatformUtils.isDesktop ? '手动输入链接' : '扫码或手动输入'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '导入后点上方圆形按钮连接',
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodesSection extends HookConsumerWidget {
  const _NodesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final running = ref.watch(serviceRunningProvider);
    final testing = useState(false);
    // 1.2.2: when the current 测速 started (its results end the spinner) and the order the list
    // had then (kept while results stream in, so rows don't jump under the finger)
    final testStartedAt = useRef<DateTime?>(null);
    final frozenOrder = useRef<List<String>>(const []);
    final frozenSort = useRef<MuseNodeSort>(MuseNodeSort.delay);
    final showHidden = useState(false);
    final hidden = ref.watch(museHiddenNodesProvider);
    // 1.2.3: 搜索节点 (shown once the list is long enough to need it)
    final searching = useState(false);
    final query = useState('');
    final searchController = useTextEditingController();
    // 1.2.5: 按延迟 / 订阅顺序 / 按地区 (Clash Verge Rev's sort switch, v2rayNG's sort by result)
    final sortMode = MuseNodeSort.fromKey(ref.watch(Preferences.museNodeSort));

    Widget header(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ],
      ),
    );

    if (!running) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('节点'),
          const MuseSection(
            children: [MuseTile(title: '连接后显示节点')],
          ),
        ],
      );
    }

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final group = proxies.valueOrNull;
    // results older than this connection are a previous session's: shown as 测速中
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;

    Future<void> urlTest() async {
      if (group == null || testing.value) return;
      final started = DateTime.now();
      testStartedAt.value = started;
      testing.value = true;
      try {
        await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group.tag);
      } catch (_) {
        // the notifier already logs the failure
      } finally {
        // results stream in over the next seconds; the spinner stops once every node has a new
        // result (checked on each update below), at the latest after 15 s
        Future.delayed(const Duration(seconds: 15), () {
          if (context.mounted && testStartedAt.value == started) testing.value = false;
        });
      }
    }

    // 1.2.5: the 首页 pull-down asks for a 测速
    ref.listen(museNodeTestRequestProvider, (prev, next) {
      if (prev != next) urlTest();
    });

    // 1.2.2: every node answered (or timed out) since 测速 was tapped: stop the spinner
    if (testing.value && group != null && testStartedAt.value != null) {
      final started = testStartedAt.value!.subtract(const Duration(seconds: 1));
      final nodes = group.items.where((e) => !e.isGroup);
      final done = nodes.isNotEmpty &&
          nodes.every((e) => e.hasUrlTestTime() && e.urlTestTime.toDateTime().isAfter(started));
      final minShown = DateTime.now().difference(testStartedAt.value!) > const Duration(milliseconds: 800);
      if (done && minShown) {
        Future.microtask(() {
          if (context.mounted) testing.value = false;
        });
      }
    }

    final selectedItem = group?.items.where((e) => e.tag == group.selected).firstOrNull;
    final String? groupName;
    if (group == null) {
      groupName = null;
    } else if (selectedItem != null && selectedItem.isGroup) {
      final n = selectedItem.tagDisplay.isNotEmpty ? selectedItem.tagDisplay : selectedItem.tag;
      groupName = museKnownGroupName(n) ??
          museGroupKind(type: selectedItem.type, name: n, selectedDisplay: selectedItem.groupSelectedTagDisplay) ??
          n;
    } else {
      groupName = museKnownGroupName(group.tag) ?? museGroupTypeLabel(group.type) ?? group.tag;
    }
    final title = ['节点', ?groupName].join(' · ');

    final nodeTotal = group?.items.where((e) => !e.isGroup).length ?? 0;
    final searchButton = nodeTotal > 6
        ? IconButton(
            key: const ValueKey('node_search_button'),
            tooltip: searching.value ? '关闭搜索' : '搜索节点',
            visualDensity: VisualDensity.compact,
            icon: Icon(searching.value ? Icons.search_off_rounded : Icons.search_rounded, size: 20),
            onPressed: () {
              searching.value = !searching.value;
              if (!searching.value) {
                searchController.clear();
                query.value = '';
              }
            },
          )
        : null;
    bool matches(OutboundInfo e) {
      final q = query.value;
      if (!searching.value || q.trim().isEmpty) return true;
      final n = e.tagDisplay.isNotEmpty ? e.tagDisplay : e.tag;
      return museNodeMatches(n, q, regionOf: museRegionCode);
    }

    final sortButton = nodeTotal > 1
        ? PopupMenuButton<MuseNodeSort>(
            key: const ValueKey('node_sort_button'),
            tooltip: '排序：${sortMode.title}',
            icon: const Icon(Icons.sort_rounded, size: 20),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            initialValue: sortMode,
            onSelected: (m) => ref.read(Preferences.museNodeSort.notifier).update(m.key),
            itemBuilder: (context) => [
              for (final m in MuseNodeSort.values)
                CheckedPopupMenuItem<MuseNodeSort>(
                  key: ValueKey('node_sort_${m.key}'),
                  value: m,
                  checked: m == sortMode,
                  child: Text(m.title),
                ),
            ],
          )
        : null;

    final testButton = TextButton(
      onPressed: group == null || testing.value ? null : urlTest,
      child: testing.value
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('测速'),
    );

    final List<Widget> body;
    if (proxies.isLoading && group == null) {
      body = [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (group == null || group.items.isEmpty) {
      body = [
        MuseSection(
          children: [MuseTile(title: '没有可用节点', subtitle: proxies.hasError ? '读取节点失败，请稍后再试' : '当前配置里没有节点')],
        ),
      ];
    } else {
      final sorted = museOrderNodes<OutboundInfo>(
        group.items,
        sort: sortMode,
        isGroup: (e) => e.isGroup,
        delay: (e) => _freshDelay(e, since),
        isValidDelay: ConnectionConst.isValidDelay,
        region: (e) => museRegionCode(_nodeName(e)),
      );
      final List<OutboundInfo> ordered;
      if (testing.value && frozenOrder.value.isNotEmpty && frozenSort.value == sortMode) {
        // 1.2.2: keep the order from before 测速 while its results arrive
        final byTag = {for (final e in group.items) e.tag: e};
        final known = frozenOrder.value.toSet();
        ordered = [
          for (final t in frozenOrder.value) ?byTag[t],
          ...sorted.where((e) => !known.contains(e.tag)),
        ];
      } else {
        ordered = sorted;
        frozenOrder.value = [for (final e in sorted) e.tag];
        frozenSort.value = sortMode;
      }
      final filtering = searching.value && query.value.trim().isNotEmpty;
      final visible = ordered.where((e) => !hidden.contains(e.tag) && matches(e)).toList();
      final folded = ordered.where((e) => hidden.contains(e.tag) && matches(e)).toList();
      final nodeCount = group.items.where((e) => !e.isGroup).length;
      // a node shows 测速中 only while a test can actually be running
      final recentlyConnected = since != null && DateTime.now().difference(since) < const Duration(seconds: 30);
      final pending = testing.value || recentlyConnected;

      Widget card(OutboundInfo proxy, {bool dimmed = false}) => _NodeCard(
        key: ValueKey(proxy.tag),
        proxy: proxy,
        since: since,
        nodeCount: nodeCount,
        pending: pending,
        dimmed: dimmed,
        selected: group.selected == proxy.tag,
        onLongPress: () => _showNodeDetails(context, ref, proxy, since: since, groupTag: group.tag),
        onTap: () async {
          try {
            await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, proxy.tag);
          } catch (_) {
            // 1.2.2: say so instead of silently staying on the old node
            try {
              ref.read(inAppNotificationControllerProvider).showErrorToast('切换节点失败，请重试');
            } catch (_) {}
          }
        },
      );

      body = [
        if (filtering && visible.isEmpty && folded.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text('没有匹配的节点', style: theme.textTheme.bodyMedium?.copyWith(color: MuseColors.secondaryText(context))),
          ),
        if (sortMode == MuseNodeSort.region) ...[
          // groups on top, then 「🇭🇰 香港 · 5」 headers over each region
          for (final proxy in visible.where((e) => e.isGroup)) card(proxy),
          for (final section in museRegionSections<OutboundInfo>(
            visible,
            isGroup: (e) => e.isGroup,
            region: (e) => museRegionCode(_nodeName(e)),
          )) ...[
            _RegionHeader(region: section.region, count: section.items.length),
            for (final proxy in section.items) card(proxy),
          ],
        ] else
          for (final proxy in visible) card(proxy),
        if (folded.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Material(
              color: MuseColors.card(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('hidden_nodes_toggle'),
                onTap: () => showHidden.value = !showHidden.value,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.block_rounded, size: 18, color: MuseColors.secondaryText(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '不可用（${folded.length}）',
                          style: theme.textTheme.bodyMedium?.copyWith(color: MuseColors.secondaryText(context)),
                        ),
                      ),
                      Text(
                        '测速超时，恢复后自动放回',
                        style: theme.textTheme.bodySmall?.copyWith(color: MuseColors.secondaryText(context)),
                      ),
                      Icon(
                        showHidden.value ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: MuseColors.secondaryText(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showHidden.value || filtering)
            for (final proxy in folded) card(proxy, dimmed: true),
        ],
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(
          title,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [?searchButton, ?sortButton, testButton]),
        ),
        if (searching.value && searchButton != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: TextField(
              key: const ValueKey('node_search_field'),
              controller: searchController,
              autofocus: true,
              onChanged: (v) => query.value = v,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索节点，如 日本、HK、IPLC',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: MuseColors.card(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ...body,
      ],
    );
  }
}

String _nodeName(OutboundInfo e) => e.tagDisplay.isNotEmpty ? e.tagDisplay : e.tag;

/// 1.2.5 按地区: 「🇭🇰 香港 · 5」 above each region's nodes.
class _RegionHeader extends StatelessWidget {
  const _RegionHeader({required this.region, required this.count});

  final String? region;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = region;
    final label = code == null ? '其他' : '${museCountryFlag(code) ?? ''} ${museCountryLabel(code)}'.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
      child: Text(
        '$label · $count',
        key: ValueKey('region_header_${code ?? 'other'}'),
        style: theme.textTheme.labelMedium?.copyWith(color: MuseColors.secondaryText(context), fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 1.2.5: long-press a node — full name, protocol, latency and when it was measured, with
/// 复制名称 / 使用此节点 (v2rayNG / Shadowrocket's node detail sheet, read-only).
Future<void> _showNodeDetails(
  BuildContext context,
  WidgetRef ref,
  OutboundInfo proxy, {
  required DateTime? since,
  required String groupTag,
}) async {
  final name = _nodeName(proxy);
  final delay = _freshDelay(proxy, since);
  final testedAt = proxy.hasUrlTestTime() ? proxy.urlTestTime.toDateTime() : null;
  final String delayText;
  if (delay == 0) {
    delayText = '未测速';
  } else if (ConnectionConst.isValidDelay(delay)) {
    delayText = '$delay ms';
  } else {
    delayText = '超时';
  }
  final region = museRegionCode(name);
  final rows = <(String, String)>[
    ('类型', proxy.isGroup ? (museGroupTypeLabel(proxy.type) ?? '分组') : museProtocolName(proxy.type)),
    if (region != null) ('地区', '${museCountryFlag(region) ?? ''} ${museCountryLabel(region)}'.trim()),
    ('延迟', delayText),
    if (testedAt != null && delay != 0) ('测速时间', museUpdatedAgo(testedAt, now: DateTime.now()).replaceAll('更新', '')),
  ];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: MuseColors.card(context),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final secondary = MuseColors.secondaryText(sheetContext);
      return SafeArea(
        child: Padding(
          key: const ValueKey('node_detail_sheet'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 72, child: Text(k, style: theme.textTheme.bodyMedium?.copyWith(color: secondary))),
                      Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('node_copy_name'),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('复制名称'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: name));
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        try {
                          ref.read(inAppNotificationControllerProvider).showSuccessToast('已复制');
                        } catch (_) {}
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('node_use'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('使用此节点'),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        try {
                          await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(groupTag, proxy.tag);
                        } catch (_) {
                          try {
                            ref.read(inAppNotificationControllerProvider).showErrorToast('切换节点失败，请重试');
                          } catch (_) {}
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A node's delay for sorting: results from before this connection count as not tested yet.
int _freshDelay(OutboundInfo proxy, DateTime? since) {
  final delay = proxy.urlTestDelay;
  if (delay == 0) return 0;
  final testedAt = proxy.hasUrlTestTime() ? proxy.urlTestTime.toDateTime() : null;
  if (since != null && testedAt != null && testedAt.isBefore(since.subtract(const Duration(seconds: 2)))) return 0;
  return delay;
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    super.key,
    required this.proxy,
    required this.since,
    required this.nodeCount,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.pending = true,
    this.dimmed = false,
  });

  final OutboundInfo proxy;
  final DateTime? since;

  /// a url test may be running (测速 tapped / just connected): an untested node shows 测速中,
  /// otherwise —
  final bool pending;

  /// folded into 「不可用」 and shown expanded
  final bool dimmed;

  /// nodes (not groups) in the main group: a 负载均衡 group spreads over these
  final int nodeCount;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = MuseColors.secondaryText(context);
    final delay = proxy.urlTestDelay;
    final testedAt = proxy.hasUrlTestTime() ? proxy.urlTestTime.toDateTime() : null;
    // tested before this connection started (or not yet): the first test is still running
    final stale = delay == 0 ||
        (since != null && testedAt != null && testedAt.isBefore(since!.subtract(const Duration(seconds: 2))));
    final String delayText;
    final Color delayColor;
    if (stale) {
      delayText = pending ? '测速中' : '—';
      delayColor = secondary;
    } else if (ConnectionConst.isValidDelay(delay)) {
      delayText = '$delay ms';
      delayColor = MuseColors.delay(context, delay);
    } else {
      delayText = '超时';
      delayColor = MuseColors.delay(context, ConnectionConst.maxDelay);
    }
    final fullName = proxy.tagDisplay.isNotEmpty ? proxy.tagDisplay : proxy.tag;
    final rawName = proxy.isGroup ? fullName.split(' → ').first.trim() : fullName;
    final name = proxy.isGroup || proxy.type.toLowerCase() == 'direct' || proxy.type.toLowerCase() == 'block'
        ? museGroupName(rawName)
        : rawName;
    final subtitle = proxy.isGroup
        ? museGroupSubtitle(
            type: proxy.type,
            name: rawName,
            selectedDisplay: proxy.groupSelectedTagDisplay,
            nodeCount: nodeCount,
          )
        : museProtocolName(proxy.type); // protocol names stay (user wants them)
    final groupIcon = proxy.isGroup
        ? switch (museGroupIconKind(type: proxy.type, name: rawName, selectedDisplay: proxy.groupSelectedTagDisplay)) {
            MuseGroupIcon.autoFastest => Icons.bolt_rounded,
            MuseGroupIcon.loadBalance => Icons.balance_rounded,
            MuseGroupIcon.manual => Icons.touch_app_rounded,
            MuseGroupIcon.fallback => Icons.alt_route_rounded,
            MuseGroupIcon.other => Icons.folder_rounded,
          }
        : Icons.public_rounded;
    final flag = proxy.isGroup ? null : museFlagEmoji(name);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Material(
        color: selected ? MuseColors.selectedCard(context) : MuseColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? MuseColors.brand : Colors.transparent, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MuseColors.brand.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: flag != null
                      ? Text(flag, style: const TextStyle(fontSize: 20, height: 1.1))
                      : Icon(
                          groupIcon,
                          key: ValueKey('group_icon_${groupIcon.codePoint}'),
                          size: 18,
                          color: MuseColors.brandLight,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: delayColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                // 1.2.5: each result fades in as it arrives during 测速
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                  child: Text(
                    delayText,
                    key: ValueKey(delayText),
                    style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return dimmed ? Opacity(opacity: 0.55, child: row) : row;
  }
}
