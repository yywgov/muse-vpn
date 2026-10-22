// 穿云 - shared bits for the Shadowrocket-style screens.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

DateTime? _connectedSince;

/// When the current connection came up (null while not connected).
/// On Android the VPN service records the real start time natively, so the 首页 timer
/// survives backgrounding, engine re-creation and process restarts; elsewhere it counts
/// from the moment the app saw the tunnel up. A transient non-connected state (e.g. the
/// status stream re-subscribing on resume) does not reset it — only a real Disconnected.
final museConnectedSinceProvider = FutureProvider<DateTime?>((ref) async {
  final status = ref.watch(connectionNotifierProvider.select((s) => s.valueOrNull));
  if (status is Disconnected) {
    _connectedSince = null;
    return null;
  }
  if (status is! Connected) return _connectedSince; // loading / switching: keep what we had
  final millis = await ChuanyunPlatform.connectedSince();
  if (millis != null && millis > 0) {
    _connectedSince = DateTime.fromMillisecondsSinceEpoch(millis);
  }
  return _connectedSince ??= DateTime.now();
});

String museFormatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return '${two(h)}:${two(m)}:${two(s)}';
}

/// Short protocol label for a sing-box outbound type.
/// 1.2.9: the core reports a node whose config sing-box could not start as
/// `Invalid initialize outbound/vless[tag]: <reason>` in place of its type.
bool museIsInvalidNodeType(String type) => type.toLowerCase().startsWith('invalid');

/// The core's full error for an invalid node (without the "Invalid" prefix), for the detail sheet.
String museInvalidNodeError(String type) {
  final t = type.trim();
  if (!museIsInvalidNodeType(t)) return '';
  final rest = t.substring('invalid'.length).trim();
  return rest.isEmpty ? '未知错误' : rest;
}

/// Short Chinese reason for an invalid node, e.g. 「ECH 参数」.
String museInvalidNodeReason(String type) {
  final error = museInvalidNodeError(type);
  // the cause is after the last "]: " (the part before names the outbound and its tag)
  final idx = error.lastIndexOf(']: ');
  final e = (idx >= 0 ? error.substring(idx + 3) : error).toLowerCase();
  if (e.contains('ech')) return 'ECH 参数';
  if (e.contains('utls') || e.contains('fingerprint')) return '指纹 fp';
  if (e.contains('reality')) return 'Reality 参数';
  if (e.contains('xhttp') || e.contains('splithttp')) return 'XHTTP 传输';
  if (e.contains('not included in this build')) return '协议不受支持';
  if (e.contains('transport')) return '传输方式';
  if (e.contains('encryption')) return '加密方式';
  if (e.contains('packet encoding')) return '包编码';
  if (e.contains('flow')) return 'flow 参数';
  if (e.contains('uuid')) return 'UUID';
  if (e.contains('alpn')) return 'ALPN';
  if (e.contains('certificate') || e.contains('pem')) return '证书';
  if (e.contains('password') || e.contains('method') || e.contains('cipher')) return '密码或加密方式';
  if (e.contains('port')) return '端口';
  if (e.contains('server') || e.contains('address')) return '服务器地址';
  return '参数不受支持';
}

/// Node subtitle for an invalid node: 「节点配置不兼容：ECH 参数」.
String museInvalidNodeSubtitle(String type) => '节点配置不兼容：${museInvalidNodeReason(type)}';

String museProtocolLabel(String type, {bool isGroup = false}) {
  final t = type.toLowerCase();
  if (!isGroup && museIsInvalidNodeType(t)) return '不兼容';
  return switch (t) {
    'vless' => 'VLESS',
    'vmess' => 'VMess',
    'trojan' => 'Trojan',
    'shadowsocks' || 'ss' => 'SS',
    'shadowsocksr' || 'ssr' => 'SSR',
    'hysteria2' || 'hy2' => 'Hy2',
    'hysteria' => 'Hy',
    'tuic' => 'TUIC',
    'wireguard' => 'WG',
    'anytls' => 'AnyTLS',
    'shadowtls' => 'ShadowTLS',
    'ssh' => 'SSH',
    'socks' => 'SOCKS',
    'http' => 'HTTP',
    'direct' => '直连',
    'block' || 'reject' => '拦截',
    'fallback' => '故障切换',
    'urltest' || 'url-test' => '自动最快',
    'selector' || 'select' => '手动选择',
    'loadbalance' || 'load-balance' || 'balancer' || 'round-robin' => '负载均衡',
    _ when isGroup => '策略组',
    _ => type.isEmpty ? '?' : type.toUpperCase(),
  };
}

class MuseProtocolChip extends StatelessWidget {
  const MuseProtocolChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8, vertical: MuseSpace.s4),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: MuseRadius.smallAll),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Full protocol name for node subtitles.
String museProtocolName(String type, {bool isGroup = false}) {
  final t = type.toLowerCase();
  return switch (t) {
    'vless' => 'VLESS',
    'vmess' => 'VMess',
    'trojan' => 'Trojan',
    'shadowsocks' || 'ss' => 'Shadowsocks',
    'shadowsocksr' || 'ssr' => 'ShadowsocksR',
    'hysteria2' || 'hy2' => 'Hysteria2',
    'hysteria' => 'Hysteria',
    'tuic' => 'TUIC',
    'wireguard' => 'WireGuard',
    'anytls' => 'AnyTLS',
    'shadowtls' => 'ShadowTLS',
    _ => museProtocolLabel(type, isGroup: isGroup),
  };
}
