// 穿云 - 自动最快 right after connecting: test every node at once so the fastest one is picked
// within seconds (the core re-tests cached results too, takes the median of several probes and
// keeps its pick unless another node is clearly faster).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tags the core gives its built-in groups.
const museAutoFastestTag = 'lowest';
const museLoadBalanceTag = 'balance';

final museAutoFastestProvider = Provider<void>((ref) {
  if (!ref.watch(serviceRunningProvider)) return;
  var done = false;
  ref.listen<AsyncValue<OutboundGroup?>>(proxiesOverviewNotifierProvider, (_, next) async {
    final group = next.valueOrNull;
    if (done || group == null || group.items.isEmpty) return;
    done = true;
    final notifier = ref.read(proxiesOverviewNotifierProvider.notifier);
    if (!ref.read(Preferences.autoFastestMigrated)) {
      await ref.read(Preferences.autoFastestMigrated.notifier).update(true);
      final hasAuto = group.items.any((e) => e.tag == museAutoFastestTag);
      if (group.selectable && group.selected == museLoadBalanceTag && hasAuto) {
        try {
          await notifier.changeProxy(group.tag, museAutoFastestTag);
        } catch (_) {
          // the notifier logs it
        }
      }
    }
    try {
      await notifier.urlTest(group.tag);
    } catch (_) {
      // the notifier logs it; the core's own cycle tests the nodes anyway
    }
  }, fireImmediately: true);
});
