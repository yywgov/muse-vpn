// 穿云 1.2.1 - one rule for latency colours everywhere (首页 node list, groups, any picker).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/core/model/constants.dart';

/// green < 300 ms, yellow 300–600 ms, red > 600 ms or timeout; unknown = not tested yet.
enum MuseLatencyLevel { good, fair, bad, unknown }

const museLatencyGoodBelowMs = 300;
const museLatencyFairUpToMs = 600;

/// [delay] in ms as the core reports it: 0 = not tested yet, >= [ConnectionConst.maxDelay]
/// (e.g. 65535) = timeout / failed.
MuseLatencyLevel museLatencyLevel(int delay) {
  if (delay == 0) return MuseLatencyLevel.unknown;
  if (!ConnectionConst.isValidDelay(delay)) return MuseLatencyLevel.bad;
  if (delay < museLatencyGoodBelowMs) return MuseLatencyLevel.good;
  if (delay <= museLatencyFairUpToMs) return MuseLatencyLevel.fair;
  return MuseLatencyLevel.bad;
}
