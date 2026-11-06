// 穿云 1.10.3: 测速 on home broadband with session limits / QoS (China Mobile) showed many working
// nodes as 超时. Fewer tests at once (8), a longer probe timeout (8 s), and one re-test of a node
// that failed before it is shown as 超时 (the core reports 0 meanwhile; the list keeps 测速中).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/core_extras.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/resources.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('测速默认值', () {
    test('8 tests at once, 8 s per probe; choices around them', () {
      expect(museTestWorkersDefault, 8);
      expect(museTestTimeoutDefault, 8);
      expect(museTestWorkersChoices, contains(museTestWorkersDefault));
      expect(museTestTimeoutChoices, contains(museTestTimeoutDefault));
      expect(museTestWorkersDefault, lessThanOrEqualTo(10));
      // sent to both cores as before (keys and clamping unchanged)
      expect(museTestExtras(workers: museTestWorkersDefault, timeoutSec: museTestTimeoutDefault), {
        'muse-test-workers': 8,
        'muse-test-timeout-ms': 8000,
      });
    });

    test('a value the user picked in 开发者选项 is kept (only the default changed, same keys)', () {
      final prefs = _src('lib/features/muse/data/muse_prefs.dart');
      expect(prefs, contains('PreferencesNotifier.create<int, int>("muse_test_workers", museTestWorkersDefault)'));
      expect(prefs, contains('PreferencesNotifier.create<int, int>("muse_test_timeout_sec", museTestTimeoutDefault)'));
      final dev = _src('lib/features/muse/settings/developer_page.dart');
      expect(dev, contains('MusePrefs.testWorkers.notifier).update(museTestWorkersDefault)'));
      expect(dev, contains('MusePrefs.testTimeoutSec.notifier).update(museTestTimeoutDefault)'));
    });

    test('the list waits long enough for the re-tests, at most 2 minutes', () {
      final c = museTestCap(nodes: 20);
      // 3 rounds of (8 + 3 + 1) s, one round of re-tests (3 + 8 + 1) s, 3 s slack
      expect(c, const Duration(seconds: 3 * 12 + 12 + 3));
      expect(museTestCap(nodes: 2000), const Duration(seconds: 120));
      expect(museTestCap(nodes: 1, timeoutSec: 2).inSeconds, greaterThanOrEqualTo(10));
    });
  });

  group('超时前重测一次', () {
    final since = DateTime(2026, 11, 4, 18);
    final started = since.add(const Duration(minutes: 1));
    final answered = started.add(const Duration(seconds: 3));

    test('0 during a 测速 = being re-tested: still 测速中, not 超时 and not —', () {
      expect(
        museDelayView(delay: 0, testedAt: answered, testStarted: started, since: since),
        const MuseDelayView(MuseDelayKind.pending, 0),
      );
      // even with an older good value in the cache
      expect(
        museDelayView(delay: 0, testedAt: answered, testStarted: started, since: since, cached: 300).kind,
        MuseDelayKind.pending,
      );
    });

    test('the re-test answers: slow but working shows its delay; a second failure shows 超时', () {
      final later = answered.add(const Duration(seconds: 11));
      expect(
        museDelayView(delay: 1800, testedAt: later, testStarted: started, since: since),
        const MuseDelayView(MuseDelayKind.live, 1800),
      );
      expect(museDelayView(delay: 65535, testedAt: later, testStarted: started, since: since).text, '超时');
    });

    test('after the 测速 ended a node still at 0 is not shown as 超时', () {
      expect(museDelayView(delay: 0, testedAt: answered, since: since).kind, isNot(MuseDelayKind.timeout));
      expect(museDelayView(delay: 0, testedAt: answered, since: since, cached: 250), const MuseDelayView(MuseDelayKind.cached, 250));
    });

    test('museAnsweredTest: only a real result of this 测速 counts', () {
      expect(museAnsweredTest(delay: 120, testedAt: answered, testStarted: started), isTrue);
      expect(museAnsweredTest(delay: 65535, testedAt: answered, testStarted: started), isTrue);
      expect(museAnsweredTest(delay: 0, testedAt: answered, testStarted: started), isFalse);
      expect(museAnsweredTest(delay: 120, testStarted: started), isFalse);
      expect(museAnsweredTest(delay: 120, testedAt: started.subtract(const Duration(seconds: 5)), testStarted: started), isFalse);
      // results stamped just before the tap (clock granularity) still count, as before
      expect(museAnsweredTest(delay: 120, testedAt: started.subtract(const Duration(milliseconds: 500)), testStarted: started), isTrue);
    });

    test('the node list ends the 测速 only when every node has a real result, and the progress agrees', () {
      final src = _src('lib/features/muse/nodes/node_list.dart');
      expect(src, contains('nodes.every((e) => museAnsweredTest(delay: e.urlTestDelay'));
      expect(src, contains('if (!e.isGroup) e.hasUrlTestTime() && e.urlTestDelay != 0 ? e.urlTestTime.toDateTime() : null,'));
      // a node being re-tested is not counted as done
      final p = museTestProgress([answered, null], started);
      expect(p, (done: 1, total: 2));
    });
  });

  group('发布 1.10.3', () {
    test('version, notes in plain words, CHANGELOG', () {
      // 1.10.4 came after (v1104_test)
      expect(museChangelog.keys, contains('1.10.3'));
      expect(museChangelog.keys.toList().indexOf('1.10.3'), lessThan(museChangelog.keys.toList().indexOf('1.10.2')));
      final notes = museChangelog['1.10.3']!;
      expect(notes.join(), contains('超时'));
      expect(notes.join(), contains('自动再测一次'));
      for (final n in notes) {
        expect(n.toLowerCase(), isNot(anyOf(contains('sing-box'), contains('hiddify'), contains('mihomo'), contains('clash'))));
      }
      final md = _src('CHANGELOG.md');
      expect(md.indexOf('### 1.10.3'), lessThan(md.indexOf('### 1.10.2')));
    });

    test('both cores from the same core commit (1.11.0: muse.23, a descendant of muse.22)', () {
      final props = _src('dependencies.properties');
      expect(props, contains('muse.core.version=5.0.0-muse.23'));
      expect(museCoreRelease, '5.0.0-muse.23');
      expect(props, contains('muse.compat.ref=66d82b1502a3b735643faf0e8102aa95f217dd34'));
    });
  });
}
