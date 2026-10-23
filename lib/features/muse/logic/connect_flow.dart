// 穿云 1.5.0 - the connect button as a state machine, the connecting stages, a local config
// pre-check before the core starts, and core errors in plain words (pure logic, unit-tested).
// Part of 穿云 (GPLv3).

// ---------------------------------------------------------------- button state machine

/// What a tap on the connect switch does.
enum MuseConnectAction {
  /// disconnected (or failed): connect
  connect,

  /// connected: disconnect
  disconnect,

  /// still connecting (or the keeper is reconnecting): stop the attempt
  cancel,

  /// disconnecting: a second tap does nothing (the switch is disabled)
  ignore,
}

/// The core's state as the button sees it.
enum MuseLinkState { disconnected, connecting, connected, disconnecting }

/// 1.5.0: 连接中 can be cancelled, 断开中 ignores taps (it used to be the other way round: both
/// were ignored as "debounce", so a connect that hung could only be stopped by quitting).
MuseConnectAction museConnectActionFor(MuseLinkState state) => switch (state) {
  MuseLinkState.disconnected => MuseConnectAction.connect,
  MuseLinkState.connected => MuseConnectAction.disconnect,
  MuseLinkState.connecting => MuseConnectAction.cancel,
  MuseLinkState.disconnecting => MuseConnectAction.ignore,
};

// ---------------------------------------------------------------- stages

/// 1.5.0: what the hero card says while a connect is under way.
enum MuseConnectStage {
  preparing('准备配置'),
  starting('启动核心'),
  testing('测试连通');

  const MuseConnectStage(this.title);

  final String title;
}

/// The stage to show: [preparing] = the app is building / checking the config (the core has not
/// been asked yet, so the status is still 未连接); [reachChecking] = the first reachability probe after connecting is running.
/// Null = nothing to show (idle, connected and tested, disconnecting).
MuseConnectStage? museConnectStageFor(MuseLinkState state, {required bool preparing, required bool reachChecking}) {
  if (state == MuseLinkState.disconnecting) return null;
  if (state == MuseLinkState.connected) return reachChecking ? MuseConnectStage.testing : null;
  if (preparing) return MuseConnectStage.preparing;
  return state == MuseLinkState.connecting ? MuseConnectStage.starting : null;
}

// ---------------------------------------------------------------- pre-check

/// One problem found before starting the core: which setting and what is wrong with it.
class MuseConfigIssue {
  const MuseConfigIssue(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => '$field：$message';

  @override
  bool operator ==(Object other) => other is MuseConfigIssue && other.field == field && other.message == message;

  @override
  int get hashCode => Object.hash(field, message);
}

bool _validPort(int p) => p >= 1 && p <= 65535;

/// 1.5.0: checks only what is certain to stop the core from starting, so a config that would
/// have worked is never refused. Empty = fine.
///
/// [profileBytes] = size of the stored subscription config (null = file missing).
List<MuseConfigIssue> museConfigPrecheck({
  required int? profileBytes,
  required int mixedPort,
  required bool clashApi,
  required int clashApiPort,
  required bool tun,
  required int mtu,
  required String remoteDns,
  required String testUrl,
}) {
  final out = <MuseConfigIssue>[];
  if (profileBytes == null) {
    out.add(const MuseConfigIssue('订阅', '找不到这个订阅的配置文件，请更新订阅'));
  } else if (profileBytes == 0) {
    out.add(const MuseConfigIssue('订阅', '订阅内容是空的，请更新订阅'));
  }
  if (!_validPort(mixedPort)) out.add(MuseConfigIssue('代理端口', '$mixedPort 不是有效端口（1–65535）'));
  if (clashApi) {
    if (!_validPort(clashApiPort)) {
      out.add(MuseConfigIssue('控制端口', '$clashApiPort 不是有效端口（1–65535）'));
    } else if (clashApiPort == mixedPort) {
      out.add(MuseConfigIssue('控制端口', '和代理端口都是 $mixedPort，请改成不同的端口'));
    }
  }
  // sing-box refuses an MTU outside this range for the TUN device
  if (tun && (mtu < 576 || mtu > 65535)) out.add(MuseConfigIssue('MTU', '$mtu 超出范围（576–65535）'));
  if (remoteDns.trim().isEmpty) out.add(const MuseConfigIssue('远程 DNS', '地址为空'));
  final u = Uri.tryParse(testUrl.trim());
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
    out.add(MuseConfigIssue('测速地址', '「$testUrl」不是 http(s) 链接'));
  }
  return out;
}

// ---------------------------------------------------------------- errors in plain words

/// A core / network error explained: what happened and what to try.
class MuseFriendlyError {
  const MuseFriendlyError(this.title, this.hint);

  final String title;
  final String hint;
}

/// 1.5.0: the common connect errors in plain words; null when the text matches none of them
/// (the raw error is shown as it is). The raw text is always kept next to it for 复制.
MuseFriendlyError? museFriendlyError(String raw) {
  final e = raw.toLowerCase();
  bool has(List<String> words) => words.any(e.contains);
  // order matters: the clock is the cause of many certificate errors
  if (has(['certificate has expired or is not yet valid', 'not yet valid', 'clock', 'time is not synchronized'])) {
    return const MuseFriendlyError('系统时间不对', '设备时间和网络时间差太多，证书和加密握手会失败。请打开「自动设置时间」后再连接');
  }
  if (has(['x509', 'certificate', 'tls: bad certificate', 'unknown authority'])) {
    return const MuseFriendlyError('证书校验失败', '节点的证书和域名（SNI）对不上或已过期。可以换个节点，或请服务商检查证书');
  }
  if (has(['address already in use', 'only one usage of each socket address', 'bind:'])) {
    return const MuseFriendlyError('本地端口被占用', '另一个代理软件可能还在运行，占用了穿云的端口。请先退出它，或在设置里换一个端口');
  }
  if (has(['connection refused', 'actively refused'])) {
    return const MuseFriendlyError('服务器拒绝连接', '节点的端口没有在监听或已关闭。换一个节点试试，或检查订阅是否过期');
  }
  if (has(['connection reset', 'reset by peer', 'forcibly closed', 'eof'])) {
    return const MuseFriendlyError('连接被中途切断', '可能是 SNI 被识别并阻断，或节点已失效。换个节点、或开启 TLS 分片后再试');
  }
  if (has(['no such host', 'server misbehaving', 'lookup ', 'dns'])) {
    return const MuseFriendlyError('域名解析失败', '找不到节点服务器的地址。检查网络，或在设置 › 网络里换一个 DNS');
  }
  if (has(['i/o timeout', 'deadline exceeded', 'timeout', 'timed out'])) {
    return const MuseFriendlyError('连接超时', '服务器没有回应：网络不稳定、节点失效或被限速。换个节点或稍后再试');
  }
  if (has(['permission denied', 'access is denied', 'operation not permitted', 'denied'])) {
    return const MuseFriendlyError('没有权限', '系统拒绝了穿云的请求。请允许 VPN 权限，Windows 的 TUN 模式需要以管理员身份运行');
  }
  if (has(['network is unreachable', 'no route to host', 'host is down'])) {
    return const MuseFriendlyError('网络不可达', '设备当前没有可用网络，或到服务器的路由不通。检查 Wi‑Fi / 移动数据后再试');
  }
  return null;
}

/// [err] (an error dialog's title + text) with the plain-words explanation in front when one
/// matches; the original text stays below it as 「详细信息」.
({String type, String? message}) museFriendlyPresent(({String type, String? message}) err) {
  final raw = [err.type, ?err.message].join(' ');
  final f = museFriendlyError(raw);
  if (f == null) return err;
  final detail = (err.message ?? '').trim();
  return (type: f.title, message: detail.isEmpty ? f.hint : '${f.hint}\n\n详细信息：$detail');
}
