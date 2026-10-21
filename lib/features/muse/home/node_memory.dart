// 穿云 1.2.8 - 记住每个订阅上次选择的节点: a node the user picks is saved for the active
// subscription, and brought back once per connection when that subscription is connected again.
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Switches [groupTag] to [tag] and remembers it for the active subscription.
Future<void> museSelectNode(WidgetRef ref, String groupTag, String tag) =>
    _select(ref.read, groupTag, tag);

/// The same from a provider / notifier (the tray).
Future<void> museSelectNodeFrom(Ref ref, String groupTag, String tag) => _select(ref.read, groupTag, tag);

Future<void> _select(T Function<T>(ProviderListenable<T>) read, String groupTag, String tag) async {
  await read(proxiesOverviewNotifierProvider.notifier).changeProxy(groupTag, tag);
  final profileId = read(activeProfileProvider).valueOrNull?.id;
  if (profileId == null) return;
  final raw = read(Preferences.museLastNodes);
  await read(Preferences.museLastNodes.notifier).update(museRememberNode(raw, profileId, tag));
}

/// Brings the remembered node back once per connection (and after a subscription switch).
final museNodeMemoryProvider = Provider<void>((ref) {
  String? restoredFor;
  ref.listen<bool>(serviceRunningProvider, (_, running) {
    if (!running) restoredFor = null;
  });
  ref.listen(proxiesOverviewNotifierProvider, (_, next) async {
    final group = next.valueOrNull;
    if (group == null || !ref.read(serviceRunningProvider)) return;
    final profileId = ref.read(activeProfileProvider).valueOrNull?.id;
    if (profileId == null || restoredFor == profileId) return;
    restoredFor = profileId;
    final tag = museNodeToRestore(
      ref.read(Preferences.museLastNodes),
      profileId,
      selected: group.selected,
      tags: group.items.map((e) => e.tag),
    );
    if (tag == null) return;
    try {
      await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, tag);
    } catch (_) {
      // the list just stays on the core's own pick
    }
  });
});
