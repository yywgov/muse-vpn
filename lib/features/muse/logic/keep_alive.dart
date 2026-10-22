// 穿云 1.3.0 - 智能保持连接: one switch (Preferences.museKeepAlive, default on) for what used to be
// five separate layers (自动最快 after connect, node failover + timed-out node folding, core
// watchdog, Windows connection keeper / recovery). Pure part, unit-tested.
//
// One ordered strategy. Each problem starts at its own step and escalates down the list:
//   1. 重新连接       (reconnect)     — the connection dropped (Windows keeper: backoff 2/5/15/30/60 s)
//   2. 换到最佳节点   (switchNode)    — the picked node stops answering (failover to 自动最快,
//                                      back to the user's pick once it recovers; dead nodes fold
//                                      into 「不可用」)
//   3. 重启内核       (restartCore)   — the core itself stops answering
// A manual disconnect always wins: every step checks the user's intent (intentGeneration /
// startedByUser) before acting, and one recovery runs at a time.
// Part of 穿云 (GPLv3).

enum MuseKeepAliveStep {
  reconnect('重新连接'),
  switchNode('换到最佳节点'),
  restartCore('重启内核');

  const MuseKeepAliveStep(this.title);

  final String title;
}

/// The order steps are tried in.
const museKeepAliveOrder = [MuseKeepAliveStep.reconnect, MuseKeepAliveStep.switchNode, MuseKeepAliveStep.restartCore];

enum MuseKeepAliveProblem {
  /// the tunnel / core went away although the user wants to be connected
  connectionLost,

  /// connected, but the selected node fails its tests
  nodeUnreachable,

  /// the core no longer answers (crash / hang)
  coreUnresponsive,
}

/// The steps for [problem], in order: from the problem's first step to the end of the list.
List<MuseKeepAliveStep> museKeepAliveLadder(MuseKeepAliveProblem problem) {
  final first = switch (problem) {
    MuseKeepAliveProblem.connectionLost => MuseKeepAliveStep.reconnect,
    MuseKeepAliveProblem.nodeUnreachable => MuseKeepAliveStep.switchNode,
    MuseKeepAliveProblem.coreUnresponsive => MuseKeepAliveStep.restartCore,
  };
  return museKeepAliveOrder.sublist(museKeepAliveOrder.indexOf(first));
}

/// The step for the [attempt]-th try (0-based) at [problem]; the last step repeats.
/// null when the user disconnected by hand ([userStopped]) or keep-alive is off.
MuseKeepAliveStep? museKeepAliveStepFor(
  MuseKeepAliveProblem problem, {
  required int attempt,
  bool enabled = true,
  bool userStopped = false,
}) {
  if (!enabled || userStopped) return null;
  final ladder = museKeepAliveLadder(problem);
  return ladder[attempt.clamp(0, ladder.length - 1)];
}

/// One line for the single keep-alive log (data/disconnect.log, 导出诊断).
String museKeepAliveLogLine(MuseKeepAliveStep step, String detail) => '智能保持连接 · ${step.title}：$detail';
