// Muse VPN - Shadowrocket-style home tab (首页).
// Part of Muse VPN, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseHomePage extends HookConsumerWidget {
  const MuseHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(hasAnyProfileProvider).value ?? false;
    return Scaffold(
      backgroundColor: MuseColors.background(context),
      appBar: AppBar(
        backgroundColor: MuseColors.background(context),
        scrolledUnderElevation: 0,
        title: const Text('Muse VPN'),
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
      ),
      body: MuseGroupedBody(
        children: [
          const _ConnectionSection(),
          const MuseSection(header: '全局路由', children: [MuseRouteModeSelector()]),
          if (hasProfile) const _NodesSection() else const _EmptyProfileSection(),
        ],
      ),
    );
  }
}

class _ConnectionSection extends HookConsumerWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connection = ref.watch(connectionNotifierProvider);
    final activeProfile = ref.watch(activeProfileProvider).value;
    final since = ref.watch(museConnectedSinceProvider);
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();

    // tick every second while connected, for the duration label
    final tick = useState(0);
    useEffect(() {
      if (since == null) return null;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => tick.value++);
      return timer.cancel;
    }, [since]);

    final status = connection.valueOrNull;
    final (label, color) = switch (status) {
      Connected() => ('已连接', Colors.green),
      Connecting() => ('连接中…', Colors.orange),
      Disconnecting() => ('断开中…', Colors.orange),
      _ when connection.hasError => ('连接失败', theme.colorScheme.error),
      _ => ('未连接', MuseColors.secondaryText(context)),
    };
    final isOn = status is Connected || status is Connecting;
    final busy = status?.isSwitching ?? false;
    final secondary = MuseColors.secondaryText(context);

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

    return MuseSection(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          leading: Icon(Icons.shield_rounded, color: color, size: 32),
          title: Text('连接', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: TextStyle(color: color),
                ),
                if (since != null) TextSpan(text: '  ${museFormatDuration(DateTime.now().difference(since))}'),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
          trailing: Switch.adaptive(value: isOn, onChanged: busy ? null : (_) => toggle()),
          onTap: busy ? null : toggle,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: _SpeedLabel(icon: Icons.arrow_upward_rounded, text: stats.uplink.toInt().speed()),
              ),
              Expanded(
                child: _SpeedLabel(icon: Icons.arrow_downward_rounded, text: stats.downlink.toInt().speed()),
              ),
            ],
          ),
        ),
        if (activeProfile != null) MuseTile(title: '当前配置', subtitle: activeProfile.name, subtitleMaxLines: 1),
      ],
    );
  }
}

class _SpeedLabel extends StatelessWidget {
  const _SpeedLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final secondary = MuseColors.secondaryText(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: secondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _EmptyProfileSection extends ConsumerWidget {
  const _EmptyProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MuseSection(
      header: '服务器节点',
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
    final running = ref.watch(serviceRunningProvider);
    final testing = useState(false);
    final secondary = MuseColors.secondaryText(context);

    if (!running) {
      return const MuseSection(
        header: '服务器节点',
        children: [MuseTile(title: '连接后显示节点', subtitle: '节点列表和延迟由内核提供，打开上方「连接」后即可选择节点、测试延迟')],
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

    final header = TextButton.icon(
      onPressed: group == null || testing.value ? null : urlTest,
      icon: testing.value
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.speed_rounded, size: 18),
      label: const Text('测试延迟'),
    );

    final List<Widget> rows;
    if (proxies.isLoading && group == null) {
      rows = [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (group == null || group.items.isEmpty) {
      rows = [MuseTile(title: '没有可用节点', subtitle: proxies.hasError ? '读取节点失败，请稍后再试' : '当前配置里没有节点')];
    } else {
      rows = [
        for (final proxy in group.items)
          _NodeTile(
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
      ];
    }

    return MuseSection(
      header: '服务器节点',
      headerTrailing: header,
      footer: group == null ? null : '共 ${group.items.length} 个，长按查看节点详情',
      children: rows.isEmpty ? [Text('', style: TextStyle(color: secondary))] : rows,
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({required this.proxy, required this.selected, required this.onTap, required this.onLongPress});

  final OutboundInfo proxy;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delay = proxy.urlTestDelay;
    final String delayText;
    final Color delayColor;
    if (delay == 0) {
      delayText = '--';
      delayColor = MuseColors.secondaryText(context);
    } else if (ConnectionConst.isValidDelay(delay)) {
      delayText = '$delay ms';
      delayColor = MuseColors.delay(context, delay);
    } else {
      delayText = '超时';
      delayColor = MuseColors.delay(context, 99999);
    }
    final name = proxy.tagDisplay.isNotEmpty ? proxy.tagDisplay : proxy.tag;
    final groupSelected = proxy.isGroup ? proxy.groupSelectedTagDisplay.trim() : '';

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            MuseProtocolChip(museProtocolLabel(proxy.type, isGroup: proxy.isGroup)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
                  if (groupSelected.isNotEmpty)
                    Text(
                      '→ $groupSelected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: MuseColors.secondaryText(context)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(delayText, style: theme.textTheme.bodySmall?.copyWith(color: delayColor)),
            const SizedBox(width: 8),
            SizedBox(
              width: 24,
              child: selected ? Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 22) : null,
            ),
          ],
        ),
      ),
    );
  }
}
