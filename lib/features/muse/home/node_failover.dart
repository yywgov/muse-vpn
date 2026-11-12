// 穿云 - 节点失效自动切换: when the hand-picked node of the main group keeps failing the url test,
// switch the group to a stand-in, and back to the user's pick once it recovers.
// 1.11.0: its own switch (节点 › ⋯ › 节点设置 › 节点失效自动切换, on by default; was part of 智能保持连接);
// the stand-in is the fastest working node of the same region (else 自动最快, else the fastest
// node), and a toast says what happened. Event driven: it only reads test results as they arrive
// (no timer, no extra tests). Logic: lib/features/muse/logic/failover_tracker.dart.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';

import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart' show museFlushDnsAfterSwitch;
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
import 'package:hiddify/features/muse/logic/keep_alive.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
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
  // 1.3.0: step 2 of 智能保持连接 (logic/keep_alive.dart); 1.11.0: its own switch
  if (!ref.watch(MusePrefs.autoFailover) || !ref.watch(serviceRunningProvider)) {
    Future.microtask(() => ref.read(museFailoverFromProvider.notifier).state = null);
    return;
  }
  final tracker = MuseFailoverTracker();
  var switching = false;
  ref.listen<AsyncValue<OutboundGroup?>>(proxiesOverviewNotifierProvider, (_, next) async {
    final group = next.valueOrNull;
    if (group == null || switching || !group.selectable) return;
    final metas = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
    final items = museFailoverSamples(group, metas);
    final target = tracker.update(selected: group.selected, autoTag: museAutoGroupTag(group), items: items);
    if (ref.read(museFailoverFromProvider) != tracker.failedFrom) {
      ref.read(museFailoverFromProvider.notifier).state = tracker.failedFrom;
    }
    if (target == null) return;
    // the user may have disconnected meanwhile: never act for them then
    if (!ref.read(Preferences.startedByUser) || !ref.read(serviceRunningProvider)) return;
    ChuanyunPlatform.recordDisconnect(
      museKeepAliveLogLine(
        MuseKeepAliveStep.switchNode,
        tracker.failedFrom != null ? '所选节点连续测速失败，暂时换到自动最快' : '所选节点已恢复，换回',
      ),
    );
    switching = true;
    try {
      await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, target);
      // 1.20.4: names resolved through the failing node are looked up again through the stand-in
      unawaited(museFlushDnsAfterSwitch(ref.read));
      String nameOf(String tag) {
        final e = group.items.where((i) => i.tag == tag).firstOrNull;
        return e == null ? tag : (e.tagDisplay.isNotEmpty ? e.tagDisplay : e.tag);
      }

      try {
        ref.read(inAppNotificationControllerProvider).showInfoToast(
          museFailoverToast(
            from: nameOf(tracker.failedFrom ?? group.selected),
            to: nameOf(target),
            back: tracker.failedFrom == null,
          ),
        );
      } catch (_) {}
    } catch (_) {
      // the notifier logs it; the next result tries again
    } finally {
      switching = false;
      ref.read(museFailoverFromProvider.notifier).state = tracker.failedFrom;
    }
  }, fireImmediately: true);
});

/// 1.11.0: the main group's state for the tracker, with each node's region (set by hand, else from
/// its name).
List<MuseNodeSample> museFailoverSamples(OutboundGroup group, MuseNodeMetas metas) => [
  for (final e in group.items)
    MuseNodeSample(
      tag: e.tag,
      delay: e.urlTestDelay,
      testedAt: e.hasUrlTestTime() ? e.urlTestTime.toDateTime().millisecondsSinceEpoch : 0,
      isGroup: e.isGroup,
      region: e.isGroup ? null : metas.regionOf(e.tag, museRegionCode(e.tagDisplay.isNotEmpty ? e.tagDisplay : e.tag)),
    ),
];

/// 1.11.0: the one-line message after a switch ([back] = the user's pick came back).
String museFailoverToast({required String from, required String to, required bool back}) =>
    back ? '「$to」已恢复，已换回' : '「$from」连续测速失败，已自动切换到「$to」';
