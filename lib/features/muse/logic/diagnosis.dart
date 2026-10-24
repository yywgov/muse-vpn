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

// ---------------------------------------------------------------- 1.4.1: 故障诊断向导

/// 时间: TLS and several protocols (VMess) fail when the clock is off.
MuseDiagItem museDiagClock(Duration? skew) {
  if (skew == null) return const MuseDiagItem('时间', MuseDiagLevel.skip, '无法核对时间');
  final s = skew.inSeconds.abs();
  if (s <= 60) return const MuseDiagItem('时间', MuseDiagLevel.ok, '系统时间准确');
  final mins = (s / 60).round();
  final level = s > 90 ? MuseDiagLevel.fail : MuseDiagLevel.warn;
  return MuseDiagItem('时间', level, '系统时间${skew.isNegative ? '慢' : '快'}了约 $mins 分钟，部分节点会连不上，请打开「自动设置时间」');
}

/// Windows 系统代理残留 (穿云 was closed abnormally and the setting still points at it).
MuseDiagItem museDiagStaleProxy({required bool stale, int? port}) => stale
    ? MuseDiagItem('系统代理', MuseDiagLevel.fail, '系统代理还指向 127.0.0.1:${port ?? ''}，但没有程序在监听，其他软件会上不了网')
    : const MuseDiagItem('系统代理', MuseDiagLevel.ok, '没有残留的系统代理');

/// What the wizard offers to do next.
enum MuseDiagAction {
  repairProxy('修复系统代理'),
  switchNode('换个节点'),
  testNodes('全部测速'),
  updateSubs('更新订阅'),
  reconnect('重新连接'),
  connect('连接'),
  fixClock('打开时间设置');

  const MuseDiagAction(this.title);

  final String title;
}

/// The fixes for what the checks found, most useful first (at most three).
List<MuseDiagAction> museDiagActions(List<MuseDiagItem> items, {required bool connected}) {
  MuseDiagLevel? level(String title) => items.where((e) => e.title == title).firstOrNull?.level;
  final out = <MuseDiagAction>[];
  if (level('系统代理') == MuseDiagLevel.fail && !connected) out.add(MuseDiagAction.repairProxy);
  if (level('时间') == MuseDiagLevel.fail) out.add(MuseDiagAction.fixClock);
  if (level('网络') == MuseDiagLevel.fail) return out; // the device itself is offline: nothing else helps
  if (!connected) {
    out.add(MuseDiagAction.connect);
    return out.take(3).toList();
  }
  final node = level('节点');
  final internet = level('外网');
  final routing = level('系统代理 / VPN');
  if (routing == MuseDiagLevel.fail) out.add(MuseDiagAction.reconnect);
  if (node == MuseDiagLevel.fail || internet == MuseDiagLevel.fail) {
    out.add(MuseDiagAction.switchNode);
    out.add(MuseDiagAction.testNodes);
    out.add(MuseDiagAction.updateSubs);
  } else if (node == MuseDiagLevel.warn) {
    out.add(MuseDiagAction.testNodes);
  }
  return out.toSet().take(3).toList();
}

/// 1.5.0 #233: a new GitHub issue with the version and system filled in; the redacted
/// diagnosis is on the clipboard for the user to paste (a long body would not fit in a link).
const museIssuesUrl = 'https://github.com/yywgov/muse-vpn/issues/new';

Uri museFeedbackIssueUri({required String version, required String system}) => Uri.parse(museIssuesUrl).replace(
  queryParameters: {
    'title': '[反馈] ',
    'body': '版本：$version\n系统：$system\n\n问题描述：\n\n复现步骤：\n\n诊断信息（已复制到剪贴板，已脱敏，请粘贴在下面）：\n',
  },
);
