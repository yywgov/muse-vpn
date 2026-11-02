// 穿云 1.2.4: update download sources / ranges, 超时节点排到末尾 (was 不可用 after one timeout), bundled rule-sets.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/bundled_rule_sets.dart';
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';

void main() {
  test('download sources: own connection, mirrors (only when verified), github', () {
    const u = 'https://github.com/yywgov/muse-vpn/releases/download/v1.2.4/a.apk';
    final s = museDownloadSources(u, proxyPort: 12334);
    expect(s.first, (url: u, proxyPort: 12334));
    expect(s.map((e) => e.url).where((e) => e.startsWith('https://ghfast.top/')).length, 1);
    expect(s.last, (url: u, proxyPort: null));
    expect(museDownloadSources(u, mirrors: false), [(url: u, proxyPort: null)]);
  });

  test('byte ranges cover the file exactly', () {
    final r = museByteRanges(10, 4);
    expect(r, [(0, 2), (3, 5), (6, 8), (9, 9)]);
    expect(museByteRanges(0, 4), isEmpty);
    expect(museByteRanges(45895392, 4).last.$2, 45895391);
  });

  test('a node shown as 超时 goes to the end at once and is back in place on its first good test (1.10.0)', () {
    List<String> order(List<MuseNodeSample> items) => museTimeoutsLast<MuseNodeSample>(
      items,
      isGroup: (e) => e.isGroup,
      delay: (e) => e.delay,
      isValidDelay: MuseFailoverTracker.isValid,
    ).map((e) => e.tag).toList();
    expect(order(const [
      MuseNodeSample(tag: 'a', delay: 65535, testedAt: 1, isGroup: false),
      MuseNodeSample(tag: 'b', delay: 300, testedAt: 1, isGroup: false),
    ]), ['b', 'a']);
    expect(order(const [
      MuseNodeSample(tag: 'a', delay: 280, testedAt: 2, isGroup: false),
      MuseNodeSample(tag: 'b', delay: 300, testedAt: 2, isGroup: false),
    ]), ['a', 'b']);
  });

  test('every bundled rule-set is in assets', () {
    for (final n in museBundledRuleSets) {
      expect(File('assets/rule-sets/$n.srs').existsSync(), isTrue, reason: n);
    }
  });
}
