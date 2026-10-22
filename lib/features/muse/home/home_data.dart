// 穿云 1.3.0 - what 首页 / 节点 read, in one place: thin providers over the connection, stats,
// subscription and node list (so the screens can be rendered with fixed values in tests), the
// speed history behind the 网速 sparkline, and the cached node list that lets 节点 work while
// disconnected.
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/node_cache.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
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
/// otherwise (no delays then; picking only remembers the node).
final museNodeGroupProvider = Provider<AsyncValue<OutboundGroup?>>((ref) {
  if (ref.watch(museRunningProvider)) return ref.watch(proxiesOverviewNotifierProvider);
  final profileId = ref.watch(museActiveProfileIdProvider);
  final cache = MuseNodeCache.parse(ref.watch(Preferences.museNodeCache)).forProfile(profileId);
  if (cache.isEmpty || profileId == null) return const AsyncData(null);
  final remembered = museParseLastNodes(ref.watch(Preferences.museLastNodes))[profileId];
  return AsyncData(museGroupFromCache(cache, remembered: remembered));
});

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
/// be shown and picked from while disconnected.
final museNodeCacheWriterProvider = Provider<void>((ref) {
  String? last;
  ref.listen<AsyncValue<OutboundGroup?>>(proxiesOverviewNotifierProvider, (_, next) {
    final group = next.valueOrNull;
    final profileId = ref.read(museActiveProfileIdProvider);
    if (group == null || group.items.isEmpty || profileId == null || !ref.read(serviceRunningProvider)) return;
    final raw = MuseNodeCache(
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
    ).toRaw();
    if (raw == last) return;
    last = raw;
    if (ref.read(Preferences.museNodeCache) != raw) ref.read(Preferences.museNodeCache.notifier).update(raw);
  });
});

/// A clipboard subscription link not offered yet (badge on 添加, first row of the 添加 sheet).
final museClipboardOfferProvider = StateProvider<String?>((ref) => null);
