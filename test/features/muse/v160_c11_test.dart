// 穿云 1.6.0 C11 性能关卡: one row per delay update, lazy long lists, nothing new at start-up,
// streams and timers released after leaving a page.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/connections/connections_page.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/home/bad_nodes.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logs/logs_page.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/hiddifycore/generated/google/protobuf/timestamp.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------------------------
// 节点: 1000 nodes, delays arriving one at a time

final _groupState = StateProvider<OutboundGroup?>((ref) => null);

OutboundGroup _group(int count, Map<int, int> delays, {DateTime? testedAt}) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '节点 0',
  selectable: true,
  // fresh objects every time, as the core sends them
  items: [
    for (var i = 0; i < count; i++)
      OutboundInfo(
        tag: '节点 $i',
        tagDisplay: '节点 $i',
        type: 'vless',
        host: 'n$i.example.com',
        port: 443,
        urlTestDelay: delays[i] ?? 0,
        urlTestTime: delays.containsKey(i) && testedAt != null ? Timestamp.fromDateTime(testedAt) : null,
      ),
  ],
);

Future<ProviderContainer> _pumpNodes(WidgetTester t, {Map<String, Object> prefs = const {}, Size size = const Size(412, 900)}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      museRunningProvider.overrideWithValue(true),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('机场'),
      museNodeGroupProvider.overrideWith((ref) => AsyncData(ref.watch(_groupState))),
      museActiveConfigProvider.overrideWith((ref) async => ''),
      museConnectedSinceProvider.overrideWith((ref) async => null),
      museHiddenNodesProvider.overrideWith((ref) => const <String>{}),
    ],
  );
  addTearDown(c.dispose);
  c.read(_groupState.notifier).state = _group(1000, const {});
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  await t.runAsync(() => c.read(museActiveConfigProvider.future));
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const Scaffold(body: MuseNodeList()),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return c;
}

/// Sends 50 single-node delay updates and returns how many rows each one rebuilt.
Future<List<int>> _fiftyUpdates(WidgetTester t, ProviderContainer c, {DateTime? testedAt}) async {
  final delays = <int, int>{};
  final per = <int>[];
  for (var k = 0; k < 50; k++) {
    // nodes on screen and off screen alike
    delays[k.isEven ? k ~/ 2 : 500 + k] = 80 + k;
    MuseNodeRow.debugBuilds = 0;
    c.read(_groupState.notifier).state = _group(1000, Map.of(delays), testedAt: testedAt);
    await t.pump();
    per.add(MuseNodeRow.debugBuilds);
  }
  return per;
}

// ---------------------------------------------------------------------------------------------
// 连接 / 日志: a local interface that only counts streams

class _FakeApi extends MuseLocalApi {
  _FakeApi() : super(port: 1, secret: 'x');

  int opened = 0;
  int closed = 0;
  final controllers = <StreamController<String>>[];

  @override
  Stream<String> stream(String path, {Map<String, String>? query}) {
    late final StreamController<String> ctrl;
    ctrl = StreamController<String>(onListen: () => opened++, onCancel: () => closed++);
    controllers.add(ctrl);
    return ctrl.stream;
  }

  @override
  Future<bool> closeAll() async => true;
}

MuseConn _conn(int i) => MuseConn(
  id: 'c$i',
  host: 'host$i.example.com',
  destination: '1.2.3.4:443',
  network: 'tcp',
  inbound: 'mixed',
  chains: const ['节点 1'],
  rule: 'final',
  process: '',
  upload: i,
  download: i * 10,
  start: DateTime(2026),
);

Widget _app(ProviderContainer c, Widget home) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)), home: home),
);

void main() {
  group('C11 节点: a delay update rebuilds only that node', () {
    testWidgets('1000 nodes (列表, 原始顺序): first build is lazy, each of 50 updates rebuilds ≤ 2 rows', (t) async {
      MuseNodeRow.debugBuilds = 0;
      final c = await _pumpNodes(t, prefs: {'muse_node_sort': 'original'});
      expect(MuseNodeRow.debugBuilds, inInclusiveRange(1, 60), reason: 'only the rows on screen are built');
      final per = await _fiftyUpdates(t, c);
      expect(per.every((n) => n <= 2), isTrue, reason: '$per');
      // the updates that hit a row on screen did rebuild it
      expect(per.where((n) => n > 0), isNotEmpty);
      expect(find.text('80 ms'), findsOneWidget);
    });

    testWidgets('卡片 layout: the same ≤ 2 rows per update', (t) async {
      final c = await _pumpNodes(t, prefs: {'muse_node_sort': 'original', 'muse_node_layout': 'grid'}, size: const Size(900, 900));
      expect(find.byKey(const ValueKey('node_card')), findsWidgets);
      final per = await _fiftyUpdates(t, c);
      expect(per.every((n) => n <= 2), isTrue, reason: '$per');
    });

    testWidgets('按延迟 while 测速 runs (order frozen): ≤ 2 rows per update', (t) async {
      final c = await _pumpNodes(t);
      final started = DateTime.now();
      c.read(museNodeTestStartedProvider.notifier).state = started;
      await t.pump();
      final per = await _fiftyUpdates(t, c, testedAt: started.add(const Duration(milliseconds: 1)));
      expect(per.every((n) => n <= 2), isTrue, reason: '$per');
    });

    testWidgets('按延迟 with the order changing: rows move instead of being rebuilt', (t) async {
      final c = await _pumpNodes(t);
      final per = await _fiftyUpdates(t, c);
      // a node jumping to the top changes which rows sit first / last in the card (corners,
      // dividers); everything else keeps its element
      expect(per.every((n) => n <= 6), isTrue, reason: '$per');
    });

    testWidgets('a list-wide change (卡型) still rebuilds every row on screen', (t) async {
      final c = await _pumpNodes(t, prefs: {'muse_node_sort': 'original'});
      MuseNodeRow.debugBuilds = 0;
      await t.runAsync(() => c.read(MusePrefs.nodeDensity.notifier).update('compact'));
      await t.pump();
      expect(MuseNodeRow.debugBuilds, greaterThan(5));
    });

    testWidgets('scrolling 1000 nodes builds only what comes into view', (t) async {
      await _pumpNodes(t, prefs: {'muse_node_sort': 'original'});
      MuseNodeRow.debugBuilds = 0;
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -600));
      await t.pump();
      expect(MuseNodeRow.debugBuilds, inInclusiveRange(1, 30));
      expect(find.text('节点 999'), findsNothing);
    });
  });

  group('C11 连接 / 日志: long lists are lazy, scrolling does not rebuild the page', () {
    Future<ProviderContainer> pump(WidgetTester t, Widget page, {List<Override> overrides = const [], Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp), ...overrides]);
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(sharedPreferencesProvider.future));
      t.view.physicalSize = const Size(412, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(c, page));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      return c;
    }

    Future<void> done(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    }

    testWidgets('1000 connections: ~a screenful built; scrolling only builds rows coming into view', (t) async {
      final conns = [for (var i = 0; i < 1000; i++) _conn(i)];
      await pump(
        t,
        const MuseConnectionsPage(),
        overrides: [
          museRunningProvider.overrideWithValue(true),
          museConnectionsProvider.overrideWith((ref) => Stream.value(MuseConnState(connections: conns))),
        ],
      );
      final built = find.byType(MuseConnRow).evaluate().length;
      expect(built, inInclusiveRange(5, 40));
      final summary = t.element(find.byKey(const ValueKey('conn_tabs')));
      final list = t.widget<ListView>(find.byKey(const ValueKey('conn_list')));
      expect(list.itemExtent, museConnRowHeight);
      await t.drag(find.byKey(const ValueKey('conn_list')), const Offset(0, -3000));
      await t.pump();
      // the page above the list is the same element, not rebuilt from scratch
      expect(t.element(find.byKey(const ValueKey('conn_tabs'))), same(summary));
      expect(find.byType(MuseConnRow).evaluate().length, inInclusiveRange(5, 40));
      expect(find.text('host0.example.com'), findsNothing);
      await done(t);
    });

    testWidgets('1000 log lines: lazy list', (t) async {
      final now = DateTime(2026);
      final logs = [for (var i = 0; i < 1000; i++) MuseLogLine('info', 'line $i', now)];
      await pump(
        t,
        const MuseLogsPage(),
        prefs: {'muse_log_capture': true},
        overrides: [museLogsProvider.overrideWith((ref) => Stream.value(logs))],
      );
      final rich = find.descendant(of: find.byKey(const ValueKey('logs_list')), matching: find.byType(RichText));
      expect(rich.evaluate().length, inInclusiveRange(5, 80));
      expect(find.textContaining('line 999', findRichText: true), findsOneWidget);
      expect(find.textContaining('line 0', findRichText: true), findsNothing);
      await t.drag(find.byKey(const ValueKey('logs_list')), const Offset(0, 2000));
      await t.pump();
      expect(rich.evaluate().length, inInclusiveRange(5, 80));
      await done(t);
    });

    test('log buffer keeps 1000 lines, request history 500', () {
      final b = MuseLogBuffer();
      for (var i = 0; i < 1500; i++) {
        b.add(MuseLogLine('info', '$i', DateTime(2026)));
      }
      expect(b.lines.length, 1000);
      expect(b.lines.last.text, '1499');
      final h = MuseRequestHistory();
      for (var i = 0; i < 700; i++) {
        h.add(_conn(i));
      }
      expect(h.length, 500);
    });
  });

  group('C11 leaving a page releases its streams and timers (#224)', () {
    Future<(ProviderContainer, _FakeApi, GlobalKey<NavigatorState>)> host(WidgetTester t, {Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final api = _FakeApi();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => sp),
          museRunningProvider.overrideWithValue(true),
          museLocalApiProvider.overrideWith((ref) => api),
        ],
      );
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(sharedPreferencesProvider.future));
      t.view.physicalSize = const Size(412, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            navigatorKey: nav,
            theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      return (c, api, nav);
    }

    Future<void> inAndOut(WidgetTester t, GlobalKey<NavigatorState> nav, Widget page, int times) async {
      for (var i = 0; i < times; i++) {
        unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => page)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 20));
        nav.currentState!.pop();
        await t.pump();
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('连接 opened and closed 100 times: one stream at most, none after the grace', (t) async {
      final (c, api, nav) = await host(t);
      await inAndOut(t, nav, const MuseConnectionsPage(), 100);
      // a quick back-and-forth reuses the stream instead of reconnecting
      expect(api.opened, 1);
      await t.pump(const Duration(seconds: 1)); // the last page finishes its exit transition
      await t.pump(museStreamGrace + const Duration(seconds: 1));
      expect(api.closed, api.opened);
      expect(c.exists(museConnectionsProvider), isFalse);
      // after the grace a new visit opens a fresh stream, and closes it again
      await inAndOut(t, nav, const MuseConnectionsPage(), 1);
      await t.pump(const Duration(seconds: 1)); // the last page finishes its exit transition
      await t.pump(museStreamGrace + const Duration(seconds: 1));
      expect((api.opened, api.closed), (2, 2));
    });

    testWidgets('日志 opened and closed 100 times: the log stream is released too', (t) async {
      final (c, api, nav) = await host(t, prefs: {'muse_log_capture': true});
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const MuseLogsPage())));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      // lines still flow through while the page is open
      api.controllers.last.add('{"type":"info","payload":"hello there"}');
      await t.pump();
      expect(find.textContaining('hello there', findRichText: true), findsOneWidget);
      nav.currentState!.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      // a quiet core sends nothing more: leaving must still close the stream
      await inAndOut(t, nav, const MuseLogsPage(), 99);
      expect(api.opened, 1);
      await t.pump(const Duration(seconds: 1)); // the last page finishes its exit transition
      await t.pump(museStreamGrace + const Duration(seconds: 1));
      expect(api.closed, api.opened);
      expect(c.exists(museLogsProvider), isFalse);
    });

    testWidgets('首页 timer: only the time text ticks; leaving cancels its timer', (t) async {
      var parentBuilds = 0;
      final since = DateTime.now().subtract(const Duration(seconds: 5));
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (_) {
              parentBuilds++;
              return Scaffold(body: MuseUptimeText(since: since));
            },
          ),
        ),
      );
      expect(find.byKey(const ValueKey('home_timer')), findsOneWidget);
      MuseUptimeText.debugBuilds = 0;
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(MuseUptimeText.debugBuilds, 3);
      expect(parentBuilds, 1);
      // the test fails on its own if a timer is still pending after this
      await t.pumpWidget(const SizedBox());
    });

    test('the hero card no longer ticks the whole card', () {
      final s = File('lib/features/muse/home/muse_home_page.dart').readAsStringSync();
      final hero = s.substring(s.indexOf('class MuseHeroCard'), s.indexOf('class MuseUptimeText'));
      expect(hero.contains('Timer.periodic'), isFalse);
      expect(hero.contains('MuseUptimeText('), isTrue);
    });

    test('every periodic timer in 穿云 code is cancelled in the same file', () {
      final files = Directory('lib/features/muse').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final s = f.readAsStringSync();
        final periodic = 'Timer.periodic('.allMatches(s).length;
        if (periodic == 0) continue;
        final cancels = '.cancel'.allMatches(s).length;
        expect(cancels, greaterThanOrEqualTo(periodic), reason: f.path);
      }
    });
  });

  group('C11 start-up: the new features do no work until used', () {
    test('快捷键 with nothing bound never touches the plugin', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.leanflutter.plugins/hotkey_manager'),
        (m) async {
          calls.add(m.method);
          return null;
        },
      );
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp), museHotkeysForceProvider.overrideWithValue(true)],
      );
      addTearDown(c.dispose);
      await c.read(sharedPreferencesProvider.future);
      final sub = c.listen(museHotkeysProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, isEmpty);
    });

    test('按需运行 off: no timer, no Wi‑Fi read', () {
      fakeAsync((async) {
        SharedPreferences.setMockInitialValues({});
        late ProviderContainer c;
        var reads = 0;
        SharedPreferences.getInstance().then((sp) {
          c = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWith((ref) async => sp),
              museOnDemandForceProvider.overrideWithValue(true),
              museSsidReaderProvider.overrideWithValue(() async {
                reads++;
                return const MuseSsidRead.ok(null);
              }),
            ],
          );
        });
        async.flushMicrotasks();
        c.read(sharedPreferencesProvider.future);
        async.flushMicrotasks();
        c.listen(museOnDemandProvider, (_, _) {});
        async.flushMicrotasks();
        expect(async.periodicTimerCount, 0);
        async.elapse(const Duration(minutes: 1));
        expect(reads, 0);
        c.dispose();
      });
    });

    test('start-up code does not reach the new pages, probes or plugins', () {
      final boot = File('lib/bootstrap.dart').readAsStringSync();
      for (final m in ['service_probe', 'resources_page', 'logic/resources', 'hotkey_manager', 'wifi_ssid', 'connections_page', 'logs_page']) {
        expect(boot.contains(m), isFalse, reason: m);
      }
      final app = File('lib/features/app/widget/app.dart').readAsStringSync();
      expect(app.contains('museServicesProvider'), isFalse);
      expect(app.contains('museConnectionsProvider'), isFalse);
      expect(app.contains('museLogsProvider'), isFalse);
      // the Windows / Android start-up listeners stay behind their platform check
      expect(RegExp(r'if \(PlatformUtils\.isWindows\) \{\s*ref\.listen\(museHotkeysProvider').hasMatch(app), isTrue);
      // 按需运行 waits 3 s before its first look; 自动运行 waits for the first frame
      expect(File('lib/features/muse/desktop/on_demand.dart').readAsStringSync().contains('Timer(const Duration(seconds: 3), tick)'), isTrue);
      expect(File('lib/features/muse/home/auto_run.dart').readAsStringSync().contains('Timer(museAutoRunDelay'), isTrue);
      // the resource page reads its files after its first frame
      expect(File('lib/features/muse/settings/resources_page.dart').readAsStringSync().contains('microtask'), isTrue);
    });

    test('new C11 code stays free of upstream names', () {
      for (final f in ['test/features/muse/v160_c11_test.dart']) {
        final s = File(f).readAsStringSync();
        for (final w in ['Fl' 'Clash', 'Hidd' 'ify', 'sing' '-box']) {
          // the package import path is the project's Dart name, not a user-visible word
          expect(s.replaceAll('package:hid' 'dify/', '').contains(w), isFalse, reason: '$f $w');
        }
      }
    });
  });
}
