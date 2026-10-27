// 穿云 1.4.0 batch 1: 测速 over dozens of nodes (cap, row states, delay cache), no global hotkey,
// 首页 tiles without a lone tile, Windows 「流量」 tile, KB/s floor.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/core_extras.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';

void main() {
  group('测速', () {
    test('cap grows with the node count, bounded', () {
      expect(museTestCap(nodes: 1), const Duration(seconds: 12));
      // 50 CF nodes, 16 workers, 5 s: 4 rounds of ~9 s
      expect(museTestCap(nodes: 50), const Duration(seconds: 39));
      expect(museTestCap(nodes: 500), const Duration(seconds: 90));
      expect(museTestCap(nodes: 50, workers: 32, timeoutSec: 3), const Duration(seconds: 17));
      expect(museTestCap(nodes: 0, workers: 0), const Duration(seconds: 12));
    });

    final since = DateTime(2026, 10, 22, 10);
    final started = since.add(const Duration(minutes: 1));
    test('only nodes not answered in the running test show 测速中', () {
      expect(
        museDelayView(delay: 0, testStarted: started, since: since),
        const MuseDelayView(MuseDelayKind.pending, 0),
      );
      expect(
        museDelayView(delay: 180, testedAt: started.add(const Duration(seconds: 2)), testStarted: started, since: since),
        const MuseDelayView(MuseDelayKind.live, 180),
      );
      expect(
        museDelayView(delay: 65535, testedAt: started.add(const Duration(seconds: 9)), testStarted: started, since: since).text,
        '超时',
      );
    });
    test('no test running: old results and the cache show grey, never 测速中', () {
      final old = since.subtract(const Duration(hours: 1));
      expect(museDelayView(delay: 220, testedAt: old, since: since), const MuseDelayView(MuseDelayKind.cached, 220));
      expect(museDelayView(delay: 0, since: since, cached: 300), const MuseDelayView(MuseDelayKind.cached, 300));
      expect(museDelayView(delay: 0, since: since, cached: 65535).text, '—');
      expect(museDelayView(delay: 0).text, '—');
      expect(museDelayView(delay: 150, testedAt: since.add(const Duration(seconds: 5)), since: since).kind, MuseDelayKind.live);
    });

    test('delay cache round trip, per subscription, old entries dropped', () {
      final now = DateTime(2026, 10, 22, 12);
      var c = MuseLatencyCache.empty.merge('p1', {
        'a': MuseCachedDelay(120, now),
        'b': MuseCachedDelay(65535, now),
        'old': MuseCachedDelay(90, now.subtract(const Duration(days: 8))),
        'none': MuseCachedDelay(0, now),
      });
      final back = MuseLatencyCache.parse(c.toRaw(now: now));
      expect(back.profileId, 'p1');
      expect(back.delayOf('a'), 120);
      expect(back.delayOf('b'), 65535);
      expect(back.delayOf('old'), isNull);
      expect(back.delayOf('none'), isNull);
      expect(back.forProfile('p2').delays, isEmpty);
      expect(identical(c.merge('p1', {'a': MuseCachedDelay(120, now)}), c), isTrue);
      c = c.merge('p2', {'x': MuseCachedDelay(50, now)});
      expect(c.delayOf('a'), isNull);
      expect(MuseLatencyCache.parse('garbage').delays, isEmpty);
    });

    test('core extras carry the 测速 settings, clamped', () {
      expect(museTestExtras(workers: 16, timeoutSec: 5), {'muse-test-workers': 16, 'muse-test-timeout-ms': 5000});
      expect(museTestExtras(workers: 1, timeoutSec: 99), {'muse-test-workers': 4, 'muse-test-timeout-ms': 15000});
      final old = museCoreExtras;
      museCoreExtras = {'muse-test-workers': 32};
      expect(museApplyCoreExtras({'a': 1, 'muse-test-workers': 1}), {'a': 1, 'muse-test-workers': 32});
      museCoreExtras = old;
    });
  });

  group('首页 tiles 1.4.0', () {
    test('no lone tile: columns follow the tile count', () {
      // 1.6.0: 4 columns from 860 px; just below = 2 columns
      expect(museTileColumnsFor(850, 4), 2);
      expect(museTileColumnsFor(860, 4), 4);
      expect(museTileColumnsFor(860, 3), 3);
      expect(museTileColumnsFor(860, 6), 3);
      expect(museTileColumnsFor(860, 5), 3);
      // wide: 4 max
      expect(museTileColumnsFor(1200, 4), 4);
      expect(museTileColumnsFor(1200, 6), 3);
      expect(museTileColumnsFor(1200, 8), 4);
      // phone
      expect(museTileColumnsFor(380, 6), 2);
      expect(museTileColumnsFor(380, 5), 2);
      expect(museTileColumnsFor(380, 1), 2);
      expect(museTileRows(5, 2), [
        [0, 1],
        [2, 3],
        [4],
      ]);
    });
    test('Windows: 网速 + 本次流量 = 流量 in place of the first', () {
      expect(
        museMergeFlowTiles([MuseHomeTile.speed, MuseHomeTile.traffic, MuseHomeTile.exit, MuseHomeTile.adBlock]),
        [MuseHomeTile.flow, MuseHomeTile.exit, MuseHomeTile.adBlock],
      );
      expect(
        museMergeFlowTiles([MuseHomeTile.exit, MuseHomeTile.traffic]),
        [MuseHomeTile.exit, MuseHomeTile.flow],
      );
      expect(museMergeFlowTiles([MuseHomeTile.exit]), [MuseHomeTile.exit]);
      // 流量 is never saved
      expect(museParseTileOrder('flow,exit').contains(MuseHomeTile.flow), isFalse);
      expect(museParseHiddenTiles('flow'), isEmpty);
    });
    test('speed is KB/s at least', () {
      expect(museSpeedText(110), '0.1 KB/s');
      expect(museSpeedText(0), '0 KB/s');
      expect(museSpeedText(5 * 1024), '5.0 KB/s');
      expect(museSpeedText(1024 * 1024 * 300), '300 MB/s');
    });
  });

  // 1.4.0 removed the fixed Ctrl+Alt+P hotkey and its setting; 1.6.0 C8 brings user-defined global
  // hotkeys back (设置 › 电脑 › 快捷键) with nothing bound by default, so nothing is registered
  // unless the user records a combination (v160_c8_test).
  test('the fixed Ctrl+Alt+P hotkey is gone; 1.6.0 hotkeys start unbound', () {
    expect(File('lib/features/muse/desktop/hotkey.dart').existsSync(), isFalse);
    expect(File('lib/core/preferences/general_preferences.dart').readAsStringSync().contains('muse_hotkey'), isFalse);
    final prefs = File('lib/features/muse/data/muse_prefs.dart').readAsStringSync();
    expect(prefs, contains('PreferencesNotifier.create<String, String>("muse_hotkeys", "")'));
    expect(File('lib/features/muse/desktop/hotkeys.dart').readAsStringSync().contains('Ctrl+Alt+P'), isFalse);
  });
}
