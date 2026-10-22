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

  String toRaw() => jsonEncode({
    'p': profileId,
    'g': groupTag,
    's': selected,
    'n': [
      for (final n in nodes) [n.tag, n.name == n.tag ? '' : n.name, n.type, if (n.isGroup) 1],
    ],
  });

  static MuseNodeCache parse(String raw) {
    if (raw.trim().isEmpty) return empty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
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
