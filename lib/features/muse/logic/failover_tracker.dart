// 穿云 1.2 - 节点失效自动切换 (pure logic, unit-tested).
// A node the user picked by hand that fails [failThreshold] fresh url tests in a row is swapped
// for a stand-in; once it passes [recoverThreshold] fresh tests in a row the user's pick comes back.
// 1.11.0: the stand-in is the fastest working node of the same region (by flag / region code),
// else 自动最快, else the fastest working node of the group ([museFailoverTarget]).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

class MuseNodeSample {
  const MuseNodeSample({required this.tag, required this.delay, required this.testedAt, this.isGroup = false, this.region});

  final String tag;

  /// 1.11.0: ISO region code ('us', 'jp', …; null = unknown)
  final String? region;

  /// url test delay in ms; 0 = not tested yet, >= [MuseFailoverTracker.maxDelay] = timed out
  final int delay;

  /// when the delay was measured (any monotonic number: ms since epoch)
  final int testedAt;
  final bool isGroup;
}

class MuseFailoverTracker {
  MuseFailoverTracker({this.failThreshold = 2, this.recoverThreshold = 2});

  static const maxDelay = 65000;
  final int failThreshold;
  final int recoverThreshold;

  /// the node the user picked, while [standIn] stands in for it
  String? failedFrom;

  /// 1.11.0: what was switched to (a node of the same region, 自动最快 or the fastest node)
  String? standIn;
  int _fails = 0;
  int _oks = 0;
  final Map<String, int> _seen = {};

  bool get active => failedFrom != null;

  static bool isValid(int delay) => delay > 0 && delay < maxDelay;

  bool _fresh(MuseNodeSample s) {
    if (s.testedAt == 0 || s.delay == 0) return false;
    if (_seen[s.tag] == s.testedAt) return false;
    _seen[s.tag] = s.testedAt;
    return true;
  }

  /// Feed the main group's latest state; returns the tag to select, or null to leave it.
  String? update({required String selected, required List<MuseNodeSample> items, required String? autoTag}) {
    MuseNodeSample? find(String? tag) => tag == null ? null : items.where((e) => e.tag == tag).firstOrNull;
    final from = failedFrom;
    if (from == null) {
      final current = find(selected);
      if (current == null || current.isGroup) {
        _fails = 0;
        return null;
      }
      if (_fresh(current)) {
        _fails = isValid(current.delay) ? 0 : _fails + 1;
      }
      if (_fails >= failThreshold) {
        final target = museFailoverTarget(failed: current, items: items, autoTag: autoTag);
        if (target == null) return null; // nothing works either: stay (the count keeps going)
        _fails = 0;
        _oks = 0;
        failedFrom = selected;
        standIn = target;
        return target;
      }
      return null;
    }
    // failover active
    if (selected == from) {
      // the user picked it again (or the group has not switched yet): stand down
      final s = find(from);
      if (s != null && isValid(s.delay)) _clear();
      return null;
    }
    if (selected != standIn) {
      // the user chose something else meanwhile
      _clear();
      return null;
    }
    final original = find(from);
    if (original == null) {
      _clear();
      return null;
    }
    if (_fresh(original)) {
      _oks = isValid(original.delay) ? _oks + 1 : 0;
    }
    if (_oks >= recoverThreshold) {
      _clear();
      return from;
    }
    return null;
  }

  void _clear() {
    failedFrom = null;
    standIn = null;
    _fails = 0;
    _oks = 0;
  }

  void reset() {
    _clear();
    _seen.clear();
  }
}

/// 1.11.0: where a failing [failed] node is switched to: the fastest node of its region that
/// passed its last test, else [autoTag] (自动最快), else the fastest working node; null = none.
String? museFailoverTarget({required MuseNodeSample failed, required List<MuseNodeSample> items, required String? autoTag}) {
  final working = [
    for (final e in items)
      if (!e.isGroup && e.tag != failed.tag && MuseFailoverTracker.isValid(e.delay)) e,
  ]..sort((a, b) => a.delay.compareTo(b.delay));
  final region = failed.region;
  if (region != null && region.isNotEmpty) {
    final same = working.where((e) => e.region == region).firstOrNull;
    if (same != null) return same.tag;
  }
  if (autoTag != null) return autoTag;
  return working.firstOrNull?.tag;
}

/// 穿云 1.2 - core watchdog (pure logic): [failThreshold] failed health pings in a row while
/// connected mean the core hung or died, and it gets restarted.
class MuseWatchdogCounter {
  MuseWatchdogCounter({this.failThreshold = 3});

  final int failThreshold;
  int _fails = 0;

  int get fails => _fails;

  /// Returns true when the core should be restarted now.
  bool record({required bool ok}) {
    if (ok) {
      _fails = 0;
      return false;
    }
    _fails++;
    if (_fails >= failThreshold) {
      _fails = 0;
      return true;
    }
    return false;
  }
}
