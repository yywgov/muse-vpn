// 穿云 1.2.2 - 自动收起不可用节点: feeds the main group's url test results into
// MuseBadNodeTracker (lib/features/muse/logic/bad_nodes.dart) and publishes the folded tags for
// 首页's node list. Same code on Windows and Android.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/bad_nodes.dart';
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tags folded into 「不可用」 right now (empty when the option is off or not connected).
final museHiddenNodesProvider = StateProvider<Set<String>>((ref) => const {});

/// One tracker per profile: kept across reconnects, so a dead node does not come back to the
/// list every time the connection restarts.
final _museBadNodeTrackerProvider = Provider<MuseBadNodeTracker>((ref) {
  ref.watch(activeProfileProvider.select((p) => p.valueOrNull?.id));
  return MuseBadNodeTracker();
});

final museBadNodesProvider = Provider<void>((ref) {
  final tracker = ref.watch(_museBadNodeTrackerProvider);
  void publish(Set<String> tags) {
    Future.microtask(() {
      final current = ref.read(museHiddenNodesProvider);
      if (current.length != tags.length || !current.containsAll(tags)) {
        ref.read(museHiddenNodesProvider.notifier).state = tags;
      }
    });
  }

  if (!ref.watch(Preferences.hideBadNodes)) {
    tracker.reset();
    publish(const {});
    return;
  }
  if (!ref.watch(serviceRunningProvider)) {
    // keep what was learnt; the list is not shown while disconnected anyway
    return;
  }
  publish(tracker.hidden);
  ref.listen<AsyncValue<OutboundGroup?>>(proxiesOverviewNotifierProvider, (_, next) {
    final group = next.valueOrNull;
    if (group == null) return;
    final changed = tracker.update(
      selected: group.selected,
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
    if (changed) publish(tracker.hidden);
  }, fireImmediately: true);
});
