// 穿云 1.2.8 - 一键诊断: 网络 → DNS → 节点 → 系统代理/VPN → 外网, one after another, each in plain
// Chinese (see logic/diagnosis.dart).
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/diagnosis.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> showMuseDiagnoseSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: MuseColors.card(context),
  builder: (_) => const _DiagnoseSheet(),
);

class _DiagnoseSheet extends ConsumerStatefulWidget {
  const _DiagnoseSheet();

  @override
  ConsumerState<_DiagnoseSheet> createState() => _DiagnoseSheetState();
}

class _DiagnoseSheetState extends ConsumerState<_DiagnoseSheet> {
  final _items = <MuseDiagItem>[];
  var _running = true;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _add(MuseDiagItem item) {
    if (mounted) setState(() => _items.add(item));
  }

  Future<void> _run() async {
    // 网络: a domestic site, straight out (not through the proxy)
    _add(museDiagNetwork(directOk: await _get('http://www.baidu.com/', direct: true) != null));
    // DNS
    final domestic = await _resolves('www.baidu.com');
    final foreign = await _resolves('www.google.com');
    _add(museDiagDns(domesticOk: domestic, foreignOk: foreign));
    // 节点
    final connected = ref.read(serviceRunningProvider);
    final group = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
    final sel = group?.items.where((e) => e.tag == group.selected).firstOrNull;
    if (connected && group != null && sel != null && !sel.isGroup) {
      try {
        await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(sel.tag);
        await Future<void>.delayed(const Duration(seconds: 4));
      } catch (_) {}
    }
    final now = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
    final cur = now?.items.where((e) => e.tag == now.selected).firstOrNull;
    _add(
      museDiagNode(
        connected: connected,
        delay: cur?.urlTestDelay ?? 0,
        name: cur == null ? null : (cur.tagDisplay.isNotEmpty ? cur.tagDisplay : cur.tag),
      ),
    );
    // 系统代理 / VPN
    final tun = !Platform.isAndroid && ref.read(ConfigOptions.serviceMode) == ServiceMode.tun;
    bool? ours;
    if (connected && Platform.isWindows && !tun) ours = await WindowsProxyGuard.pointsAtUsNow();
    _add(museDiagRouting(connected: connected, android: Platform.isAndroid, tun: tun, systemProxyOurs: ours));
    // 外网
    var internet = false;
    if (connected) {
      await ref.read(museReachProvider.notifier).check();
      internet = ref.read(museReachProvider) == MuseReach.ok;
    }
    _add(museDiagInternet(connected: connected, ok: internet));
    if (mounted) setState(() => _running = false);
  }

  static Future<bool> _resolves(String host) async {
    try {
      final r = await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<int?> _get(String url, {bool direct = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    if (direct) client.findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      unawaited(res.drain<void>().catchError((_) {}));
      return res.statusCode;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = MuseColors.secondaryText(context);
    (IconData, Color) icon(MuseDiagLevel l) => switch (l) {
      MuseDiagLevel.ok => (Icons.check_circle_rounded, const Color(0xFF34C759)),
      MuseDiagLevel.warn => (Icons.error_rounded, Colors.orange),
      MuseDiagLevel.fail => (Icons.cancel_rounded, Colors.red),
      MuseDiagLevel.skip => (Icons.remove_circle_outline_rounded, secondary),
    };
    return SafeArea(
      child: Padding(
        key: const ValueKey('diagnose_sheet'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('一键诊断', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon(item.level).$1, color: icon(item.level).$2, size: 20),
                    const SizedBox(width: 10),
                    SizedBox(width: 96, child: Text(item.title, style: theme.textTheme.bodyMedium?.copyWith(color: secondary))),
                    Expanded(child: Text(item.text, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            if (_running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else ...[
              const SizedBox(height: 12),
              Text(museDiagConclusion(_items), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
