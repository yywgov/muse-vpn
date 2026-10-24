// 穿云 1.3.0 - what 首页 / 节点 read, in one place: thin providers over the connection, stats,
// subscription and node list (so the screens can be rendered with fixed values in tests), the
// speed history behind the 网速 sparkline, and the cached node list that lets 节点 work while
// disconnected.
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/node_cache.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/features/muse/home/core_profile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The app version (null until known).
final museAppVersionProvider = Provider<String?>((ref) => ref.watch(appInfoProvider).valueOrNull?.version);

final museConnectionProvider = Provider<AsyncValue<ConnectionStatus>>((ref) => ref.watch(connectionNotifierProvider));

final museRunningProvider = Provider<bool>((ref) => ref.watch(serviceRunningProvider));

/// null while the profile list is still loading.
final museHasProfileProvider = Provider<bool?>((ref) => ref.watch(hasAnyProfileProvider).valueOrNull);

final museActiveProfileIdProvider = Provider<String?>((ref) => ref.watch(activeProfileProvider).valueOrNull?.id);

/// Traffic / expiry the active subscription reports (null for local configs or when it sends none).
final museSubInfoProvider = Provider<SubscriptionInfo?>((ref) {
  final profile = ref.watch(activeProfileProvider).valueOrNull;
  return profile is RemoteProfileEntity ? profile.subInfo : null;
});

final museStatsProvider = Provider<SystemInfo>(
  (ref) => ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create(),
);

/// Last 30 download speed samples (bytes/s) of this connection, for the 网速 sparkline.
class MuseSpeedHistory extends Notifier<List<int>> {
  static const length = 30;

  @override
  List<int> build() {
    ref.listen<bool>(museRunningProvider, (_, running) {
      if (!running) state = const [];
    });
    ref.listen<SystemInfo>(museStatsProvider, (_, s) {
      if (!ref.read(museRunningProvider)) return;
      final next = [...state, s.downlink.toInt()];
      state = next.length > length ? next.sublist(next.length - length) : next;
    });
    return const [];
  }
}

final museSpeedHistoryProvider = NotifierProvider<MuseSpeedHistory, List<int>>(MuseSpeedHistory.new);

/// The main node group: live while connected, the cached list of the active subscription
/// otherwise (no delays then; picking only remembers the node). 1.5.3: while the core is still
/// being reloaded with a newly picked subscription, the old core's groups are never shown.
final museNodeGroupProvider = Provider<AsyncValue<OutboundGroup?>>((ref) {
  final running = ref.watch(museRunningProvider);
  final profileId = ref.watch(museActiveProfileIdProvider);
  final source = museNodeSource(running: running, activeProfileId: profileId, coreProfileId: ref.watch(museCoreProfileIdProvider));
  if (source == MuseNodeSource.live) return ref.watch(proxiesOverviewNotifierProvider);
  final cache = MuseNodeCaches.parse(ref.watch(Preferences.museNodeCache)).of(profileId);
  if (cache.isEmpty || profileId == null) return source == MuseNodeSource.switching ? const AsyncLoading() : const AsyncData(null);
  final remembered = museParseLastNodes(ref.watch(Preferences.museLastNodes))[profileId];
  return AsyncData(museGroupFromCache(cache, remembered: remembered));
});

/// 1.5.3: the active subscription's name (节点 header).
final museActiveProfileNameProvider = Provider<String?>((ref) => ref.watch(activeProfileProvider).valueOrNull?.name);

OutboundGroup museGroupFromCache(MuseNodeCache cache, {String? remembered}) => OutboundGroup(
  tag: cache.groupTag,
  type: 'selector',
  selected: cache.currentTag(remembered),
  selectable: true,
  items: [
    for (final n in cache.nodes) OutboundInfo(tag: n.tag, tagDisplay: n.name, type: n.type, isGroup: n.isGroup),
  ],
);

/// Saves the main group's node list (names and types, no delays) whenever it changes, so it can
/// be shown and picked from while disconnected. 1.5.3: one list per subscription, and only when
/// the running core belongs to the active subscription (switching used to file the old
/// subscription's nodes under the new one).
final museNodeCacheWriterProvider = Provider<void>((ref) {
  String? last;
  ref.listen<AsyncValue<OutboundGroup?>>(proxiesOverviewNotifierProvider, (_, next) {
    final group = next.valueOrNull;
    final profileId = ref.read(museActiveProfileIdProvider);
    if (group == null || group.items.isEmpty || profileId == null || !ref.read(serviceRunningProvider)) return;
    final source = museNodeSource(running: true, activeProfileId: profileId, coreProfileId: ref.read(museCoreProfileIdProvider));
    if (source != MuseNodeSource.live) return;
    final cache = MuseNodeCache(
      profileId: profileId,
      groupTag: group.tag,
      selected: group.selected,
      nodes: [
        for (final e in group.items)
          MuseCachedNode(
            tag: e.tag,
            name: e.tagDisplay.isNotEmpty ? e.tagDisplay : e.tag,
            type: e.type,
            isGroup: e.isGroup,
          ),
      ],
    );
    final one = cache.toRaw();
    if (one == last) return;
    last = one;
    final cur = ref.read(Preferences.museNodeCache);
    final raw = MuseNodeCaches.parse(cur).put(cache).toRaw();
    if (cur != raw) ref.read(Preferences.museNodeCache.notifier).update(raw);
  });
});

/// A clipboard subscription link not offered yet (badge on 添加, first row of the 添加 sheet).
final museClipboardOfferProvider = StateProvider<String?>((ref) => null);

/// 1.4.0: last delay per node of the active subscription (shown grey until a fresh result).
final museLatencyCacheProvider = Provider<MuseLatencyCache>((ref) {
  final id = ref.watch(museActiveProfileIdProvider);
  return MuseLatencyCache.parse(ref.watch(MusePrefs.latencyCache)).forProfile(id);
});

/// 1.4.0: saves fresh delays into the cache (at most every 5 s).
final museLatencyCacheWriterProvider = Provider<void>((ref) {
  var lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? pending;
  ref.onDispose(() => pending?.cancel());
  void write() {
    final group = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
    final profileId = ref.read(museActiveProfileIdProvider);
    if (group == null || profileId == null) return;
    final fresh = <String, MuseCachedDelay>{
      for (final e in group.items)
        if (!e.isGroup && e.urlTestDelay != 0 && e.hasUrlTestTime())
          e.tag: MuseCachedDelay(e.urlTestDelay, e.urlTestTime.toDateTime()),
    };
    if (fresh.isEmpty) return;
    final cur = MuseLatencyCache.parse(ref.read(MusePrefs.latencyCache));
    final next = cur.merge(profileId, fresh);
    if (identical(next, cur)) return;
    lastWrite = DateTime.now();
    ref.read(MusePrefs.latencyCache.notifier).update(next.toRaw());
    // 1.4.0: recent results per node (健康 / 丢包 / 抖动 in the node details): only results newer
    // than what the cache held count as a new sample
    final newer = <String, int>{
      for (final e in fresh.entries)
        if ((cur.forProfile(profileId).delays[e.key]?.at.millisecondsSinceEpoch ?? 0) ~/ 1000 !=
            e.value.at.millisecondsSinceEpoch ~/ 1000)
          e.key: e.value.delay,
    };
    if (newer.isNotEmpty) {
      final h = MuseDelayHistories.parse(ref.read(MusePrefs.delayHistory)).add(profileId, newer);
      ref.read(MusePrefs.delayHistory.notifier).update(h.toRaw());
    }
  }

  ref.listen<AsyncValue<OutboundGroup?>>(proxiesOverviewNotifierProvider, (_, next) {
    if (next.valueOrNull == null || !ref.read(serviceRunningProvider)) return;
    final wait = const Duration(seconds: 5) - DateTime.now().difference(lastWrite);
    pending?.cancel();
    pending = Timer(wait.isNegative ? Duration.zero : wait, write);
  });
});
