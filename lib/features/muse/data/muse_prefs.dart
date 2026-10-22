// 穿云 1.4.0 - preferences added in 1.4 (one place, so sync / backup can list them).
// Conservative defaults: anything experimental or network-affecting starts off.
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';

abstract final class MusePrefs {
  // ---- 测速
  /// last delay per node of the active subscription (logic/latency_cache.dart)
  static final latencyCache = PreferencesNotifier.create<String, String>("muse_latency_cache", "");
  static final testWorkers = PreferencesNotifier.create<int, int>("muse_test_workers", museTestWorkersDefault);
  static final testTimeoutSec = PreferencesNotifier.create<int, int>("muse_test_timeout_sec", museTestTimeoutDefault);
}
