// 穿云 - 设置 › 网络. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// 1.10.0: the 设置 home page's collapsed 「高级」 (负载均衡策略 / TLS 分片 / IPv6 / Fake-IP / 屏蔽 QUIC /
// 切换节点时关闭旧连接) is the 「高级」 group here, and Windows 运行模式 sits on top. Same preferences.
// 1.11.0: 连接质量提醒 removed; TLS 分片 and 屏蔽 QUIC stay in view, 负载均衡策略 / IPv6 / Fake-IP /
// 切换节点时关闭旧连接 fold into 「高级」.
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 网络

class MuseNetworkPage extends HookConsumerWidget {
  const MuseNetworkPage({super.key, this.windows, this.advancedOpen = false});

  /// 1.11.0: open with 「高级」 unfolded (a search result inside it)
  final bool advancedOpen;

  /// Platform override for tests; null = the running platform.
  final bool? windows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final dns = museDnsPreset(ref.watch(MusePrefs.dnsPreset));
    final balancer = ref.watch(ConfigOptions.balancerStrategy);
    final ipv6 = MuseIpv6Policy.fromKey(ref.watch(MusePrefs.ipv6Policy));
    final hosts = museParseHosts(ref.watch(MusePrefs.hosts));
    return MuseScaffold(
      title: '网络',
      body: MuseGroupedBody(
        children: [
          if (windows ?? PlatformUtils.isWindows) const MuseSection(children: [MuseWindowsModeTile(), MuseUwpLoopbackTile()]),
          MuseSection(
            header: 'DNS',
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
              // 1.20.3：自定义 hosts 属于域名解析，从分流规则挪到这里（同一个键 MusePrefs.hosts）
              MuseTile(
                key: const ValueKey('routing_hosts'),
                leading: const Icon(Icons.edit_note_outlined),
                title: '自定义 hosts',
                trailing: Text(hosts.isEmpty ? '无' : '${hosts.length} 条'),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(
                    context,
                    '自定义 hosts',
                    initial: ref.read(MusePrefs.hosts),
                    hint: '每行一条：1.2.3.4 example.com',
                    maxLines: 8,
                  );
                  if (v != null) await ref.read(MusePrefs.hosts.notifier).update(v);
                },
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('network_tls_tricks'),
                leading: const Icon(Icons.call_split_outlined),
                title: 'TLS 分片',
                chevron: true,
                onTap: () => context.goNamed('tlsTricks'),
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
            ],
          ),
          // 1.11.0: rarely changed options fold into 「高级」 (same preferences)
          MuseFoldSection(
            key: const ValueKey('network_advanced'),
            foldKey: const ValueKey('network_advanced_fold'),
            summary: '负载均衡策略、IPv6、Fake-IP、切换节点时关闭旧连接',
            initiallyOpen: advancedOpen,
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
              // 1.12.0 (Windows 系统代理): 本机、局域网、.local 不走代理
              if (windows ?? PlatformUtils.isWindows)
                MuseTile(
                  key: const ValueKey('proxy_bypass'),
                  leading: const Icon(Icons.lan_outlined),
                  title: '不走代理的地址',
                  info: '只影响系统代理模式：访问这些地址（路由器、NAS、打印机等）时直接连接。默认包含本机、局域网网段和 .local',
                  trailing: Text(ref.watch(MusePrefs.proxyBypass).trim().isEmpty ? '默认' : '${museProxyBypassList(ref.watch(MusePrefs.proxyBypass)).length} 项'),
                  chevron: true,
                  onTap: () => museEditProxyBypass(context, ref),
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


/// 1.12.0: 编辑「不走代理的地址」：每行一个，留空 = 默认列表。下次连接时生效。
Future<void> museEditProxyBypass(BuildContext context, WidgetRef ref) async {
  final raw = ref.read(MusePrefs.proxyBypass);
  final controller = TextEditingController(text: museProxyBypassList(raw).join('\n'));
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('不走代理的地址'),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const ValueKey('proxy_bypass_field'),
          controller: controller,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(helperText: '每行一个，支持 * 通配；下次连接时生效'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('恢复默认')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('保存')),
      ],
    ),
  );
  controller.dispose();
  if (result == null) return;
  final list = museProxyBypassList(result);
  final isDefault = result.trim().isEmpty || (list.length == museDefaultProxyBypass.length && list.every(museDefaultProxyBypass.contains));
  await ref.read(MusePrefs.proxyBypass.notifier).update(isDefault ? '' : list.join('\n'));
}
