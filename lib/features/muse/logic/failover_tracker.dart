// 穿云 1.2 - 节点失效自动切换 (pure logic, unit-tested).
// A node the user picked by hand that fails [failThreshold] fresh url tests in a row is swapped
// for 自动最快; once it passes [recoverThreshold] fresh tests in a row the user's pick comes back.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

class MuseNodeSample {
  const MuseNodeSample({required this.tag, required this.delay, required this.testedAt, this.isGroup = false});

  final String tag;

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

  /// the node the user picked, while 自动最快 stands in for it
  String? failedFrom;
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
      if (current == null || current.isGroup || autoTag == null) {
        _fails = 0;
        return null;
      }
      if (_fresh(current)) {
        _fails = isValid(current.delay) ? 0 : _fails + 1;
      }
      if (_fails >= failThreshold) {
        _fails = 0;
        _oks = 0;
        failedFrom = selected;
        return autoTag;
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
    if (selected != autoTag) {
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
    _fails = 0;
    _oks = 0;
  }

  void reset() {
    _clear();
    _seen.clear();
  }
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
