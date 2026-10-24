// 穿云 1.3.0 - 诊断: the one sheet for every check (was 一键诊断 + 出口检测 + 外网检测).
// 网络 → DNS → 节点 → 系统代理/VPN → 外网 → 出口 (IP / region, Google · ChatGPT · Netflix), each in
// plain Chinese (logic/diagnosis.dart), plus 复制 / 导出 the redacted log.
// Opened from the 首页 出口 IP tile and from 设置.
// Part of 穿云 (GPLv3).

import 'package:hiddify/utils/uri_utils.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/crash_recorder.dart';
import 'package:hiddify/features/muse/data/diagnostics.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show museSaveTextFile;
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
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
    // 1.5.3: the saved result when it is still fresh (刷新 next to 出口 asks again)
    if (connected) unawaited(ref.read(museExitProvider.notifier).ensure().catchError((_) {}));
    // 网络: a domestic site, straight out (not through the proxy); its Date header checks the clock
    final direct = await _get('http://www.baidu.com/', direct: true);
    _add(museDiagNetwork(directOk: direct != null));
    // 1.4.1 时间: a clock off by minutes breaks TLS / VMess
    if (direct != null) _add(museDiagClock(museClockSkew(direct.date, DateTime.now())));
    // 1.4.1 Windows: a system proxy left pointing at a dead local port (穿云 closed abnormally)
    if (Platform.isWindows && !connected) {
      final stale = await WindowsProxyGuard.checkStale(connected: false);
      if (stale.port != null || stale.stale) _add(museDiagStaleProxy(stale: stale.stale, port: stale.port));
    }
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

  static Future<({int status, String? date})?> _get(String url, {bool direct = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    if (direct) client.findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      unawaited(res.drain<void>().catchError((_) {}));
      return (status: res.statusCode, date: res.headers.value(HttpHeaders.dateHeader));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  bool _acting = false;

  /// 1.4.1: what the wizard's buttons do.
  Future<void> _act(MuseDiagAction a) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      switch (a) {
        case MuseDiagAction.repairProxy:
          final ok = await WindowsProxyGuard.repairStale();
          _toast(ok ? '已修复系统代理' : '修复失败，请在 Windows 设置 › 网络 › 代理 中关闭「使用代理服务器」', error: !ok);
        case MuseDiagAction.switchNode:
          if (mounted) Navigator.of(context).pop();
          if (mounted) await showMuseNodePicker(context);
          return;
        case MuseDiagAction.testNodes:
          await museRunNodeTest(ref);
          _toast('已开始测速');
        case MuseDiagAction.updateSubs:
          await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
          _toast('正在更新订阅');
        case MuseDiagAction.reconnect:
          await ref.read(connectionNotifierProvider.notifier).reconnect(await ref.read(activeProfileProvider.future));
          _toast('已重新连接');
        case MuseDiagAction.connect:
          if (mounted) Navigator.of(context).pop();
          await ref.read(connectionNotifierProvider.notifier).toggleConnection();
          return;
        case MuseDiagAction.fixClock:
          if (Platform.isWindows) {
            await Process.start('cmd', ['/c', 'start', 'ms-settings:dateandtime'], mode: ProcessStartMode.detached);
          } else {
            await ChuanyunPlatform.openDateSettings();
          }
      }
      if (!mounted) return;
      setState(() {
        _items.clear();
        _running = true;
      });
      await _run();
    } catch (e) {
      _toast('操作失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _acting = false);
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
      MuseDiagLevel.ok => (Icons.check_circle_outlined, MusePalette.green),
      MuseDiagLevel.warn => (Icons.error_outlined, MusePalette.orange),
      MuseDiagLevel.fail => (Icons.cancel_outlined, MusePalette.red),
      MuseDiagLevel.skip => (Icons.remove_circle_outlined, mt.text3),
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
                    info != null ? Icons.check_circle_outlined : Icons.travel_explore_outlined,
                    color: info != null ? MusePalette.green : mt.text3,
                    size: MuseIconSize.small,
                  ),
                  '出口',
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                        key: const ValueKey('diagnose_exit'),
                        info != null
                            ? '${museCountryFlag(info.country) ?? ''} ${museCountryLabel(info.country)} · ${museMaskIp(info.ip)}'.trim()
                            : (exit?.infoFailed ?? false)
                            ? '获取出口失败'
                            : '检测中…',
                        style: MuseType.body(context).copyWith(fontFeatures: MuseType.tabular),
                        ),
                      ),
                      SizedBox(
                        width: MuseSize.flagBox,
                        height: MuseIconSize.small,
                        child: exit?.refreshing ?? false
                            ? Center(
                                key: const ValueKey('diagnose_exit_refreshing'),
                                child: SizedBox(
                                  width: MuseIconSize.tiny,
                                  height: MuseIconSize.tiny,
                                  child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke, color: mt.text2),
                                ),
                              )
                            : IconButton(
                                key: const ValueKey('diagnose_exit_refresh'),
                                tooltip: '刷新',
                                padding: EdgeInsets.zero,
                                iconSize: MuseIconSize.small,
                                icon: Icon(Icons.refresh_outlined, color: mt.text3),
                                onPressed: () => unawaited(ref.read(museExitProvider.notifier).check().catchError((_) {})),
                              ),
                      ),
                    ],
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
                // 1.4.1 向导: one tap for the fix
                if (museDiagActions(_items, connected: connected).isNotEmpty) ...[
                  const SizedBox(height: MuseSpace.s12),
                  Wrap(
                    key: const ValueKey('diagnose_actions'),
                    spacing: MuseSpace.s8,
                    runSpacing: MuseSpace.s8,
                    children: [
                      for (final a in museDiagActions(_items, connected: connected))
                        FilledButton.tonal(
                          key: ValueKey('diagnose_action_${a.name}'),
                          onPressed: _acting ? null : () => _act(a),
                          child: Text(a.title),
                        ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: MuseSpace.s16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('diagnose_copy_log'),
                      icon: const Icon(Icons.copy_outlined, size: MuseIconSize.small),
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
                      icon: const Icon(Icons.ios_share_outlined, size: MuseIconSize.small),
                      label: const Text('导出日志'),
                      onPressed: () async {
                        if (!await MuseDiagnostics.export(ref)) _toast('导出失败', error: true);
                      },
                    ),
                  ),
                ],
              ),
              // 1.4.1: the local crash log, redacted (nothing is uploaded)
              Wrap(
                spacing: MuseSpace.s8,
                children: [
                  // 1.5.0 #233: diagnosis + crash log copied, an issue opened with version / system
                  TextButton.icon(
                    key: const ValueKey('diagnose_feedback'),
                    icon: const Icon(Icons.feedback_outlined, size: MuseIconSize.small),
                    label: const Text('反馈问题'),
                    onPressed: () async {
                      final log = await MuseDiagnostics.redactedText(ref) ?? '';
                      final crashes = MuseCrashRecorder.exportText(ref.read(sharedPreferencesProvider).requireValue);
                      await Clipboard.setData(ClipboardData(text: [log, if (crashes.isNotEmpty) crashes].join('\n\n')));
                      final info = ref.read(appInfoProvider).valueOrNull;
                      final uri = museFeedbackIssueUri(
                        version: info == null ? '未知' : '${info.version} (${info.buildNumber})',
                        system: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
                      );
                      _toast('诊断信息已复制，请粘贴到反馈里');
                      await UriUtils.tryLaunch(uri);
                    },
                  ),
                  TextButton.icon(
                  key: const ValueKey('diagnose_export_crashes'),
                  icon: const Icon(Icons.bug_report_outlined, size: MuseIconSize.small),
                  label: const Text('导出崩溃记录'),
                  onPressed: () async {
                    final text = MuseCrashRecorder.exportText(ref.read(sharedPreferencesProvider).requireValue);
                    if (text.isEmpty) return _toast('没有崩溃记录');
                    if (!context.mounted) return;
                    final ok = await museSaveTextFile(context, 'chuanyun-crashes.txt', text);
                    if (ok) _toast('已导出（已脱敏）');
                  },
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
