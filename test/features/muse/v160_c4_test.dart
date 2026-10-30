// 穿云 1.6.0 C4 首页仪表盘: new cards, columns, editor order, 服务状态 probing, 内网 IP, 内存,
// 网络接管 mode step, preference migration 1→2.

import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs_migration.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart';
import 'package:hiddify/features/muse/logic/service_probe.dart';
import 'package:hiddify/features/muse/settings/service_mode_switch.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Iface implements NetworkInterface {
  _Iface(this.name, this.addresses);

  @override
  final String name;
  @override
  final List<InternetAddress> addresses;
  @override
  int get index => 0;
}

class _Exit extends MuseExitNotifier {
  _Exit() : super(() => 0) {
    state = const MuseExitResult(info: MuseExitInfo(ip: '45.76.112.9', country: 'JP'));
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
  selected: '🇯🇵 东京 02',
  selectable: true,
  items: [OutboundInfo(tag: '🇯🇵 东京 02', type: 'vless'), OutboundInfo(tag: '🇭🇰 香港 01', type: 'trojan')],
);

void main() {
  group('C4 card registry', () {
    test('new cards are stored, hidden by default, appended to an old order', () {
      for (final t in museNewTiles16) {
        expect(museStoredTiles, contains(t));
      }
      final hidden = museParseHiddenTiles(museDefaultHiddenTiles);
      expect(hidden.containsAll(museNewTiles16), isTrue);
      // a 1.5.x order gets the new cards at the end
      final order = museParseTileOrder('exit,speed,traffic,remaining,expiry,adblock');
      expect(order.sublist(6), museNewTiles16.toList());
    });
    test('migration 1→2 hides the new cards in a saved hidden list, keeps the user choice', () {
      final prefs = <String, Object?>{'muse_home_tiles_hidden': 'exit', 'muse_prefs_version': 1};
      expect(musePrefsMigrate(prefs), musePrefsVersionCurrent);
      final hidden = museParseHiddenTiles(prefs['muse_home_tiles_hidden']! as String);
      expect(hidden, {MuseHomeTile.exit, ...museNewTiles16});
      // idempotent
      final again = Map<String, Object?>.of(prefs);
      musePrefsMigrate(again);
      expect(again, prefs);
      // nothing saved = nothing to migrate (the default already hides them)
      final fresh = <String, Object?>{};
      musePrefsMigrate(fresh);
      expect(fresh.containsKey('muse_home_tiles_hidden'), isFalse);
    });
    test('migration on the store writes back only what changed', () async {
      SharedPreferences.setMockInitialValues({'muse_home_tiles_hidden': '', 'other': 'x'});
      final sp = await SharedPreferences.getInstance();
      expect(await musePrefsMigrateStore(sp), musePrefsVersionCurrent);
      expect(museParseHiddenTiles(sp.getString('muse_home_tiles_hidden')!), museNewTiles16);
      expect(sp.getInt('muse_prefs_version'), musePrefsVersionCurrent);
      expect(sp.getString('other'), 'x');
      // second run: unchanged
      await musePrefsMigrateStore(sp);
      expect(museParseHiddenTiles(sp.getString('muse_home_tiles_hidden')!), museNewTiles16);
    });
    test('网络接管 only on Windows; the editor reorders only the shown cards', () {
      expect(museTileOnPlatform(MuseHomeTile.takeover, windows: false), isFalse);
      expect(museTileOnPlatform(MuseHomeTile.takeover, windows: true), isTrue);
      expect(museTileOnPlatform(MuseHomeTile.memory, windows: false), isTrue);
      final order = museStoredTiles;
      final shown = [for (final t in order) if (museTileOnPlatform(t, windows: false)) t];
      final next = museReorderShownTiles(order, shown, shown.indexOf(MuseHomeTile.memory), 0);
      expect(next.first, MuseHomeTile.memory);
      expect(next.last, MuseHomeTile.takeover);
      expect(next.toSet(), order.toSet());
      expect(museReorderShownTiles(order, shown, 99, 0), order);
    });
    test('columns: 2 below 860, 4 from 860', () {
      expect(museTileColumns(390), 2);
      expect(museTileColumns(700), 2);
      expect(museTileColumns(1100), 4);
      expect(museTileColumnsFor(1100, 8), 4);
      expect(museTileColumnsFor(700, 8), 2);
    });
  });

  group('C4 服务状态', () {
    test('13 services, verdicts', () {
      expect(museServices.length, 13);
      expect(museServices.map((e) => e.key).toSet().length, 13);
      expect(museServiceVerdict(204), MuseSvcState.ok);
      expect(museServiceVerdict(302), MuseSvcState.ok);
      expect(museServiceVerdict(403), MuseSvcState.limited);
      expect(museServiceVerdict(451), MuseSvcState.limited);
      expect(museServiceVerdict(502), MuseSvcState.failed);
      expect(museServiceVerdict(null), MuseSvcState.failed);
    });
    test('at most 4 at once, every service once', () async {
      var running = 0;
      var peak = 0;
      final seen = <String>[];
      final r = await museProbeServices((s) async {
        running++;
        peak = running > peak ? running : peak;
        seen.add(s.key);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        return s.key == 'netflix' ? 403 : 200;
      });
      expect(peak, 4);
      expect(seen.length, 13);
      expect(r['netflix'], MuseSvcState.limited);
      expect(r['google'], MuseSvcState.ok);
    });
    test('a slow service times out as failed, the rest still finish', () async {
      final r = await museProbeServices(
        (s) => s.key == 'claude' ? Completer<int?>().future : Future.value(200),
        timeout: const Duration(milliseconds: 30),
      );
      expect(r['claude'], MuseSvcState.failed);
      expect(r.values.where((v) => v == MuseSvcState.ok).length, 12);
    });
    test('cache: fresh for 10 minutes', () {
      final c = MuseServiceCache();
      final t0 = DateTime(2026, 10, 27, 1);
      expect(c.fresh(t0), isFalse);
      c.store({'google': MuseSvcState.ok}, t0);
      expect(c.fresh(t0.add(const Duration(minutes: 9))), isTrue);
      expect(c.fresh(t0.add(const Duration(minutes: 10))), isFalse);
      c.clear();
      expect(c.fresh(t0), isFalse);
    });
    test('notifier uses the cache unless forced', () async {
      var calls = 0;
      var now = DateTime(2026, 10, 27, 1);
      final n = MuseServicesNotifier(() => (s) async {
        calls++;
        return 200;
      }, now: () => now);
      await n.check();
      expect(calls, 13);
      expect(n.state.okCount, 13);
      await n.check();
      expect(calls, 13);
      await n.check(force: true);
      expect(calls, 26);
      now = now.add(const Duration(minutes: 11));
      await n.check();
      expect(calls, 39);
      n.dispose();
    });
  });

  group('C4 内网 IP / 内存 / 代理组 / 网络接管', () {
    test('LAN addresses: IPv4 first, no loopback / link-local / TUN', () {
      final list = museLanAddresses([
        _Iface('lo', [InternetAddress('127.0.0.1')]),
        _Iface('tun0', [InternetAddress('172.19.0.1'), InternetAddress('198.18.0.1')]),
        _Iface('wlan0', [InternetAddress('2408:8207::1234'), InternetAddress('192.168.1.23'), InternetAddress('fe80::1')]),
        _Iface('eth0', [InternetAddress('10.0.0.5'), InternetAddress('192.168.1.23')]),
      ]);
      expect(list, ['192.168.1.23', '10.0.0.5', '2408:8207::1234']);
    });
    test('memory text and 30-point history', () {
      expect(museMemText(0), '—');
      expect(museMemText(12 * 1024 * 1024 + 300 * 1024), '12.3 MB');
      expect(museMemText(300 * 1024 * 1024), '300 MB');
      expect(museMemText(3 * 1024 * 1024 * 1024), '3.00 GB');
      var h = <int>[];
      for (var i = 0; i < 40; i++) {
        h = museAppendSample(h, i, 30);
      }
      expect(h.length, 30);
      expect(h.first, 10);
    });
    test('group titles', () {
      expect(museGroupTitle('select'), '手动选择');
      expect(museGroupTitle('auto'), '自动最快');
      expect(museGroupTitle('我的组'), '我的组');
    });
    test('网络接管 step: same mode nothing, TUN without admin asks, otherwise applies', () {
      expect(museModeStep(ServiceMode.systemProxy, ServiceMode.systemProxy, elevated: false), MuseModeStep.none);
      expect(museModeStep(ServiceMode.systemProxy, ServiceMode.tun, elevated: false), MuseModeStep.needsAdmin);
      expect(museModeStep(ServiceMode.systemProxy, ServiceMode.tun, elevated: true), MuseModeStep.apply);
      expect(museModeStep(ServiceMode.tun, ServiceMode.systemProxy, elevated: false), MuseModeStep.apply);
    });
    test('设置 › 电脑 and the card share one switch function', () {
      final win = File('lib/features/muse/settings/windows_settings.dart').readAsStringSync();
      final cards = File('lib/features/muse/home/dashboard_cards.dart').readAsStringSync();
      expect(win, contains('museSwitchServiceMode('));
      expect(cards, contains('museSwitchServiceMode('));
      expect(win, isNot(contains('relaunchElevated()')));
    });
  });

  group('C4 dashboard widget', () {
    Future<void> pump(WidgetTester tester, Size size) async {
      SharedPreferences.setMockInitialValues({'muse_home_tiles_hidden': ''});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => prefs),
          museRunningProvider.overrideWithValue(true),
          museSubInfoProvider.overrideWithValue(
            SubscriptionInfo(
              upload: 0,
              download: 1024,
              total: 100 * 1024 * 1024 * 1024,
              expire: DateTime.now().add(const Duration(days: 20)),
            ),
          ),
          museStatsProvider.overrideWithValue(SystemInfo(memory: Int64(64 * 1024 * 1024))),
          museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
          museConnectionsProvider.overrideWith((ref) => Stream.value(const MuseConnState())),
          museLanIpProvider.overrideWith((ref) async => ['192.168.1.23']),
          museExitProvider.overrideWith((ref) => _Exit()),
          museReachProvider.overrideWith((ref) => _Reach()),
          museServicesProvider.overrideWith((ref) => MuseServicesNotifier(() => (s) async => 204)),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SizedBox(width: size.width, child: const MuseTileGrid(mergeFlow: false))),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('phone: the new cards render in 2 columns without overflow', (tester) async {
      await pump(tester, const Size(390, 2400));
      for (final k in ['services', 'groups', 'connections', 'lanip', 'memory']) {
        expect(find.byKey(ValueKey('tile_$k')), findsOneWidget, reason: k);
      }
      // 网络接管 only on Windows (the test host is not)
      expect(find.byKey(const ValueKey('tile_takeover')), findsNothing);
      expect(find.text('🇯🇵 东京 02'), findsOneWidget);
      expect(find.text('192.168.1.23'), findsOneWidget);
      expect(find.text('64.0 MB'), findsOneWidget);
      expect(find.text('13/13'), findsOneWidget);
      final a = tester.getSize(find.byKey(const ValueKey('tile_speed')));
      expect(a.width, lessThan(390 / 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('wide: 4 columns', (tester) async {
      await pump(tester, const Size(1100, 1600));
      final w = tester.getSize(find.byKey(const ValueKey('tile_speed'))).width;
      expect(w, lessThan(1100 / 4));
      expect(w, greaterThan(1100 / 5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });
  });
}
