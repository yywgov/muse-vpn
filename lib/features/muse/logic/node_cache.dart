// 穿云 1.3.0 - the last node list of the active subscription, kept so 节点 and the 首页 node picker
// work while disconnected (pure part, unit-tested). Picking a node then only remembers it
// (Preferences.museLastNodes); node_memory switches to it once connected.
// Part of 穿云 (GPLv3).

import 'dart:convert';

class MuseCachedNode {
  const MuseCachedNode({required this.tag, required this.name, required this.type, this.isGroup = false});

  final String tag;
  final String name;
  final String type;
  final bool isGroup;
}

class MuseNodeCache {
  const MuseNodeCache({required this.profileId, required this.groupTag, required this.selected, required this.nodes});

  final String profileId;
  final String groupTag;
  final String selected;
  final List<MuseCachedNode> nodes;

  static const empty = MuseNodeCache(profileId: '', groupTag: '', selected: '', nodes: []);

  bool get isEmpty => nodes.isEmpty;

  String toRaw() => jsonEncode(toMap());

  Map<String, dynamic> toMap() => {
    'p': profileId,
    'g': groupTag,
    's': selected,
    'n': [
      for (final n in nodes) [n.tag, n.name == n.tag ? '' : n.name, n.type, if (n.isGroup) 1],
    ],
  };

  static MuseNodeCache parse(String raw) {
    if (raw.trim().isEmpty) return empty;
    try {
      return fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return empty;
    }
  }

  static MuseNodeCache fromMap(Map<String, dynamic> m) {
    try {
      final nodes = <MuseCachedNode>[];
      for (final e in (m['n'] as List? ?? const [])) {
        final l = e as List;
        if (l.length < 3) continue;
        final tag = '${l[0]}';
        final name = '${l[1]}';
        nodes.add(MuseCachedNode(tag: tag, name: name.isEmpty ? tag : name, type: '${l[2]}', isGroup: l.length > 3));
      }
      return MuseNodeCache(profileId: '${m['p'] ?? ''}', groupTag: '${m['g'] ?? ''}', selected: '${m['s'] ?? ''}', nodes: nodes);
    } catch (_) {
      return empty;
    }
  }

  /// The cache for [profileId] only (another subscription's list is never shown).
  MuseNodeCache forProfile(String? profileId) => profileId != null && profileId == this.profileId ? this : empty;

  /// The node shown as current while disconnected: the remembered pick, else the last selected.
  String currentTag(String? remembered) =>
      remembered != null && nodes.any((n) => n.tag == remembered) ? remembered : selected;
}

/// 1.5.3: one cached list per subscription (newest first, at most [max]), so switching the
/// active subscription while disconnected shows that subscription's own nodes. Reads the
/// single-list format of 1.3.0–1.5.2 too.
class MuseNodeCaches {
  const MuseNodeCaches(this.items);

  static const max = 8;
  final List<MuseNodeCache> items;

  static MuseNodeCaches parse(String raw) {
    if (raw.trim().isEmpty) return const MuseNodeCaches([]);
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final list = m['c'];
      if (list is! List) {
        final one = MuseNodeCache.fromMap(m);
        return MuseNodeCaches([if (!one.isEmpty) one]);
      }
      return MuseNodeCaches([
        for (final e in list)
          if (e is Map<String, dynamic>) MuseNodeCache.fromMap(e),
      ].where((c) => !c.isEmpty && c.profileId.isNotEmpty).toList());
    } catch (_) {
      return const MuseNodeCaches([]);
    }
  }

  MuseNodeCache of(String? profileId) =>
      items.where((c) => profileId != null && c.profileId == profileId).firstOrNull ?? MuseNodeCache.empty;

  MuseNodeCaches put(MuseNodeCache cache) =>
      MuseNodeCaches([cache, ...items.where((c) => c.profileId != cache.profileId)].take(max).toList());

  String toRaw() => jsonEncode({
    'c': [for (final c in items) c.toMap()],
  });
}

/// 1.5.3: where the 节点 list comes from.
enum MuseNodeSource {
  /// the running core's groups (they belong to the active subscription)
  live,

  /// the saved list of the active subscription (disconnected)
  cache,

  /// connected, but the core still runs another subscription (being reloaded): its groups
  /// must not be shown, nor saved under the new subscription
  switching,
}

/// [coreProfileId] = the subscription the core was last started / reloaded with (null when
/// unknown, e.g. the app was reopened while the Android VPN kept running: trusted as live).
MuseNodeSource museNodeSource({required bool running, required String? activeProfileId, required String? coreProfileId}) {
  if (!running) return MuseNodeSource.cache;
  if (coreProfileId != null && activeProfileId != null && coreProfileId != activeProfileId) return MuseNodeSource.switching;
  return MuseNodeSource.live;
}
