// 穿云 - 节点失效自动切换: when the hand-picked node of the main group keeps failing the url test,
// switch the group to its 自动最快 member, and back to the user's pick once it recovers.
// Shown as an icon on 首页, no text. Logic: lib/features/muse/logic/failover_tracker.dart.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The node 自动最快 currently stands in for (null = no failover active).
final museFailoverFromProvider = StateProvider<String?>((ref) => null);

String? museAutoGroupTag(OutboundGroup group) => group.items
    .where((e) => e.isGroup && const {'urltest', 'url-test', 'balancer'}.contains(e.type.toLowerCase()) && e.tag == 'lowest')
    .map((e) => e.tag)
    .followedBy(group.items
        .where((e) => e.isGroup && const {'urltest', 'url-test'}.contains(e.type.toLowerCase()))
        .map((e) => e.tag))
    .firstOrNull;

final museNodeFailoverProvider = Provider<void>((ref) {
  if (!ref.watch(Preferences.nodeFailover) || !ref.watch(serviceRunningProvider)) {
    Future.microtask(() => ref.read(museFailoverFromProvider.notifier).state = null);
    return;
  }
  final tracker = MuseFailoverTracker();
  var switching = false;
  ref.listen<AsyncValue<OutboundGroup?>>(proxiesOverviewNotifierProvider, (_, next) async {
    final group = next.valueOrNull;
    if (group == null || switching || !group.selectable) return;
    final target = tracker.update(
      selected: group.selected,
      autoTag: museAutoGroupTag(group),
      items: [
        for (final e in group.items)
          MuseNodeSample(
            tag: e.tag,
            delay: e.urlTestDelay,
            testedAt: e.hasUrlTestTime() ? e.urlTestTime.toDateTime().millisecondsSinceEpoch : 0,
            isGroup: e.isGroup,
          ),
      ],
    );
    if (ref.read(museFailoverFromProvider) != tracker.failedFrom) {
      ref.read(museFailoverFromProvider.notifier).state = tracker.failedFrom;
    }
    if (target == null) return;
    switching = true;
    try {
      await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, target);
    } catch (_) {
      // the notifier logs it; the next result tries again
    } finally {
      switching = false;
      ref.read(museFailoverFromProvider.notifier).state = tracker.failedFrom;
    }
  }, fireImmediately: true);
});
