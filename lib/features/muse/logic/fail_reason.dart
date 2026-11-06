// 穿云 1.12.0 - 节点失败原因：内核在测速结果里带出原因（refused / dns / handshake / timeout），
// 这里把它说成中文：卡片上一个短词，节点详情里一句原因 + 一条建议。拿不准的一律算「超时」。
// 只是显示，测速流程不变。
// Part of 穿云 (GPLv3).

enum MuseFailReason {
  refused('拒绝连接', '服务器拒绝连接', '节点端口没有在监听，或已被关闭、封锁。换一个节点，或请服务商检查端口。'),
  dns('解析失败', '域名解析失败', '找不到节点服务器的地址：域名可能已失效或被污染。检查订阅是否过期，或在 网络 › DNS 里换一个。'),
  handshake('握手失败', '握手失败', '连上了服务器但加密握手没成功（TLS / REALITY）。常见原因是设备时间不准、证书或 SNI 不对、指纹被识别。先打开「自动设置时间」，仍不行就换节点。'),
  timeout('超时', '超时', '服务器在规定时间内没有回应：线路拥堵、丢包或节点失效。稍后再测一次，或换个节点。');

  const MuseFailReason(this.word, this.title, this.advice);

  /// 卡片上的短词（不超过 4 个字）
  final String word;

  /// 节点详情里的原因
  final String title;

  /// 一条建议
  final String advice;

  /// 内核给的原因字段；空或不认识 = 超时（不猜测原因）
  static MuseFailReason parse(String? raw) => switch ((raw ?? '').trim().toLowerCase()) {
    'refused' => MuseFailReason.refused,
    'dns' => MuseFailReason.dns,
    'handshake' => MuseFailReason.handshake,
    _ => MuseFailReason.timeout,
  };
}
