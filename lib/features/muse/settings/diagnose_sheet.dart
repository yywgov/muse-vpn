// 穿云 1.3.0 - 诊断: the one sheet for every check (was 一键诊断 + 出口检测 + 外网检测).
// 网络 → DNS → 节点 → 系统代理/VPN → 外网 → 出口 (IP / region, Google · ChatGPT · Netflix), each in
// plain Chinese (logic/diagnosis.dart), plus 复制 / 导出 the redacted log.
// Opened from the 首页 出口 IP tile and from 设置.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/diagnostics.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/diagnosis.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
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
    final connected = ref.read(serviceRunningProvider);
    // 出口 / services: checked alongside, shown live below
    if (connected) unawaited(ref.read(museExitProvider.notifier).check());
    // 网络: a domestic site, straight out (not through the proxy)
    _add(museDiagNetwork(directOk: await _get('http://www.baidu.com/', direct: true) != null));
    // DNS
    final domestic = await _resolves('www.baidu.com');
    final foreign = await _resolves('www.google.com');
    _add(museDiagDns(domesticOk: domestic, foreignOk: foreign));
    // 节点
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
    // 外网 (generate_204)
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

  void _toast(String text, {bool error = false}) {
    try {
      final n = ref.read(inAppNotificationControllerProvider);
      error ? n.showErrorToast(text) : n.showSuccessToast(text);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final connected = ref.watch(serviceRunningProvider);
    final exit = ref.watch(museExitProvider);
    (IconData, Color) icon(MuseDiagLevel l) => switch (l) {
      MuseDiagLevel.ok => (Icons.check_circle_rounded, MusePalette.green),
      MuseDiagLevel.warn => (Icons.error_rounded, MusePalette.orange),
      MuseDiagLevel.fail => (Icons.cancel_rounded, MusePalette.red),
      MuseDiagLevel.skip => (Icons.remove_circle_outline_rounded, mt.text3),
    };
    Widget line(Widget leading, String title, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: MuseSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: MuseSpace.s12),
          SizedBox(width: MuseSize.labelColumnWide, child: Text(title, style: MuseType.body(context).copyWith(color: mt.text2))),
          Expanded(child: value),
        ],
      ),
    );
    final info = exit?.info;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          key: const ValueKey('diagnose_sheet'),
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('诊断', style: MuseType.title(context)),
              const SizedBox(height: MuseSpace.s8),
              for (final item in _items)
                line(
                  Icon(icon(item.level).$1, color: icon(item.level).$2, size: MuseIconSize.small),
                  item.title,
                  Text(item.text, style: MuseType.body(context)),
                ),
              if (connected) ...[
                line(
                  Icon(
                    info != null ? Icons.check_circle_rounded : Icons.travel_explore_rounded,
                    color: info != null ? MusePalette.green : mt.text3,
                    size: MuseIconSize.small,
                  ),
                  '出口',
                  Text(
                    key: const ValueKey('diagnose_exit'),
                    info != null
                        ? '${museCountryFlag(info.country) ?? ''} ${museCountryLabel(info.country)} · ${museMaskIp(info.ip)}'.trim()
                        : (exit?.infoFailed ?? false)
                        ? '获取出口失败'
                        : '检测中…',
                    style: MuseType.body(context).copyWith(fontFeatures: MuseType.tabular),
                  ),
                ),
                const SizedBox(height: MuseSpace.s4),
                Row(
                  children: [
                    Expanded(child: _ServiceChip(name: 'Google', state: exit?.google ?? MuseServiceState.checking)),
                    const SizedBox(width: MuseSpace.s8),
                    Expanded(child: _ServiceChip(name: 'ChatGPT', state: exit?.chatGpt ?? MuseServiceState.checking)),
                    const SizedBox(width: MuseSpace.s8),
                    Expanded(
                      child: _ServiceChip(name: 'Netflix', state: exit?.netflix ?? MuseServiceState.checking, partial: '仅自制剧'),
                    ),
                  ],
                ),
              ],
              if (_running)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: MuseSpace.s12),
                  child: Center(child: SizedBox(width: MuseIconSize.small, height: MuseIconSize.small, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else ...[
                const SizedBox(height: MuseSpace.s16),
                Text(museDiagConclusion(_items), style: MuseType.body(context).copyWith(fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: MuseSpace.s16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('diagnose_copy_log'),
                      icon: const Icon(Icons.copy_rounded, size: MuseIconSize.small),
                      label: const Text('复制日志'),
                      onPressed: () async {
                        final text = await MuseDiagnostics.redactedText(ref);
                        if (text == null) return _toast('读取日志失败', error: true);
                        await Clipboard.setData(ClipboardData(text: text));
                        _toast('已复制（已脱敏）');
                      },
                    ),
                  ),
                  const SizedBox(width: MuseSpace.s12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('diagnose_export_log'),
                      icon: const Icon(Icons.ios_share_rounded, size: MuseIconSize.small),
                      label: const Text('导出日志'),
                      onPressed: () async {
                        if (!await MuseDiagnostics.export(ref)) _toast('导出失败', error: true);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.name, required this.state, this.partial = '部分'});

  final String name;
  final MuseServiceState state;
  final String partial;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final Color dot = switch (state) {
      MuseServiceState.ok => MusePalette.green,
      MuseServiceState.partial => MusePalette.orange,
      MuseServiceState.blocked => MusePalette.red,
      MuseServiceState.failed => MusePalette.red,
      MuseServiceState.checking => mt.text3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8, vertical: MuseSpace.s8),
      decoration: BoxDecoration(color: mt.inner, borderRadius: MuseRadius.smallAll),
      child: Row(
        children: [
          Container(width: MuseSize.dot, height: MuseSize.dot, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: MuseSpace.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.caption(context).copyWith(color: mt.text1)),
                Text(museServiceStateLabel(state, partial: partial), maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.caption(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
