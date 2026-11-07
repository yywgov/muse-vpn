// 穿云 1.13.0 - 连不上一键诊断. Nothing runs until 「开始诊断」 is tapped: then 网络 → DNS → 节点可达
// → 端口占用 → 其他 VPN, one conclusion in plain Chinese (logic/connect_doctor.dart) and fix buttons
// (释放内核、打开 VPN 设置、切换节点、重新检测). Opened from 首页 after a failed connect and from 活动 › 诊断.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/port_override.dart';
import 'package:hiddify/features/muse/logic/connect_doctor.dart';
import 'package:hiddify/features/muse/logic/diagnosis.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart' show museRecentFromRaw;
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> showMuseConnectDoctor(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: MuseColors.card(context),
  builder: (_) => const MuseConnectDoctorView(),
);

class MuseConnectDoctorView extends ConsumerStatefulWidget {
  const MuseConnectDoctorView({super.key});

  @override
  ConsumerState<MuseConnectDoctorView> createState() => _DoctorState();
}

class _DoctorState extends ConsumerState<MuseConnectDoctorView> {
  MuseDoctorInput? _result;
  var _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _result = null;
    });
    try {
      final r = await _check();
      if (mounted) setState(() => _result = r);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<MuseDoctorInput> _check() async {
    final connected = ref.read(serviceRunningProvider);
    final networkOk = await _directOk();
    final dnsOk = await _resolves('www.baidu.com');
    // 节点: the one in use, or the last one picked when disconnected
    final group = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
    var tag = group?.selected ?? '';
    if (tag.isEmpty) tag = museRecentFromRaw(ref.read(MusePrefs.recentNodes)).firstOrNull ?? '';
    var raw = '';
    try {
      raw = await ref.read(museActiveConfigProvider.future).timeout(const Duration(seconds: 3));
    } catch (_) {}
    final ep = museNodeEndpoint(raw, tag);
    bool? reachable;
    if (ep != null && !ep.udp && networkOk) reachable = await _tcp(ep.host, ep.port, const Duration(seconds: 4));
    // 端口: listening while disconnected = something still holds it
    final mixed = museEffectiveMixedPort(ref.read);
    var coreBusy = false;
    var mixedBusy = false;
    if (!connected) {
      if (Platform.isAndroid) coreBusy = await _tcp('127.0.0.1', museCorePort, const Duration(seconds: 1));
      if (mixed > 0) mixedBusy = await _tcp('127.0.0.1', mixed, const Duration(seconds: 1));
    }
    final otherVpn = connected ? null : await ChuanyunPlatform.otherVpnActive();
    return MuseDoctorInput(
      connected: connected,
      networkOk: networkOk,
      dnsOk: dnsOk,
      nodeName: tag,
      nodeReachable: ep == null ? null : reachable,
      nodeUdp: ep?.udp ?? false,
      corePortBusy: coreBusy,
      mixedPort: mixed,
      mixedPortBusy: mixedBusy,
      otherVpn: otherVpn,
    );
  }

  static Future<bool> _tcp(String host, int port, Duration timeout) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _resolves(String host) async {
    try {
      return (await InternetAddress.lookup(host).timeout(const Duration(seconds: 5))).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _directOk() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(Uri.parse('http://www.baidu.com/')).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      unawaited(res.drain<void>().catchError((_) {}));
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _fix(MuseDoctorFix f) async {
    switch (f) {
      case MuseDoctorFix.releaseCore:
        await ChuanyunPlatform.releaseCore();
        _toast('已释放后台内核');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _run();
      case MuseDoctorFix.openVpnSettings:
        if (!await ChuanyunPlatform.openVpnSettings()) _toast('无法打开系统 VPN 设置，请在系统设置里查找「VPN」', error: true);
      case MuseDoctorFix.switchNode:
        if (mounted) Navigator.of(context).pop();
        if (mounted) await showMuseNodePicker(context);
      case MuseDoctorFix.retest:
        await _run();
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
    final r = _result;
    (IconData, Color) icon(MuseDiagLevel l) => switch (l) {
      MuseDiagLevel.ok => (Icons.check_circle_outlined, MusePalette.green),
      MuseDiagLevel.warn => (Icons.error_outlined, MusePalette.orange),
      MuseDiagLevel.fail => (Icons.cancel_outlined, MusePalette.red),
      MuseDiagLevel.skip => (Icons.remove_circle_outlined, mt.text3),
    };
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('connect_doctor'),
        padding: const EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('连不上？一键诊断', style: MuseType.title(context)),
            const SizedBox(height: MuseSpace.s8),
            Text(
              '依次检查网络、DNS、节点能否连通、端口是否被占用、有没有其他 VPN，并给出结论和修复办法。点「开始诊断」才会检查。',
              style: MuseType.caption(context).copyWith(color: mt.text2),
            ),
            const SizedBox(height: MuseSpace.s16),
            if (r == null)
              FilledButton.icon(
                key: const ValueKey('connect_doctor_start'),
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.medical_services_outlined),
                label: Text(_running ? '正在诊断…' : '开始诊断'),
              )
            else ...[
              for (final item in museDoctorItems(r))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon(item.level).$1, color: icon(item.level).$2, size: 20),
                      const SizedBox(width: MuseSpace.s8),
                      SizedBox(width: 72, child: Text(item.title, style: MuseType.body(context).copyWith(color: mt.text2))),
                      Expanded(child: Text(item.text, style: MuseType.body(context))),
                    ],
                  ),
                ),
              const SizedBox(height: MuseSpace.s12),
              Text('结论：${museDoctorConclusion(r)}', key: const ValueKey('connect_doctor_conclusion'), style: MuseType.body(context).copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: MuseSpace.s12),
              Wrap(
                spacing: MuseSpace.s8,
                runSpacing: MuseSpace.s8,
                children: [
                  for (final f in museDoctorFixes(r, android: Platform.isAndroid))
                    f == MuseDoctorFix.retest
                        ? OutlinedButton(onPressed: _running ? null : () => _fix(f), child: Text(f.title))
                        : FilledButton.tonal(onPressed: _running ? null : () => _fix(f), child: Text(f.title)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
