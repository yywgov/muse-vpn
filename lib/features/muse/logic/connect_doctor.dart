// 穿云 1.13.0 - 连不上一键诊断 (pure part, unit-tested). Runs only when the user taps 「开始诊断」:
// 网络 → DNS → 节点可达 → 端口占用 (17079 后台内核、本地代理端口) → 其他 VPN, then one conclusion in plain
// Chinese and at most three fixes (释放内核、打开 VPN 设置、切换节点、重新检测).
// Part of 穿云 (GPLv3).

import 'dart:convert';

import 'package:hiddify/features/muse/logic/diagnosis.dart';

/// What the checks found. A null means the check could not run (shown as skipped).
class MuseDoctorInput {
  const MuseDoctorInput({
    required this.connected,
    required this.networkOk,
    required this.dnsOk,
    this.nodeName = '',
    this.nodeReachable,
    this.nodeUdp = false,
    this.corePortBusy = false,
    this.mixedPort = 0,
    this.mixedPortBusy = false,
    this.otherVpn,
  });

  final bool connected;
  final bool networkOk;
  final bool dnsOk;
  final String nodeName;

  /// TCP connect to the node's server:port (null = address unknown)
  final bool? nodeReachable;

  /// the node runs over UDP (QUIC: Hysteria2 / TUIC): a TCP check says nothing
  final bool nodeUdp;

  /// 17079 still open while 穿云 is disconnected: a background core that did not exit
  final bool corePortBusy;
  final int mixedPort;
  final bool mixedPortBusy;

  /// another app's VPN is up (null = unknown, e.g. desktop)
  final bool? otherVpn;
}

enum MuseDoctorFix {
  releaseCore('释放内核'),
  openVpnSettings('打开 VPN 设置'),
  switchNode('切换节点'),
  retest('重新检测');

  const MuseDoctorFix(this.title);

  final String title;
}

const museCorePort = 17079;

List<MuseDiagItem> museDoctorItems(MuseDoctorInput i) {
  final who = i.nodeName.isEmpty ? '当前节点' : '「${i.nodeName}」';
  return [
    i.networkOk
        ? const MuseDiagItem('网络', MuseDiagLevel.ok, '本机网络正常')
        : const MuseDiagItem('网络', MuseDiagLevel.fail, '本机网络不通，请先检查 Wi-Fi 或数据网络'),
    i.dnsOk
        ? const MuseDiagItem('DNS', MuseDiagLevel.ok, '域名解析正常')
        : const MuseDiagItem('DNS', MuseDiagLevel.fail, '域名解析失败，可能是路由器或运营商的 DNS 有问题'),
    if (i.nodeUdp)
      MuseDiagItem('节点', MuseDiagLevel.skip, '$who 使用 UDP（QUIC）传输，这一项无法检测')
    else
      switch (i.nodeReachable) {
        true => MuseDiagItem('节点', MuseDiagLevel.ok, '$who 的服务器可以连通'),
        false => MuseDiagItem('节点', MuseDiagLevel.fail, '$who 的服务器没有响应，建议切换节点'),
        null => const MuseDiagItem('节点', MuseDiagLevel.skip, '没有找到当前节点的地址'),
      },
    if (i.connected)
      const MuseDiagItem('端口', MuseDiagLevel.skip, '已连接，跳过端口检查')
    else if (i.corePortBusy)
      const MuseDiagItem('端口', MuseDiagLevel.fail, '后台内核还占着 $museCorePort 端口（上次没有完全退出）')
    else if (i.mixedPortBusy)
      MuseDiagItem('端口', MuseDiagLevel.fail, '本地代理端口 ${i.mixedPort} 被其他程序占用')
    else
      MuseDiagItem('端口', MuseDiagLevel.ok, i.mixedPort > 0 ? '端口 $museCorePort、${i.mixedPort} 空闲' : '端口 $museCorePort 空闲'),
    if (i.connected)
      const MuseDiagItem('其他 VPN', MuseDiagLevel.skip, '已连接，跳过')
    else
      switch (i.otherVpn) {
        true => const MuseDiagItem('其他 VPN', MuseDiagLevel.fail, '有其他 VPN 应用正在运行，会挡住穿云'),
        false => const MuseDiagItem('其他 VPN', MuseDiagLevel.ok, '没有其他 VPN 在运行'),
        null => const MuseDiagItem('其他 VPN', MuseDiagLevel.skip, '无法检测'),
      },
  ];
}

/// One sentence: the most likely reason, most basic first.
String museDoctorConclusion(MuseDoctorInput i) {
  if (!i.networkOk) return '本机没有网络，先检查 Wi-Fi 或数据网络，网络恢复后再连接';
  if (!i.connected && i.otherVpn == true) return '有其他 VPN 应用占用着 VPN，先在系统 VPN 设置里断开它，再连接穿云';
  if (!i.connected && i.corePortBusy) return '上次的后台内核没有退出，点「释放内核」后再连接';
  if (!i.connected && i.mixedPortBusy) return '本地代理端口 ${i.mixedPort} 被其他程序占用，关闭那个程序或在设置里换一个端口';
  if (!i.dnsOk) return '域名解析失败，可能是路由器或运营商的 DNS 有问题，可以换个网络试试';
  if (i.nodeReachable == false && !i.nodeUdp) return '当前节点的服务器没有响应，换一个节点试试';
  return '没有发现明显问题，可以重新连接；仍连不上请切换节点或更新订阅';
}

/// The buttons under the conclusion (at most three, 重新检测 always last).
List<MuseDoctorFix> museDoctorFixes(MuseDoctorInput i, {required bool android}) {
  final out = <MuseDoctorFix>[];
  if (i.networkOk) {
    if (!i.connected && i.corePortBusy && android) out.add(MuseDoctorFix.releaseCore);
    if (!i.connected && i.otherVpn == true && android) out.add(MuseDoctorFix.openVpnSettings);
    if (i.nodeReachable == false && !i.nodeUdp) out.add(MuseDoctorFix.switchNode);
  }
  return [...out.take(2), MuseDoctorFix.retest];
}

/// The node's server and port in the saved config (sing-box JSON), or null.
({String host, int port, bool udp})? museNodeEndpoint(String raw, String tag) {
  if (raw.isEmpty || tag.isEmpty) return null;
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    final all = [...((j['outbounds'] as List?) ?? const []), ...((j['endpoints'] as List?) ?? const [])].whereType<Map>();
    final o = all.where((e) => e['tag'] == tag).firstOrNull;
    if (o == null) return null;
    final host = '${o['server'] ?? ''}';
    final port = (o['server_port'] as num?)?.toInt() ?? 0;
    if (host.isEmpty || port <= 0) return null;
    final type = '${o['type'] ?? ''}'.toLowerCase();
    return (host: host, port: port, udp: type == 'hysteria2' || type == 'hysteria' || type == 'tuic');
  } catch (_) {
    return null;
  }
}
