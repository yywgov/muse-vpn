// 穿云 - 设置 › 网络. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 网络

class MuseNetworkPage extends HookConsumerWidget {
  const MuseNetworkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dns = museDnsPreset(ref.watch(MusePrefs.dnsPreset));
    return MuseScaffold(
      title: '网络',
      body: MuseGroupedBody(
        children: [
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
        ],
      ),
    );
  }
}
