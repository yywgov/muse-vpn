// 穿云 - shared bits for the Shadowrocket-style screens.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
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
String museProtocolLabel(String type, {bool isGroup = false}) {
  final t = type.toLowerCase();
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(4)),
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
