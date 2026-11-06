// 穿云 1.12.0 - 点出口 IP 卡打开的「出口 IP 详情」：点开才查（经当前代理），按 IP 缓存 1 天。
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/port_override.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/exit_detail.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart' show museScrollEndGap;
import 'package:hooks_riverpod/hooks_riverpod.dart';

const museIpApiUrl =
    'http://ip-api.com/json/?lang=zh-CN&fields=status,country,countryCode,regionName,city,isp,org,as,mobile,proxy,hosting,query';
const museIpWhoUrl = 'https://ipwho.is/?lang=zh-CN';

/// Looks the exit up through 127.0.0.1:[port] (straight out when it does not listen): the main
/// source first, the other one when it fails. Null = both failed.
Future<MuseExitDetail?> museFetchExitDetail(int port) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 2)
    ..userAgent = 'Mozilla/5.0';
  try {
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
      s.destroy();
      client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
    } catch (_) {}
    Future<String?> get(String url) async {
      try {
        final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) {
          unawaited(res.drain<void>().catchError((_) {}));
          return null;
        }
        return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
      } catch (_) {
        return null;
      }
    }

    final now = DateTime.now();
    final a = await get(museIpApiUrl);
    final d = a == null ? null : museParseIpApi(a, at: now);
    if (d != null) return d;
    final b = await get(museIpWhoUrl);
    return b == null ? null : museParseIpWho(b, at: now);
  } finally {
    client.close(force: true);
  }
}

Future<void> showMuseExitDetailSheet(BuildContext context) => showMuseSnapSheet<void>(
  context,
  title: '出口 IP 详情',
  builder: (ctx, controller) => MuseExitDetailBody(controller: controller),
);

class MuseExitDetailBody extends HookConsumerWidget {
  const MuseExitDetailBody({super.key, required this.controller, this.fetch});

  final ScrollController controller;

  /// tests: replaces the network lookup
  final Future<MuseExitDetail?> Function()? fetch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(museRunningProvider);
    final detail = useState<MuseExitDetail?>(null);
    final changed = useState<bool?>(null);
    final loading = useState(false);
    final failed = useState(false);

    Future<void> load({bool force = false}) async {
      if (loading.value) return;
      final cache = MuseExitDetailCache.parse(ref.read(MusePrefs.exitDetailCache));
      final ip = ref.read(museExitProvider)?.info?.ip ?? '';
      if (!force && ip.isNotEmpty) {
        final hit = cache.fresh(ip, DateTime.now());
        if (hit != null) {
          detail.value = hit;
          failed.value = false;
          return;
        }
      }
      loading.value = true;
      failed.value = false;
      final d = await (fetch?.call() ?? museFetchExitDetail(museEffectiveMixedPort(ref.read)));
      if (!context.mounted) return;
      loading.value = false;
      if (d == null) {
        failed.value = true;
        return;
      }
      changed.value = museExitChanged(cache.lastIp, d.ip);
      detail.value = d;
      await ref.read(MusePrefs.exitDetailCache.notifier).update(cache.store(d).toRaw());
    }

    useEffect(() {
      if (running) Future.microtask(load);
      return null;
    }, const []);

    final mask = ref.watch(MusePrefs.privacyMask);
    final d = detail.value;
    Widget row(String k, String v, {String? sub, Key? key}) => MuseTile(key: key, title: k, subtitle: sub, trailing: Text(v));
    return ListView(
      key: const ValueKey('exit_detail_sheet'),
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
      children: [
        Text(running ? '经当前节点查询公开的 IP 信息，结果保留 1 天' : '连接后才能查询', style: MuseType.caption(context)),
        const SizedBox(height: MuseSpace.s8),
        if (loading.value) const Padding(padding: EdgeInsets.all(MuseSpace.s16), child: Center(child: CircularProgressIndicator())),
        if (failed.value && !loading.value) Text('暂不可用，请稍后再试', key: const ValueKey('exit_detail_failed'), style: MuseType.body(context)),
        if (d != null) ...[
          row('IP 地址', mask ? museMaskIp(d.ip) : d.ip, key: const ValueKey('exit_detail_ip')),
          row('协议', d.isV6 ? 'IPv6' : 'IPv4'),
          row('地区', '${museCountryFlag(d.country) ?? ''} ${museCountryLabel(d.country)}'.trim(), sub: d.place.isEmpty ? null : d.place),
          if (d.isp.isNotEmpty) row('运营商', d.isp),
          if (d.asn.isNotEmpty) row('自治系统号（ASN）', d.asn),
          row('IP 类型', d.kind.title, sub: d.kind.hint.isEmpty ? null : d.kind.hint, key: const ValueKey('exit_detail_kind')),
          if (changed.value != null)
            row('和上次相比', changed.value! ? '出口已变化' : '没有变化', key: const ValueKey('exit_detail_changed')),
        ],
        const SizedBox(height: MuseSpace.s8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('exit_detail_refresh'),
                onPressed: running && !loading.value ? () => load(force: true) : null,
                child: const Text('重新查询'),
              ),
            ),
            const SizedBox(width: MuseSpace.s8),
            if (d != null)
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: d.ip));
                    try {
                      ref.read(inAppNotificationControllerProvider).showSuccessToast('已复制 IP');
                    } catch (_) {}
                  },
                  child: const Text('复制 IP'),
                ),
              ),
            if (d != null) const SizedBox(width: MuseSpace.s8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('exit_detail_diagnose'),
                onPressed: () {
                  Navigator.pop(context);
                  showMuseDiagnoseSheet(context);
                },
                child: const Text('网络诊断'),
              ),
            ),
          ],
        ),
        SizedBox(height: museScrollEndGap(context, MuseSpace.s24)),
      ],
    );
  }
}
