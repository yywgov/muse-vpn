// 穿云 - 首页: big connect button, route mode, speed card and node cards (style B).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/home/speed_test.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseHomePage extends HookConsumerWidget {
  const MuseHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(hasAnyProfileProvider).value ?? false;
    return MuseScaffold(
      titleWidget: const _Header(),
      actions: [
        IconButton(
          tooltip: '快速设置',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings(),
        ),
        IconButton(
          key: const ValueKey("profile_add_button"),
          tooltip: '添加订阅/配置',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
        ),
        const SizedBox(width: 4),
      ],
      body: MuseGroupedBody(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _ConnectSection(),
          const _RouteModeSelector(),
          if (hasProfile) ...[const MuseSpeedCard(), const _NodesSection()] else const _EmptyProfileSection(),
        ],
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
    final since = ref.watch(museConnectedSinceProvider).valueOrNull;
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();
    final secondary = MuseColors.secondaryText(context);

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
    final String label = switch (status) {
      Connected() => '已连接',
      Connecting() => '正在连接…',
      Disconnecting() => '正在断开…',
      _ when connection.hasError => '连接失败',
      _ => '未连接',
    };

    // same flow as the original connection button
    Future<void> toggle() async {
      if (status is Connected) {
        await ref.read(connectionNotifierProvider.notifier).toggleConnection();
        return;
      }
      if (ref.read(activeProfileProvider).valueOrNull == null) {
        await ref.read(dialogNotifierProvider.notifier).showNoActiveProfile();
        await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
        return;
      }
      if (await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
        await ref.read(connectionNotifierProvider.notifier).toggleConnection();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          _ConnectButton(connected: connected, busy: busy, onTap: busy ? null : toggle),
          const SizedBox(height: 20),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                if (since != null) TextSpan(text: '  ·  ${museFormatDuration(DateTime.now().difference(since))}'),
              ],
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: connection.hasError && !connected ? theme.colorScheme.error : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            connected ? '↑ ${stats.uplink.toInt().speed()}   ↓ ${stats.downlink.toInt().speed()}' : '点击按钮连接',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The big round button with the 穿云 glyph; glows while connected, breathes while switching.
class _ConnectButton extends HookWidget {
  const _ConnectButton({required this.connected, required this.busy, required this.onTap});

  final bool connected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pulse = useAnimationController(duration: const Duration(milliseconds: 1100));
    useEffect(() {
      if (busy) {
        pulse.repeat(reverse: true);
      } else {
        pulse
          ..stop()
          ..value = 0;
      }
      return null;
    }, [busy]);

    const size = 168.0;
    final active = connected || busy;
    final off = MuseColors.isTrueBlack(context) ? const Color(0xFF1C1C1C) : (dark ? const Color(0xFF1E2A4D) : const Color(0xFFDDE5F4));
    final glyphColor = active ? Colors.white : (dark ? const Color(0xFF8A94B3) : const Color(0xFF7B8AA8));

    return Semantics(
      button: true,
      label: connected ? '断开' : '连接',
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          final glow = connected ? 0.55 : (busy ? 0.25 + 0.3 * pulse.value : 0.0);
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [MuseColors.brandLight, MuseColors.brandDeep],
                    )
                  : null,
              color: active ? null : off,
              boxShadow: [
                if (glow > 0)
                  BoxShadow(color: MuseColors.brand.withValues(alpha: glow), blurRadius: 64, spreadRadius: 10),
              ],
            ),
            child: child,
          );
        },
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Assets.images.glyph.svg(
                  key: ValueKey(glyphColor),
                  width: 92,
                  height: 92,
                  colorFilter: ColorFilter.mode(glyphColor, BlendMode.srcIn),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 配置 / 代理 / 直连 as a pill segmented control.
class _RouteModeSelector extends ConsumerWidget {
  const _RouteModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(ConfigOptions.museRouteMode);
    final secondary = MuseColors.secondaryText(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          Container(
            height: 48,
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
          const SizedBox(height: 6),
          Text(mode.explain, style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
        ],
      ),
    );
  }
}

class _EmptyProfileSection extends ConsumerWidget {
  const _EmptyProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MuseSection(
      header: '节点',
      footer: '支持订阅链接、剪贴板导入、扫描二维码。',
      children: [
        MuseTile(
          leading: const Icon(Icons.add_circle_outline_rounded),
          title: '添加订阅或配置',
          subtitle: '还没有配置，点这里添加',
          chevron: true,
          onTap: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
        ),
      ],
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
    final secondary = MuseColors.secondaryText(context);

    Widget header(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 12, 4),
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
            children: [MuseTile(title: '连接后显示节点', subtitle: '节点列表和延迟由内核提供，连接后即可选择节点、测试延迟。')],
          ),
        ],
      );
    }

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final group = proxies.valueOrNull;

    Future<void> urlTest() async {
      if (group == null || testing.value) return;
      testing.value = true;
      try {
        await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group.tag);
      } catch (_) {
        // the notifier already logs the failure
      } finally {
        // results stream in over the next seconds
        Future.delayed(const Duration(seconds: 3), () {
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
      body = [
        for (final proxy in group.items)
          _NodeCard(
            key: ValueKey(proxy.tag),
            proxy: proxy,
            selected: group.selected == proxy.tag,
            onTap: () async {
              try {
                await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, proxy.tag);
              } catch (_) {
                // the notifier already logs the failure
              }
            },
            onLongPress: () => ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: Text(
            '共 ${group.items.length} 个，长按查看详情',
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header(title, trailing: testButton), ...body],
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    super.key,
    required this.proxy,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final OutboundInfo proxy;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = MuseColors.secondaryText(context);
    final delay = proxy.urlTestDelay;
    final String delayText;
    final Color delayColor;
    if (delay == 0) {
      delayText = '--';
      delayColor = secondary;
    } else if (ConnectionConst.isValidDelay(delay)) {
      delayText = '$delay ms';
      delayColor = MuseColors.delay(context, delay);
    } else {
      delayText = '超时';
      delayColor = MuseColors.delay(context, 99999);
    }
    final fullName = proxy.tagDisplay.isNotEmpty ? proxy.tagDisplay : proxy.tag;
    final rawName = proxy.isGroup ? fullName.split(' → ').first.trim() : fullName;
    final name = proxy.isGroup || proxy.type.toLowerCase() == 'direct' || proxy.type.toLowerCase() == 'block'
        ? museGroupName(rawName)
        : rawName;
    final subtitle = proxy.isGroup
        ? museGroupSubtitle(type: proxy.type, name: rawName, selectedDisplay: proxy.groupSelectedTagDisplay)
        : museProtocolName(proxy.type);
    final badge = proxy.isGroup ? null : museRegionBadge(name);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MuseColors.brand.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: badge != null
                      ? Text(
                          badge,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: MuseColors.brandLight,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : Icon(
                          proxy.isGroup ? Icons.bolt_rounded : Icons.public_rounded,
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
                Container(width: 8, height: 8, decoration: BoxDecoration(color: delayColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  delayText,
                  style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
