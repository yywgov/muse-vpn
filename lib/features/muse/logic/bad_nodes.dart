// 穿云 1.2.2 - 自动收起不可用节点 (pure logic, unit-tested).
//
// A node that fails [hideAfter] fresh url tests in a row (timeout / error) is moved out of the
// node list into a folded 「不可用」 section; the core keeps testing it, and after [restoreAfter]
// fresh successful tests in a row it comes back. Nothing is deleted from the profile.
// - groups (自动最快, 负载均衡 …) are never hidden,
// - the node that is selected right now is never hidden (节点失效自动切换 handles that one),
// - at least one node always stays visible: when every node fails, nothing is hidden.
// Shared Dart code, so the same behaviour on Windows and Android.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/logic/failover_tracker.dart';

class MuseBadNodeTracker {
  // 1.2.4: a node shown as 超时 goes to 「不可用」 at once and comes back on its first good test
  // (the core already reports 超时 only after two lost probes in a row)
  MuseBadNodeTracker({this.hideAfter = 1, this.restoreAfter = 1});

  final int hideAfter;
  final int restoreAfter;

  final Map<String, int> _fails = {};
  final Map<String, int> _oks = {};
  final Map<String, int> _seen = {};
  final Set<String> _hidden = {};

  /// Tags currently folded away.
  Set<String> get hidden => Set.unmodifiable(_hidden);

  void reset() {
    _fails.clear();
    _oks.clear();
    _seen.clear();
    _hidden.clear();
  }

  bool _fresh(MuseNodeSample s) {
    if (s.testedAt == 0 || s.delay == 0) return false;
    if (_seen[s.tag] == s.testedAt) return false;
    _seen[s.tag] = s.testedAt;
    return true;
  }

  /// Feed the main group's latest state. Returns true when [hidden] changed.
  bool update({required String selected, required List<MuseNodeSample> items}) {
    final before = Set<String>.of(_hidden);
    final nodes = items.where((e) => !e.isGroup).toList();
    final present = {for (final n in nodes) n.tag};
    // nodes that left the profile are forgotten
    _hidden.removeWhere((t) => !present.contains(t));
    _fails.removeWhere((t, _) => !present.contains(t));
    _oks.removeWhere((t, _) => !present.contains(t));
    _seen.removeWhere((t, _) => !present.contains(t));

    for (final n in nodes) {
      if (!_fresh(n)) continue;
      if (MuseFailoverTracker.isValid(n.delay)) {
        _fails[n.tag] = 0;
        _oks[n.tag] = (_oks[n.tag] ?? 0) + 1;
        if (_hidden.contains(n.tag) && _oks[n.tag]! >= restoreAfter) _hidden.remove(n.tag);
      } else {
        _oks[n.tag] = 0;
        _fails[n.tag] = (_fails[n.tag] ?? 0) + 1;
        if (_fails[n.tag]! >= hideAfter) _hidden.add(n.tag);
      }
    }

    // the selected node stays in the list
    _hidden.remove(selected);
    // never fold away every node: with nothing working, show them all
    if (nodes.isNotEmpty && nodes.every((n) => _hidden.contains(n.tag))) _hidden.clear();

    return before.length != _hidden.length || !before.containsAll(_hidden);
  }
}
