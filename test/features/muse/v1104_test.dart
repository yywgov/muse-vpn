// 穿云 1.10.4: 测速 faster and more accurate (core 5.0.0-muse.22), and the 首页「服务状态」card
// that stayed at 「检测中」 with every service at 「—」 forever.
import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/logic/service_probe.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

class _Exit extends MuseExitNotifier {
  _Exit() : super(() => 0) {
    state = const MuseExitResult(info: MuseExitInfo(ip: '45.76.112.9', country: 'US'));
  }
}

class _Reach extends MuseReachNotifier {
  _Reach() : super(() => 0) {
    state = MuseReach.ok;
  }
}

final _group = OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: 'DediRock-HY2',
  selectable: true,
  items: [OutboundInfo(tag: 'DediRock-HY2', type: 'hysteria2')],
);

void main() {
  group('服务状态: every service ends in a final state', () {
    test('a probe that never answers is 超时, one that throws is 不可用, answers carry their time', () async {
      final seen = <String, int?>{};
      final r = await museProbeServices(
        (s) {
          if (s.key == 'claude') return Completer<int?>().future; // never settles
          if (s.key == 'discord') throw const SocketException('reset');
          if (s.key == 'gemini') return Future<int?>.error(const MuseServiceTimeout());
          return Future.delayed(const Duration(milliseconds: 3), () => s.key == 'netflix' ? 403 : 204);
        },
        timeout: const Duration(milliseconds: 40),
        onResult: (k, v, ms) => seen[k] = ms,
      );
      expect(r.length, museServices.length, reason: 'every service has a result');
      expect(r['claude'], MuseSvcState.timeout);
      expect(r['gemini'], MuseSvcState.timeout);
      expect(r['discord'], MuseSvcState.failed);
      expect(r['netflix'], MuseSvcState.limited);
      expect(r['google'], MuseSvcState.ok);
      expect(seen['google'], isNotNull);
      expect(seen['claude'], isNull);
      expect(r.values.any((v) => v == MuseSvcState.checking || v == MuseSvcState.unknown), isFalse);
    });

    test('the whole check is capped: what is still open then is 超时', () async {
      final sw = Stopwatch()..start();
      final r = await museProbeServices(
        (s) => Completer<int?>().future,
        timeout: const Duration(seconds: 30), // per service longer than the cap
        totalCap: const Duration(milliseconds: 80),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      expect(r.length, museServices.length);
      expect(r.values.every((v) => v == MuseSvcState.timeout), isTrue);
    });

    test('the card value: 检测中 only while a check runs', () {
      const total = 13;
      expect(museServicesValue(running: false, s: const MuseServicesState(), total: total), '—');
      expect(museServicesValue(running: true, s: const MuseServicesState(checking: true), total: total), '检测中');
      expect(museServicesValue(running: true, s: const MuseServicesState(), total: total), '点按检测');
      expect(
        museServicesValue(running: true, s: const MuseServicesState(results: {'google': MuseSvcState.ok}), total: total),
        '1/13',
      );
      expect(museServiceLabel(MuseSvcState.ok, 182), '可用 182 ms');
      expect(museServiceLabel(MuseSvcState.timeout, null), '超时');
      expect(museServiceLabel(MuseSvcState.failed, null), '不可用');
    });

    test('a reset in the middle of a check leaves an idle state (not a check that never ends)', () async {
      final gate = Completer<void>();
      var calls = 0;
      final n = MuseServicesNotifier(() => (s) async {
        calls++;
        await gate.future;
        return 204;
      });
      final first = n.check();
      await Future<void>.delayed(Duration.zero);
      expect(n.state.checking, isTrue);
      n.reset(); // a new connection while checking
      expect(n.state.idle, isTrue, reason: 'nothing running, nothing shown: the card checks again');
      // the card starts the new check; the old one finishing does not overwrite it
      final second = n.check();
      gate.complete();
      await Future.wait([first, second]);
      expect(n.state.checking, isFalse);
      expect(n.state.okCount, 13);
      expect(calls, greaterThanOrEqualTo(13));
      n.dispose();
    });

    test('a node switch keeps the results (final) and makes the next check probe again', () async {
      var calls = 0;
      final n = MuseServicesNotifier(() => (s) async {
        calls++;
        return 204;
      });
      await n.check();
      expect(calls, 13);
      n.stale();
      expect(n.state.okCount, 13, reason: 'results stay on the card');
      expect(n.state.checking, isFalse);
      await n.check();
      expect(calls, 26, reason: 'the cache no longer counts');
      n.dispose();
    });

    test('a probe function that throws synchronously still ends the check', () async {
      final n = MuseServicesNotifier(() => (s) => throw StateError('boom'));
      await n.check();
      expect(n.state.checking, isFalse);
      expect(n.state.results.length, 13);
      expect(n.state.results.values.every((v) => v == MuseSvcState.failed), isTrue);
      n.dispose();
    });

    test('the provider: a reload of the node list (null in between) is not a node change', () {
      final src = _src('lib/features/muse/home/dashboard_cards.dart');
      expect(src, contains('if (prev != null && next != null && prev != next) n.stale();'));
      expect(src, contains('}, [running, idle]);'));
      expect(src, contains("if (running && !s.checking) ref.read(museServicesProvider.notifier).check(force: true);"));
      // no timer / polling added for the card
      final card = src.substring(src.indexOf('class _ServicesTile'), src.indexOf('class _ServicesSheet'));
      expect(card, isNot(contains('Timer')));
      expect(card, isNot(contains('periodic')));
    });

    test('the real probe bounds the request and closes the client', () {
      final src = _src('lib/features/muse/logic/service_probe.dart');
      expect(src, contains('client.getUrl(Uri.parse(service.url)).timeout(museServiceTimeout)'));
      expect(src, contains('req.close().timeout(museServiceTimeout)'));
      expect(src, contains('client.close(force: true)'));
      expect(museServiceTotalCap, const Duration(seconds: 30));
    });
  });

  group('服务状态 card on 首页', () {
    late ProviderContainer container;
    late List<String> probed;
    late Completer<void> hold;
    late MuseServicesNotifier notifier;

    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'muse_home_tiles_hidden': ''});
      final prefs = await SharedPreferences.getInstance();
      probed = [];
      hold = Completer<void>()..complete();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => prefs),
          museRunningProvider.overrideWithValue(true),
          museSubInfoProvider.overrideWithValue(
            SubscriptionInfo(upload: 0, download: 1024, total: 1 << 30, expire: DateTime.now().add(const Duration(days: 20))),
          ),
          museStatsProvider.overrideWithValue(SystemInfo(memory: Int64(64 * 1024 * 1024))),
          museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
          museConnectionsProvider.overrideWith((ref) => Stream.value(const MuseConnState())),
          museLanIpProvider.overrideWith((ref) async => ['192.168.1.216']),
          museExitProvider.overrideWith((ref) => _Exit()),
          museReachProvider.overrideWith((ref) => _Reach()),
          museServicesProvider.overrideWith((ref) {
            notifier = MuseServicesNotifier(() => (s) async {
              probed.add(s.key);
              await hold.future;
              return 204;
            });
            return notifier;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
      tester.view.physicalSize = const Size(780, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 390, child: MuseTileGrid(mergeFlow: false)))),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('results cleared while the card is on screen: it checks again and ends with a result', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('tile_services')), findsOneWidget);
      expect(find.text('13/13'), findsOneWidget);
      expect(probed.length, 13);
      // the 1.10.3 bug: results wiped while connected and on screen → 「检测中」 forever
      notifier.reset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(probed.length, 26, reason: 'the card started a new check by itself');
      await tester.pump(const Duration(seconds: 1)); // value cross-fade
      expect(find.text('13/13'), findsOneWidget);
      expect(find.text('检测中'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('a tap checks again', (tester) async {
      await pump(tester);
      expect(probed.length, 13);
      await tester.tap(find.byKey(const ValueKey('tile_services')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(probed.length, 26);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 31));
    });
  });

  group('测速 1.10.4', () {
    test('core 5.0.0-muse.22 for both cores', () {
      final deps = _src('dependencies.properties');
      // 1.11.0: 5.0.0-muse.23 (muse.22 + slimmer standard core), still carries the 1.10.4 测速
      expect(deps, contains('muse.core.version=5.0.0-muse.23'));
      expect(museCoreRelease, '5.0.0-muse.23');
      final ref = RegExp(r'muse\.compat\.ref=([0-9a-f]{40})').firstMatch(deps)!.group(1);
      expect(ref, isNot('0b29e71e991143cd1b0db0a075a863d2688a6182'), reason: 'the compatible core builds the 1.10.4 commit');
    });

    test('changelog says what changed, in words users understand', () {
      final lines = museChangelog['1.10.4']!;
      expect(lines.first, startsWith('测速更快、结果更准'));
      expect(lines.join(), contains('服务状态'));
      // 1.11.0 came after
      expect(museChangelog.keys.toList().indexOf('1.10.4'), lessThan(museChangelog.keys.toList().indexOf('1.10.3')));
      expect(_src('CHANGELOG.md'), contains('### 1.10.4'));
    });
  });
}
