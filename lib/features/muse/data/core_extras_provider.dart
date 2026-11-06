// 穿云 1.4.0 - keeps museCoreExtras in step with the preferences behind it.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/quick_rules_provider.dart';
import 'package:hiddify/features/muse/logic/quick_rules.dart';
import 'package:hiddify/features/muse/logic/auto_region.dart';
import 'package:hiddify/features/muse/logic/core_extras.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final museCoreExtrasProvider = Provider<Map<String, dynamic>>((ref) {
  final extras = <String, dynamic>{
    ...museTestExtras(workers: ref.watch(MusePrefs.testWorkers), timeoutSec: ref.watch(MusePrefs.testTimeoutSec)),
    // 1.4.0: custom hosts (设置 › 分流 › hosts), answered by the core's static DNS
    ...museHostsExtras(museParseHosts(ref.watch(MusePrefs.hosts))),
    // 1.4.1: 指定节点 (设置 › 分流)
    ...museNodeRulesExtras([for (final r in museMergeNodeRules(museParseNodeRules(ref.watch(MusePrefs.nodeRules)), ref.watch(museTempNodeRulesProvider))) r.toJson()]),
    // 1.12.0: 自动最快只在一个地区里选（空 = 全部）
    ...museAutoFilterExtras(museAutoRegionFilter(ref.watch(MusePrefs.autoRegion))),
  };
  museCoreExtras = extras;
  return extras;
});
