// 穿云 1.13.0 - 首页 hints about the app's own health, above the connect card. Each shows only when
// it applies and goes away when closed:
//   安全模式       2 failed starts in a row → widget updates and the user's own rules are off; 退出安全模式
//   被其他 VPN 断开  another VPN app took the VPN over (onRevoke); 穿云 does not reconnect by itself
//   上次异常       an uncaught error or a failed start was written to the local log; 复制日志 / 知道了
//   连接没有成功    the last connect failed → 设置 › 诊断（1.20.3；原一键诊断弹层，点了才查）
// Read when 首页 opens and when the connection status changes; no timer, no animation.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/crash_recorder.dart';
import 'package:hiddify/features/muse/data/muse_health.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/health_tools.dart';
import 'package:hiddify/features/muse/logic/redact.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart' show museDiagnosePath;
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseHealthBanner extends ConsumerWidget {
  const MuseHealthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(museHealthProvider).valueOrNull ?? MuseHealthState.none;
    final status = ref.watch(museConnectionProvider).valueOrNull;
    final failed = status is Disconnected && status.connectionFailure != null;
    final now = DateTime.now();
    final cards = <Widget>[
      if (h.safeMode)
        _Hint(
          key: const ValueKey('home_safe_mode'),
          icon: Icons.health_and_safety_outlined,
          color: MusePalette.orange,
          title: '安全模式',
          text: '连续 $museSafeModeAfter 次启动失败，已停用桌面小组件更新和自定义规则（分流规则、规则集、从连接加的规则、屏蔽域名、订阅修改），以最小配置连接。确认能正常连接后可退出。',
          actions: [
            ('退出安全模式', () async {
              await ref.read(museHealthProvider.notifier).exitSafeMode();
              _toast(ref, '已退出安全模式，下次连接恢复自定义规则');
            }),
          ],
        ),
      if (h.revokedAt != null)
        _Hint(
          key: const ValueKey('home_vpn_revoked'),
          icon: Icons.vpn_lock_outlined,
          color: MusePalette.orange,
          title: '已被其他 VPN 断开',
          text: '${museWhen(h.revokedAt!, now)}，另一个 VPN 应用开启后系统收回了穿云的 VPN。穿云不会自动重连，需要时再点「连接」。',
          actions: [
            ('知道了', () => ref.read(museHealthProvider.notifier).dismissRevoked()),
            if (status is Disconnected)
              ('重新连接', () async {
                await ref.read(museHealthProvider.notifier).dismissRevoked();
                await ref.read(connectionNotifierProvider.notifier).toggleConnection();
              }),
          ],
        ),
      if (h.crash != null)
        _Hint(
          key: const ValueKey('home_last_crash'),
          icon: Icons.report_outlined,
          color: MusePalette.red,
          title: '上次异常',
          text: '${h.crashAt == null ? '' : '${museWhen(h.crashAt!, now)}：'}${museRedact(h.crash!)}。详细记录只保存在本机。',
          actions: [
            ('复制日志', () => _copyLog(ref)),
            ('知道了', () => ref.read(museHealthProvider.notifier).dismissCrash()),
          ],
        ),
      if (failed && !h.safeMode)
        _Hint(
          key: const ValueKey('home_connect_failed'),
          icon: Icons.medical_services_outlined,
          color: MusePalette.red,
          title: '连接没有成功',
          text: '可以检查网络、DNS、节点、端口占用和其他 VPN，找出连不上的原因。',
          // 1.20.3：跳到 设置 › 诊断（没连上时页顶就是「连不上」流程）
          actions: [('诊断', () => GoRouter.of(context).go(museDiagnosePath))],
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: MuseSpace.s12),
      child: Column(children: [for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(height: MuseSpace.s8), c]]),
    );
  }

  static Future<void> _copyLog(WidgetRef ref) async {
    try {
      final info = ref.read(appInfoProvider).valueOrNull;
      final prefs = ref.read(sharedPreferencesProvider).requireValue;
      final text = museHealthLogText(
        version: info == null ? '未知版本' : '${info.version} (${info.buildNumber})',
        system: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        serviceLog: museRedact(await MuseHealth.serviceLog()),
        appLog: MuseCrashRecorder.exportText(prefs),
      );
      await Clipboard.setData(ClipboardData(text: text));
      _toast(ref, '日志已复制（已脱敏）');
    } catch (e) {
      _toast(ref, '复制失败：$e', error: true);
    }
  }

  static void _toast(WidgetRef ref, String text, {bool error = false}) {
    try {
      final n = ref.read(inAppNotificationControllerProvider);
      error ? n.showErrorToast(text) : n.showSuccessToast(text);
    } catch (_) {}
  }
}

class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.icon, required this.color, required this.title, required this.text, required this.actions});

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    return Material(
      color: MuseColors.card(context),
      borderRadius: BorderRadius.circular(MuseRadius.card),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s12, MuseSpace.s8, MuseSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: MuseIconSize.small),
                const SizedBox(width: MuseSpace.s8),
                Expanded(child: Text(title, style: MuseType.body(context).copyWith(fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: MuseSpace.s4),
            Padding(
              padding: const EdgeInsets.only(right: MuseSpace.s8),
              child: Text(text, style: MuseType.caption(context).copyWith(color: mt.text2)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                children: [for (final (label, onTap) in actions) TextButton(onPressed: onTap, child: Text(label))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
