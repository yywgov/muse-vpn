// 穿云 1.2.8 - 一键诊断 (pure part, unit-tested): each check's result in plain Chinese.
// Part of 穿云 (GPLv3).

enum MuseDiagLevel { ok, warn, fail, skip }

class MuseDiagItem {
  const MuseDiagItem(this.title, this.level, this.text);

  final String title;
  final MuseDiagLevel level;
  final String text;
}

/// 网络: could the device reach a domestic site without the proxy?
MuseDiagItem museDiagNetwork({required bool directOk}) => directOk
    ? const MuseDiagItem('网络', MuseDiagLevel.ok, '本机网络正常')
    : const MuseDiagItem('网络', MuseDiagLevel.fail, '本机网络不通，请先检查 Wi-Fi 或数据网络');

/// DNS: does name resolution work?
MuseDiagItem museDiagDns({required bool domesticOk, required bool foreignOk}) {
  if (domesticOk && foreignOk) return const MuseDiagItem('DNS', MuseDiagLevel.ok, '域名解析正常');
  if (domesticOk) return const MuseDiagItem('DNS', MuseDiagLevel.warn, '国内域名能解析，国外域名解析失败（连上节点后通常会恢复）');
  return const MuseDiagItem('DNS', MuseDiagLevel.fail, '域名解析失败，可能是网络或路由器 DNS 有问题');
}

/// 节点: the current node's latest test ([delay] 0 = untested, ≥ 65535 = timeout).
MuseDiagItem museDiagNode({required bool connected, required int delay, String? name}) {
  if (!connected) return const MuseDiagItem('节点', MuseDiagLevel.skip, '未连接，连接后再诊断节点');
  final who = name == null || name.isEmpty ? '当前节点' : '「$name」';
  if (delay > 0 && delay < 65535) {
    return MuseDiagItem('节点', delay > 1000 ? MuseDiagLevel.warn : MuseDiagLevel.ok, delay > 1000 ? '$who 可用，但延迟较高（$delay ms）' : '$who 可用（$delay ms）');
  }
  if (delay == 0) return MuseDiagItem('节点', MuseDiagLevel.warn, '$who 还没有测速结果');
  return MuseDiagItem('节点', MuseDiagLevel.fail, '$who 测速超时，建议换一个节点');
}

/// 系统代理 / VPN: is the traffic actually handed to 穿云?
/// [systemProxyOurs] null = not applicable (Android / TUN) or unreadable.
MuseDiagItem museDiagRouting({required bool connected, required bool android, required bool tun, bool? systemProxyOurs}) {
  const title = '系统代理 / VPN';
  if (!connected) return const MuseDiagItem(title, MuseDiagLevel.skip, '未连接');
  if (android) return const MuseDiagItem(title, MuseDiagLevel.ok, 'VPN 已开启');
  if (tun) return const MuseDiagItem(title, MuseDiagLevel.ok, 'TUN 模式已开启');
  return switch (systemProxyOurs) {
    true => const MuseDiagItem(title, MuseDiagLevel.ok, '系统代理已指向穿云'),
    false => const MuseDiagItem(title, MuseDiagLevel.fail, '系统代理被其他软件改掉了，请断开后重新连接'),
    null => const MuseDiagItem(title, MuseDiagLevel.warn, '无法读取系统代理设置'),
  };
}

/// 外网: generate_204 through 穿云.
MuseDiagItem museDiagInternet({required bool connected, required bool ok}) {
  if (!connected) return const MuseDiagItem('外网', MuseDiagLevel.skip, '未连接');
  return ok
      ? const MuseDiagItem('外网', MuseDiagLevel.ok, '可以正常访问外网')
      : const MuseDiagItem('外网', MuseDiagLevel.fail, '已连接但无法访问外网，建议换节点');
}

/// One-line conclusion for the whole run.
String museDiagConclusion(List<MuseDiagItem> items) {
  final failed = items.where((e) => e.level == MuseDiagLevel.fail).toList();
  if (failed.isNotEmpty) return '发现问题：${failed.first.text}';
  if (items.any((e) => e.level == MuseDiagLevel.warn)) return '基本正常，有需要留意的地方';
  return '一切正常';
}
