// 穿云 1.4.0 - keeps museCoreExtras in step with the preferences behind it.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/core_extras.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final museCoreExtrasProvider = Provider<Map<String, dynamic>>((ref) {
  final extras = <String, dynamic>{
    ...museTestExtras(workers: ref.watch(MusePrefs.testWorkers), timeoutSec: ref.watch(MusePrefs.testTimeoutSec)),
    // 1.4.0: custom hosts (设置 › 分流 › hosts), answered by the core's static DNS
    ...museHostsExtras(museParseHosts(ref.watch(MusePrefs.hosts))),
  };
  museCoreExtras = extras;
  return extras;
});
