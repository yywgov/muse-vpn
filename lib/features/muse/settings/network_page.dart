// 穿云 - 设置 › 网络. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// 1.10.0: the 设置 home page's collapsed 「高级」 (负载均衡策略 / TLS 分片 / IPv6 / Fake-IP / 屏蔽 QUIC /
// 切换节点时关闭旧连接) is the 「高级」 group here, and Windows 运行模式 sits on top. Same preferences.
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 网络

class MuseNetworkPage extends HookConsumerWidget {
  const MuseNetworkPage({super.key, this.windows});

  /// Platform override for tests; null = the running platform.
  final bool? windows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final dns = museDnsPreset(ref.watch(MusePrefs.dnsPreset));
    final balancer = ref.watch(ConfigOptions.balancerStrategy);
    final ipv6 = MuseIpv6Policy.fromKey(ref.watch(MusePrefs.ipv6Policy));
    return MuseScaffold(
      title: '网络',
      body: MuseGroupedBody(
        children: [
          if (windows ?? PlatformUtils.isWindows) const MuseSection(children: [MuseWindowsModeTile()]),
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('network_dns'),
                leading: const Icon(Icons.dns_outlined),
                title: '远程 DNS',
                trailing: Text(dns.title),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<String>(context, '远程 DNS', [for (final p in museDnsPresets) (p.key, p.title)], dns.key);
                  if (picked != null) await ref.read(MusePrefs.dnsPreset.notifier).update(picked);
                },
              ),
              // 1.9.0 #78: one tap back to the recommended DNS
              if (dns.key != museDnsPresets.first.key)
                MuseTile(
                  key: const ValueKey('network_dns_restore'),
                  leading: const Icon(Icons.restart_alt_outlined),
                  title: '恢复推荐 DNS',
                  subtitle: '改回「${museDnsPresets.first.title}」',
                  onTap: () => ref.read(MusePrefs.dnsPreset.notifier).update(museDnsPresets.first.key),
                ),
            ],
          ),
          // 1.9.0 #5: 定时连接 / 断开 moved to 设置 › 自动连接
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('network_quality_alert'),
                leading: const Icon(Icons.network_check_outlined),
                title: '连接质量提醒',
                info: '当前节点延迟持续偏高或超时时通知（每分钟测一次）',
                value: ref.watch(MusePrefs.qualityAlert),
                onChanged: (v) => ref.read(MusePrefs.qualityAlert.notifier).update(v),
              ),
            ],
          ),
          MuseSection(
            key: const ValueKey('network_advanced'),
            header: '高级',
            children: [
              MuseTile(
                key: const ValueKey('balancer_strategy'),
                leading: const Icon(Icons.balance_outlined),
                title: '负载均衡策略',
                trailing: Text(balancer.present(t)),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<BalancerStrategy>(
                    context,
                    '负载均衡策略',
                    [for (final b in BalancerStrategy.values) (b, b.present(t))],
                    balancer,
                  );
                  if (picked != null) await ref.read(ConfigOptions.balancerStrategy.notifier).update(picked);
                },
              ),
              MuseTile(
                key: const ValueKey('network_tls_tricks'),
                leading: const Icon(Icons.call_split_outlined),
                title: 'TLS 分片',
                chevron: true,
                onTap: () => context.goNamed('tlsTricks'),
              ),
              // 1.5.0: network options that can break a working setup, all off by default
              MuseTile(
                key: const ValueKey('ipv6_policy'),
                leading: const Icon(Icons.language_outlined),
                title: 'IPv6',
                info: '只在本地网络和节点都支持 IPv6 时开启，否则可能打不开网页',
                trailing: Text(ipv6.title),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<MuseIpv6Policy>(context, 'IPv6', [for (final p in MuseIpv6Policy.values) (p, p.title)], ipv6);
                  if (picked != null) await ref.read(MusePrefs.ipv6Policy.notifier).update(picked.key);
                },
              ),
              MuseSwitchTile(
                key: const ValueKey('fake_ip'),
                leading: const Icon(Icons.dns_outlined),
                title: 'Fake-IP',
                info: '仅 TUN 模式生效：域名先拿到虚拟地址，打开网页更快；局域网、对时和联网检测仍用真实地址。个别 App 或游戏异常时请关闭',
                value: ref.watch(ConfigOptions.enableFakeDns),
                onChanged: (v) => ref.read(ConfigOptions.enableFakeDns.notifier).update(v),
              ),
              // 1.5.0 #9
              MuseSwitchTile(
                key: const ValueKey('block_quic'),
                leading: const Icon(Icons.block_outlined),
                title: '屏蔽 QUIC',
                info: '节点 UDP 不稳时打开：YouTube 等网站改走 TCP，播放更稳',
                value: ref.watch(MusePrefs.blockQuic),
                onChanged: (v) => ref.read(MusePrefs.blockQuic.notifier).update(v),
              ),
              MuseSwitchTile(
                key: const ValueKey('settings_auto_close'),
                leading: const Icon(Icons.link_off_outlined),
                title: '切换节点时关闭旧连接',
                info: '换节点后，仍走旧节点的连接会立即断开并通过新节点重连',
                value: ref.watch(MusePrefs.autoCloseConnections),
                onChanged: (v) => ref.read(MusePrefs.autoCloseConnections.notifier).update(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
