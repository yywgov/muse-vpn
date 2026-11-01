// 穿云 - 设置 › 网络. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 网络

class MuseNetworkPage extends HookConsumerWidget {
  const MuseNetworkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dns = museDnsPreset(ref.watch(MusePrefs.dnsPreset));
    final schedule = MuseSchedule.parse(ref.watch(MusePrefs.schedule));

    Future<void> pickTime(bool connect) async {
      final cur = connect ? schedule.connectAt : schedule.disconnectAt;
      final picked = await showTimePicker(
        context: context,
        initialTime: cur < 0 ? TimeOfDay(hour: connect ? 8 : 23, minute: 0) : TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
        helpText: connect ? '每天定时连接' : '每天定时断开',
        cancelText: '关闭',
      );
      final m = picked == null ? -1 : picked.hour * 60 + picked.minute;
      final next = connect
          ? MuseSchedule(connectAt: m, disconnectAt: schedule.disconnectAt)
          : MuseSchedule(connectAt: schedule.connectAt, disconnectAt: m);
      await ref.read(MusePrefs.schedule.notifier).update(next.toRaw());
    }

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
          // 1.4.1
          MuseSection(
            header: '定时',
            footer: '穿云需在运行（可在后台）；时间到时只执行一次，手动操作随时优先',
            children: [
              MuseTile(
                key: const ValueKey('network_schedule_connect'),
                leading: const Icon(Icons.alarm_on_outlined),
                title: '每天定时连接',
                trailing: Text(museMinuteLabel(schedule.connectAt)),
                chevron: true,
                onTap: () => pickTime(true),
              ),
              MuseTile(
                key: const ValueKey('network_schedule_disconnect'),
                leading: const Icon(Icons.alarm_off_outlined),
                title: '每天定时断开',
                trailing: Text(museMinuteLabel(schedule.disconnectAt)),
                chevron: true,
                onTap: () => pickTime(false),
              ),
            ],
          ),
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
