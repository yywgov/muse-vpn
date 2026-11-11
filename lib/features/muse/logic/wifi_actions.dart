// 穿云 1.20.3 第 2 轮 - Wi‑Fi 规则：每个 Wi‑Fi 选一个动作（暂停连接 / 切到规则模式 / 切到全局模式）。
// 存储沿用两份旧键（降级回旧版仍读得懂）：暂停连接 = muse_wifi_rules 里值为 "disconnect" 的条目（按需运行用），
// 切换模式 = muse_wifi_modes（按 Wi‑Fi 切换模式用）。新版保证同一个 Wi‑Fi 只在其中一份里；旧数据两边都有时，
// 按以前实际生效的行为合并一次：按需运行开着时暂停连接说了算（连上就断开），关着时暂停不生效、模式切换说了算。
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/desktop/wifi_mode.dart' show museParseWifiModes, museWifiModesToRaw;
import 'package:hiddify/features/muse/model/route_mode.dart';

enum MuseWifiAct {
  pause('pause', '暂停连接'),
  rule('rule', '切到规则模式'),
  global('global', '切到全局模式');

  const MuseWifiAct(this.key, this.title);

  final String key;
  final String title;

  /// 切换模式的动作对应的模式；暂停连接为 null。
  MuseRouteMode? get mode => switch (this) {
    pause => null,
    rule => MuseRouteMode.rule,
    global => MuseRouteMode.global,
  };

  static MuseWifiAct ofMode(MuseRouteMode m) => m == MuseRouteMode.global ? global : rule;
}

/// 两份旧名单合成「每个 Wi‑Fi 一个动作」。同一个 Wi‑Fi 两边都有时：[onDemandOn]（按需运行开着）→ 暂停连接；
/// 关着 → 切换模式（以前就是这样生效的）。顺序：先暂停名单，再模式名单里剩下的。
Map<String, MuseWifiAct> museWifiActions({required String rulesRaw, required String modesRaw, required bool onDemandOn}) {
  final pause = museOnDemandSsids(rulesRaw);
  final modes = museParseWifiModes(modesRaw);
  final out = <String, MuseWifiAct>{}; // insertion-ordered
  for (final s in pause) {
    final m = modes[s];
    out[s] = m != null && !onDemandOn ? MuseWifiAct.ofMode(m) : MuseWifiAct.pause;
  }
  for (final e in modes.entries) {
    out.putIfAbsent(e.key, () => MuseWifiAct.ofMode(e.value));
  }
  return out;
}

/// 两份旧名单里有同一个 Wi‑Fi（需要合并一次）。
bool museWifiActionsConflict({required String rulesRaw, required String modesRaw}) {
  final modes = museParseWifiModes(modesRaw);
  return museOnDemandSsids(rulesRaw).any(modes.containsKey);
}

/// 写回两份旧键：暂停连接 → muse_wifi_rules（保留里面其他类型的条目），切换模式 → muse_wifi_modes。两边不重复。
({String rulesRaw, String modesRaw}) museWifiActionsToRaw(Map<String, MuseWifiAct> acts, {required String rulesRaw}) => (
  rulesRaw: museOnDemandWithSsids(rulesRaw, [
    for (final e in acts.entries)
      if (e.value == MuseWifiAct.pause) e.key,
  ]),
  modesRaw: museWifiModesToRaw({
    for (final e in acts.entries)
      if (e.value.mode case final m?) e.key: m,
  }),
);

/// 「启动与断线」上 Wi‑Fi 规则一行的摘要（按需运行关着时暂停连接不算）。
String museWifiActionsSummary(Map<String, MuseWifiAct> acts, {required bool onDemandOn}) {
  final pause = acts.values.where((a) => a == MuseWifiAct.pause).length;
  final mode = acts.length - pause;
  final parts = [if (onDemandOn && pause > 0) '暂停 $pause 个', if (mode > 0) '切换模式 $mode 个'];
  return parts.isEmpty ? '关' : parts.join('，');
}
