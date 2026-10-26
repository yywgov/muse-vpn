// 穿云 1.6.0 C3: local control API client, live connections / 请求, logs, rotation, 屏蔽此域名.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/logger/sinks/file_sink_io.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/connections/connections_page.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logs/logs_page.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _conn(String id, {String host = 'www.example.com', int up = 0, int down = 0, String rule = 'final'}) => {
  'id': id,
  'metadata': {'network': 'tcp', 'type': 'mixed/in', 'destinationIP': '93.184.216.34', 'destinationPort': '443', 'host': host},
  'upload': up,
  'download': down,
  'start': '2026-10-27T01:00:00Z',
  'chains': ['日本 01', 'select'],
  'rule': rule,
  'rulePayload': '',
};

String _frame(List<Map<String, Object?>> conns, {int up = 0, int down = 0}) =>
    jsonEncode({'downloadTotal': down, 'uploadTotal': up, 'connections': conns, 'memory': 1024});

void main() {
  group('client', () {
    test('web secret: 32 hex chars, different each time', () {
      final a = museNewWebSecret();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(museNewWebSecret(), isNot(a));
    });

    test('frame parse, speeds from deltas, ended connections go to 请求', () {
      final h = MuseRequestHistory();
      final t = MuseConnTracker(history: h);
      final t0 = DateTime(2026, 10, 27, 1);
      var live = t.apply(museParseConnFrame(_frame([_conn('a', up: 100, down: 1000), _conn('b', host: '')])), t0);
      expect(live.length, 2);
      expect(live.firstWhere((c) => c.id == 'b').host, '93.184.216.34');
      expect(live.first.node, '日本 01');
      live = t.apply(museParseConnFrame(_frame([_conn('a', up: 300, down: 5000)])), t0.add(const Duration(seconds: 2)));
      expect(live.single.upSpeed, 100);
      expect(live.single.downSpeed, 2000);
      expect(h.length, 1);
      expect(h.items.single.id, 'b');
      expect(h.items.single.end, isNotNull);
    });

    test('unchanged rows keep their identity (cheap rebuilds)', () {
      final t = MuseConnTracker(history: MuseRequestHistory());
      final now = DateTime(2026);
      final first = t.apply(museParseConnFrame(_frame([_conn('a')])), now).single;
      final second = t.apply(museParseConnFrame(_frame([_conn('a')])), now.add(const Duration(seconds: 1))).single;
      expect(identical(first, second), isTrue);
    });

    test('请求 keeps the newest 500', () {
      final h = MuseRequestHistory();
      final c = MuseConn.fromJson(_conn('x'))!;
      for (var i = 0; i < 620; i++) {
        h.add(c);
      }
      expect(h.length, 500);
    });

    test('sort and search', () {
      final list = [
        MuseConn.fromJson(_conn('1', host: 'a.com', down: 10))!.copyWith(downSpeed: 5),
        MuseConn.fromJson(_conn('2', host: 'b.org', down: 999, rule: 'geosite-cn'))!,
      ];
      expect(museSortConns(list, MuseConnSort.speed).first.id, '1');
      expect(museSortConns(list, MuseConnSort.traffic).first.id, '2');
      expect(museSortConns(list, MuseConnSort.speed, query: 'GEOSITE').single.id, '2');
      expect(museSortConns(list, MuseConnSort.host, query: '日本').length, 2);
    });

    test('big frames are parsed in an isolate with the same result', () async {
      final big = _frame([for (var i = 0; i < 1500; i++) _conn('id$i', host: 'host-$i.example.com')]);
      expect(big.length, greaterThan(museConnIsolateBytes));
      final f = await museParseConnFrameAsync(big);
      expect(f.connections.length, 1500);
    });

    test('logs: parse, level filter, search, 1000-line buffer', () {
      final now = DateTime(2026);
      final i = MuseLogLine.fromJson('{"type":"info","payload":"hello"}', now)!;
      final w = MuseLogLine.fromJson('{"type":"warn","payload":"slow"}', now)!;
      expect(w.level, 'warning');
      expect(MuseLogLine.fromJson('not json', now), isNull);
      expect(museLogPasses(i, 'warning', ''), isFalse);
      expect(museLogPasses(w, 'warning', ''), isTrue);
      expect(museLogPasses(i, 'debug', 'HEL'), isTrue);
      final b = MuseLogBuffer();
      for (var k = 0; k < 1200; k++) {
        b.add(i);
      }
      expect(b.lines.length, 1000);
    });

    test('export text is redacted', () {
      final l = MuseLogLine('info', 'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443', DateTime(2026));
      expect(museLogExportText([l]).contains('11111111-2222-3333-4444-555555555555'), isFalse);
    });
  });

  test('log file rotates over the limit and keeps 3 files (#175)', () {
    final dir = Directory.systemTemp.createTempSync('muse_log');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.log';
    File(path).writeAsStringSync('x' * 200);
    expect(museRotateLogFile(path, maxBytes: 100), isTrue);
    File(path).writeAsStringSync('y' * 200);
    expect(museRotateLogFile(path, maxBytes: 100), isTrue);
    File(path).writeAsStringSync('z' * 200);
    expect(museRotateLogFile(path, maxBytes: 100), isTrue);
    expect(File('$path.1').readAsStringSync().startsWith('z'), isTrue);
    expect(File('$path.2').readAsStringSync().startsWith('y'), isTrue);
    expect(File('$path.3').existsSync(), isFalse);
    expect(museRotateLogFile(path, maxBytes: 100), isFalse);
    expect(museLogMaxBytes, 5 * 1024 * 1024);
  });

  group('屏蔽此域名', () {
    test('block rule sits right after 局域网; IPs become /32', () {
      final rules = [
        Rule(name: museLanRuleName, enabled: true, outbound: Outbound.direct),
        Rule(name: 'mine', enabled: true, outbound: Outbound.proxy),
      ];
      final out = museApplyBlockedHosts(rules, ['ads.example.com', '1.2.3.4']);
      expect(out.map((r) => r.name), [museLanRuleName, museBlockedHostsRuleName, '$museBlockedHostsRuleName:ip', 'mine']);
      expect(out[1].outbound, Outbound.block);
      expect(out[1].domainSuffixes, ['ads.example.com']);
      expect(out[2].ipCidrs, ['1.2.3.4/32']);
      expect([for (final r in out) r.listOrder], [0, 1, 2, 3]);
      expect(museApplyBlockedHosts(rules, const []), same(rules));
    });

    test('hosts list: lower-case, no duplicates, bad JSON is empty', () {
      expect(museAddBlockedHost(const [], ' A.COM '), ['a.com']);
      final l = ['a.com'];
      expect(museAddBlockedHost(l, 'a.com'), same(l));
      expect(museParseBlockedHosts('{oops'), isEmpty);
      expect(museParseBlockedHosts(museBlockedHostsToRaw(['x.org'])), ['x.org']);
    });

    test('the core gets the blocked hosts and the per-install key', () {
      final src = File('lib/features/settings/data/config_option_repository.dart').readAsStringSync();
      expect(src.contains('museApplyBlockedHosts('), isTrue);
      expect(src.contains('webSecret: ref.watch(museWebSecretProvider)'), isTrue);
      final model = File('lib/singbox/model/singbox_config_option.dart').readAsStringSync();
      expect(model.contains('String webSecret'), isTrue);
      expect(model.contains('FieldRename.kebab'), isTrue);
    });
  });

  test('web secret is made once and kept locally (not synced)', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
    addTearDown(c.dispose);
    await c.read(sharedPreferencesProvider.future);
    final a = c.read(museWebSecretProvider);
    expect(sp.getString(museWebSecretKey), a);
    final c2 = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
    addTearDown(c2.dispose);
    await c2.read(sharedPreferencesProvider.future);
    expect(c2.read(museWebSecretProvider), a);
    expect(museSyncedPrefKeys.contains(museWebSecretKey), isFalse);
  });

  test('streams stop 5 s after the last listener leaves, not before', () {
    fakeAsync((async) {
      var disposed = 0;
      final p = Provider.autoDispose<int>((ref) {
        museKeepFor(ref, museStreamGrace);
        ref.onDispose(() => disposed++);
        return 1;
      });
      final c = ProviderContainer();
      for (var i = 0; i < 100; i++) {
        final sub = c.listen(p, (_, _) {});
        sub.close();
        async.elapse(const Duration(seconds: 1));
      }
      expect(disposed, 0);
      async.elapse(const Duration(seconds: 6));
      expect(disposed, 1);
      c.dispose();
    });
  });

  test('連接 / 日志 never touch the connection state', () {
    for (final f in [
      'lib/features/muse/local_api/local_api_client.dart',
      'lib/features/muse/local_api/local_api_providers.dart',
      'lib/features/muse/connections/connections_page.dart',
      'lib/features/muse/logs/logs_page.dart',
    ]) {
      final s = File(f).readAsStringSync();
      expect(s.contains('connection_notifier.dart'), isFalse, reason: f);
      expect(s.contains('toggleConnection'), isFalse, reason: f);
    }
  });

  group('pages', () {
    Future<ProviderContainer> pump(WidgetTester t, Widget page, {MuseConnState? conns, List<MuseLogLine>? logs, Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => sp),
          museRunningProvider.overrideWithValue(conns != null),
          if (conns != null) museConnectionsProvider.overrideWith((ref) => Stream.value(conns)),
          if (logs != null) museLogsProvider.overrideWith((ref) => Stream.value(logs)),
        ],
      );
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(sharedPreferencesProvider.future));
      t.view.physicalSize = const Size(412, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)), home: page),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      return c;
    }

    // the streams linger 5 s after the page leaves
    Future<void> done(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    }

    testWidgets('连接: not connected shows a hint', (t) async {
      await pump(t, const MuseConnectionsPage());
      expect(find.text('连接后可查看实时连接'), findsOneWidget);
      await done(t);
    });

    testWidgets('连接: list, search, details, 屏蔽 adds a rule host', (t) async {
      final conns = [
        for (var i = 0; i < 40; i++) MuseConn.fromJson(_conn('c$i', host: 'host$i.example.com', down: i * 100))!,
      ];
      final c = await pump(t, const MuseConnectionsPage(), conns: MuseConnState(connections: conns));
      expect(find.byKey(const ValueKey('conn_list')), findsOneWidget);
      // lazy: far fewer rows built than 40
      expect(find.byType(MuseConnRow).evaluate().length, lessThan(40));
      await t.enterText(find.byKey(const ValueKey('conn_search')), 'host39');
      await t.pump();
      expect(find.byType(MuseConnRow), findsOneWidget);
      await t.tap(find.text('host39.example.com'));
      await t.pumpAndSettle();
      expect(find.text('连接详情'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('conn_block')));
      await t.pumpAndSettle();
      expect(museParseBlockedHosts(c.read(MusePrefs.blockedHosts)), ['host39.example.com']);
      await done(t);
    });

    testWidgets('日志: off shows the switch hint; on lists lines and filters by level', (t) async {
      await pump(t, const MuseLogsPage());
      expect(find.text('打开「日志记录」后显示内核实时日志'), findsOneWidget);
      await done(t);
      final now = DateTime(2026);
      await pump(
        t,
        const MuseLogsPage(),
        prefs: {'muse_log_capture': true},
        logs: [MuseLogLine('info', 'hello world', now), MuseLogLine('error', 'boom', now)],
      );
      expect(find.textContaining('hello world', findRichText: true), findsOneWidget);
      await t.tap(find.text('错误'));
      await t.pump();
      expect(find.textContaining('hello world', findRichText: true), findsNothing);
      expect(find.textContaining('boom', findRichText: true), findsOneWidget);
      await done(t);
    });
  });
}
