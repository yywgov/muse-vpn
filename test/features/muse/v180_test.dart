// 穿云 1.8.0: DNS 查询视图 + 活动 (连接 / 日志 / DNS). Parsing, labels, filtering, the buffer, the
// stream only while the DNS tab is visible, tab switches ending the stream left behind, the
// 兼容内核 fallback, routes / entries and the release numbers.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/activity/activity_page.dart';
import 'package:hiddify/features/muse/activity/dns_view.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/dns_queries.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _q(
  int id,
  String domain, {
  String server = 'dns-direct',
  String serverType = 'udp',
  String address = '223.5.5.5',
  List<String> answers = const ['1.2.3.4'],
  bool cached = false,
  double elapsed = 12.4,
  String rcode = 'NOERROR',
  String error = '',
  String group = '',
}) => {
  'id': id,
  'time': 1761955200000 + id,
  'domain': domain,
  'type': 'A',
  'server': server,
  'serverType': serverType,
  'address': address,
  if (group.isNotEmpty) 'group': group,
  'answers': answers,
  'rcode': rcode,
  'elapsed': elapsed,
  'cached': cached,
  if (error.isNotEmpty) 'error': error,
};

MuseDnsQuery _m(int id, String domain, {String server = 'dns-direct', String serverType = 'udp', String address = '223.5.5.5', bool cached = false, List<String> answers = const ['1.2.3.4']}) =>
    MuseDnsQuery.fromJson(_q(id, domain, server: server, serverType: serverType, address: address, cached: cached, answers: answers))!;

void main() {
  group('parsing', () {
    test('a frame is a JSON array of queries; every field is read', () {
      final list = museParseDnsFrame(jsonEncode([
        _q(7, 'www.baidu.com', cached: true, elapsed: 0.3),
        _q(8, 'www.google.com', server: 'dns-remote', serverType: 'tcp', address: 'tcp://8.8.8.8', answers: ['142.250.1.1', '2404:6800::1']),
      ]));
      expect(list, hasLength(2));
      final a = list.first;
      expect(a.id, 7);
      expect(a.domain, 'www.baidu.com');
      expect(a.type, 'A');
      expect(a.server, 'dns-direct');
      expect(a.address, '223.5.5.5');
      expect(a.answers, ['1.2.3.4']);
      expect(a.cached, isTrue);
      expect(a.elapsedMs, 0.3);
      expect(a.time, DateTime.fromMillisecondsSinceEpoch(1761955200007));
      expect(list[1].answers, ['142.250.1.1', '2404:6800::1']);
      expect(list[1].failed, isFalse);
    });

    test('bad entries are skipped, a bad frame is empty', () {
      expect(museParseDnsFrame(jsonEncode([{'id': 1}, 'x', 3, _q(2, 'ok.cn')])).map((e) => e.domain), ['ok.cn']);
      expect(museParseDnsFrame('not json'), isEmpty);
      expect(museParseDnsFrame('{"domain":"a"}'), isEmpty);
      expect(museParseDnsFrame('[]'), isEmpty);
      final missing = MuseDnsQuery.fromJson({'domain': 'a.cn'})!;
      expect(missing.answers, isEmpty);
      expect(missing.cached, isFalse);
      expect(missing.elapsedMs, 0);
    });

    test('labels: which DNS, answers, time, failures', () {
      expect(museDnsServerLabel(_m(1, 'a')), '223.5.5.5');
      expect(museDnsServerLabel(_m(1, 'a', server: 'dns-direct-group-1', serverType: 'tcp', address: 'tcp://119.29.29.29')), 'tcp://119.29.29.29');
      expect(museDnsServerLabel(_m(1, 'a', server: 'dns-remote', serverType: 'https', address: 'https://8.8.8.8')), '远程 DNS（https://8.8.8.8）');
      expect(museDnsServerLabel(_m(1, 'a', server: 'dns-remote', address: '')), '远程 DNS');
      expect(museDnsServerLabel(_m(1, 'a', server: 'dns-fake', serverType: 'fakeip', address: '')), 'Fake-IP');
      expect(museDnsServerLabel(_m(1, 'a', server: 'dns-local', serverType: 'local', address: '')), '系统 DNS');
      expect(museDnsServerLabel(_m(1, 'a', server: 'dns-static', serverType: 'hosts', address: '')), '静态解析');
      expect(museDnsServerLabel(_m(1, 'a', server: 'my-dns', serverType: 'x', address: 'udp://9.9.9.9')), '9.9.9.9');
      final group = MuseDnsQuery.fromJson(_q(1, 'a', server: 'dns-remote-group-1', group: 'dns-remote-group', address: 'tcp://1.1.1.1'))!;
      expect(museDnsServerLabel(group), '远程 DNS（tcp://1.1.1.1）');

      expect(museDnsAnswerText(_m(1, 'a', answers: ['1.1.1.1', '2.2.2.2'])), '1.1.1.1  2.2.2.2');
      expect(museDnsAnswerText(MuseDnsQuery.fromJson(_q(1, 'a', answers: [], rcode: 'NXDOMAIN'))!), '域名不存在');
      expect(museDnsAnswerText(MuseDnsQuery.fromJson(_q(1, 'a', answers: []))!), '无地址');
      final failed = MuseDnsQuery.fromJson(_q(1, 'a', answers: [], rcode: '', error: 'context deadline exceeded'))!;
      expect(failed.failed, isTrue);
      expect(museDnsAnswerText(failed), '失败：超时');

      expect(museDnsElapsedText(MuseDnsQuery.fromJson(_q(1, 'a', elapsed: 0.2))!), '<1 ms');
      expect(museDnsElapsedText(MuseDnsQuery.fromJson(_q(1, 'a', elapsed: 35.6))!), '36 ms');
      expect(museDnsElapsedText(MuseDnsQuery.fromJson(_q(1, 'a', elapsed: 2500))!), '2.5 s');
      final copy = museDnsCopyText(_m(1, 'www.qq.com', cached: true));
      expect(copy, contains('www.qq.com A'));
      expect(copy, contains('1.2.3.4'));
      expect(copy, contains('223.5.5.5，缓存'));
    });
  });

  group('filter and buffer', () {
    final items = [
      _m(1, 'www.baidu.com'),
      _m(2, 'www.google.com', server: 'dns-remote', address: 'tcp://8.8.8.8', answers: ['142.250.1.1']),
      _m(3, 'www.baidu.com', cached: true),
      _m(4, 'img.baidu.com', answers: ['5.6.7.8']),
    ];

    test('newest first; search matches domain, address or DNS; domain filter is exact', () {
      expect(museFilterDns(items).map((e) => e.id), [4, 3, 2, 1]);
      expect(museFilterDns(items, query: 'BAIDU').map((e) => e.id), [4, 3, 1]);
      expect(museFilterDns(items, query: '142.250').map((e) => e.id), [2]);
      expect(museFilterDns(items, query: '远程').map((e) => e.id), [2]);
      expect(museFilterDns(items, domain: 'www.baidu.com').map((e) => e.id), [3, 1]);
      expect(museFilterDns(items, domain: 'www.baidu.com', query: 'img'), isEmpty);
      expect(museFilterDns(items, query: '  '), hasLength(4));
    });

    test('a new socket replaces the list; later frames append once; capacity holds', () {
      final b = MuseDnsBuffer(capacity: 3);
      b.reset([items[0], items[1]]);
      b.addAll([items[1], items[2]]); // 2 again is dropped
      expect(b.items.map((e) => e.id), [1, 2, 3]);
      b.addAll([items[3]]);
      expect(b.items.map((e) => e.id), [2, 3, 4]);
      b.reset([_m(1, 'after.restart')]); // the core restarted: ids start over
      expect(b.items.map((e) => e.domain), ['after.restart']);
      b.clear();
      expect(b.length, 0);
      expect(museDnsCapacity, 500);
      expect(MuseDnsBuffer().capacity, 500);
    });
  });

  group('stream', () {
    test('兼容内核: unsupported, no socket; disconnected: 未连接', () async {
      final c = ProviderContainer(overrides: [museRunningCoreKindProvider.overrideWithValue(MuseCoreKind.compat)]);
      addTearDown(c.dispose);
      final sub = c.listen(museDnsQueriesProvider, (_, _) {});
      final s = await c.read(museDnsQueriesProvider.future);
      expect(s.unsupported, isTrue);
      sub.close();

      final d = ProviderContainer(
        overrides: [
          museRunningCoreKindProvider.overrideWithValue(MuseCoreKind.standard),
          museLocalApiProvider.overrideWithValue(null),
        ],
      );
      addTearDown(d.dispose);
      final sub2 = d.listen(museDnsQueriesProvider, (_, _) {});
      final s2 = await d.read(museDnsQueriesProvider.future);
      expect(s2.unsupported, isFalse);
      expect(s2.error, '未连接');
      sub2.close();
    });

    test('the WebSocket is open only while someone watches; snapshot first, then live batches; 清空 hits the core', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var opened = 0;
      var deletes = 0;
      final closed = Completer<void>();
      final live = Completer<WebSocket>();
      server.listen((req) async {
        if (req.uri.path != '/dns/queries') {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        if (req.method == 'DELETE') {
          deletes++;
          req.response.statusCode = 204;
          await req.response.close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(req);
        opened++;
        ws.add(jsonEncode([_q(1, 'snap.cn')]));
        live.complete(ws);
        ws.listen((_) {}, onDone: () {
          if (!closed.isCompleted) closed.complete();
        });
      });
      final api = MuseLocalApi(port: server.port, secret: '');
      addTearDown(api.close);
      final c = ProviderContainer(
        overrides: [
          museRunningCoreKindProvider.overrideWithValue(MuseCoreKind.standard),
          museLocalApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(c.dispose);
      final states = <MuseDnsState>[];
      final sub = c.listen(museDnsQueriesProvider, (_, n) {
        if (n.valueOrNull != null) states.add(n.value!);
      });
      final ws = await live.future.timeout(const Duration(seconds: 5));
      await _until(() => states.any((s) => s.queries.length == 1));
      expect(states.last.queries.single.domain, 'snap.cn');
      ws.add(jsonEncode([_q(2, 'live1.cn'), _q(3, 'live2.cn', cached: true)]));
      await _until(() => states.last.queries.length == 3);
      expect(states.last.queries.map((e) => e.domain), ['snap.cn', 'live1.cn', 'live2.cn']);
      expect(c.read(museDnsBufferProvider).length, 3);
      expect(opened, 1);

      // nobody watching -> the socket closes right away (no grace period for DNS)
      sub.close();
      await closed.future.timeout(const Duration(seconds: 3));

      // (the widget-test binding fakes plain HTTP; use a real client for this request)
      await HttpOverrides.runWithHttpOverrides(() async {
        final real = MuseLocalApi(port: server.port, secret: '');
        try {
          expect(await real.clearDnsQueries(), isTrue);
        } finally {
          real.close();
        }
      }, _RealHttp());
      expect(deletes, 1);
    });

    test('invalidating a stream left by a tab ends it now, not after the grace period', () {
      fakeAsync((async) {
        var disposed = 0;
        final p = Provider.autoDispose<int>((ref) {
          museKeepFor(ref, museStreamGrace);
          ref.onDispose(() => disposed++);
          return 1;
        });
        final c = ProviderContainer();
        c.listen(p, (_, _) {}).close();
        async.elapse(const Duration(seconds: 1));
        expect(disposed, 0, reason: 'grace when leaving the page');
        c.invalidate(p);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        expect(disposed, 1);
        expect(c.exists(p), isFalse);
        c.dispose();
      });
    });
  });

  group('活动 page', () {
    Future<(ProviderContainer, Map<String, int>, Map<String, int>)> pump(WidgetTester t, {MuseActivityTab initial = MuseActivityTab.connections, MuseCoreKind kind = MuseCoreKind.standard}) async {
      SharedPreferences.setMockInitialValues({'muse_log_capture': true});
      final sp = await SharedPreferences.getInstance();
      final created = <String, int>{'conn': 0, 'logs': 0, 'dns': 0};
      final disposed = <String, int>{'conn': 0, 'logs': 0, 'dns': 0};
      void track(Ref ref, String k) {
        created[k] = created[k]! + 1;
        ref.onDispose(() => disposed[k] = disposed[k]! + 1);
      }

      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
          museRunningProvider.overrideWithValue(true),
          museLocalApiProvider.overrideWithValue(null),
          museRunningCoreKindProvider.overrideWithValue(kind),
          museConnectionsProvider.overrideWith((ref) {
            track(ref, 'conn');
            return Stream.value(const MuseConnState());
          }),
          museLogsProvider.overrideWith((ref) {
            track(ref, 'logs');
            return Stream.value(const <MuseLogLine>[]);
          }),
          if (kind == MuseCoreKind.standard)
            museDnsQueriesProvider.overrideWith((ref) {
              track(ref, 'dns');
              return Stream.value(MuseDnsState(queries: [_m(1, 'www.baidu.com'), _m(2, 'www.google.com', server: 'dns-remote', address: 'tcp://8.8.8.8'), _m(3, 'www.baidu.com', cached: true)]));
            }),
        ],
      );
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(sharedPreferencesProvider.future));
      t.view.physicalSize = const Size(412, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)), home: MuseActivityPage(initial: initial)),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      return (c, created, disposed);
    }

    Future<void> tapTab(WidgetTester t, String title) async {
      await t.tap(find.descendant(of: find.byKey(const ValueKey('activity_tabs')), matching: find.text(title)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    testWidgets('only the visible tab streams; leaving a tab ends its stream at once', (t) async {
      final (c, created, disposed) = await pump(t);
      expect(find.text('活动'), findsWidgets);
      expect(created, {'conn': 1, 'logs': 0, 'dns': 0});
      expect(c.exists(museDnsQueriesProvider), isFalse);

      await tapTab(t, 'DNS');
      expect(created['dns'], 1);
      expect(disposed['conn'], 1, reason: 'connections ended when its tab was left');
      expect(c.exists(museConnectionsProvider), isFalse);
      expect(find.byKey(const ValueKey('dns_list')), findsOneWidget);

      await tapTab(t, '日志');
      expect(created['logs'], 1);
      expect(disposed['dns'], 1);
      expect(c.exists(museDnsQueriesProvider), isFalse);

      await tapTab(t, '连接');
      expect(created['conn'], 2);
      expect(disposed['logs'], 1);
      expect(c.exists(museLogsProvider), isFalse);

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('DNS: rows show domain, DNS, address, cache; search and long-press domain filter', (t) async {
      await pump(t, initial: MuseActivityTab.dns);
      expect(find.text('远程 DNS（tcp://8.8.8.8）'), findsOneWidget);
      expect(find.text('223.5.5.5'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('dns_cached')), findsOneWidget);
      expect(find.byType(MuseDnsRow), findsNWidgets(3));

      await t.enterText(find.byKey(const ValueKey('dns_search')), 'google');
      await t.pump();
      expect(find.byType(MuseDnsRow), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('dns_search')), '');
      await t.pump();

      await t.longPress(find.byType(MuseDnsRow).first);
      await t.pump();
      expect(find.byKey(const ValueKey('dns_domain_filter')), findsOneWidget);
      expect(find.byType(MuseDnsRow), findsNWidgets(2));
      await t.tap(find.descendant(of: find.byKey(const ValueKey('dns_domain_filter')), matching: find.byIcon(Icons.clear)));
      await t.pump();
      expect(find.byType(MuseDnsRow), findsNWidgets(3));

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('兼容内核: DNS says 当前内核不支持 and opens no stream', (t) async {
      final (c, _, _) = await pump(t, initial: MuseActivityTab.dns, kind: MuseCoreKind.compat);
      expect(find.textContaining(museDnsUnsupportedText), findsOneWidget);
      expect(find.byKey(const ValueKey('dns_search')), findsNothing);
      expect(c.read(museDnsQueriesProvider).valueOrNull?.unsupported, isTrue);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });
  });

  group('entries and release', () {
    test('tabs by key; old locations and 设置 search open the right tab', () {
      expect(MuseActivityTab.fromKey('dns'), MuseActivityTab.dns);
      expect(MuseActivityTab.fromKey('logs'), MuseActivityTab.logs);
      expect(MuseActivityTab.fromKey(null), MuseActivityTab.connections);
      expect(museActivityLocation(MuseActivityTab.dns), '/settings/activity?tab=dns');
      final routes = File('lib/core/router/go_router/routing_config_notifier.dart').readAsStringSync();
      expect(routes, contains("_slide(museActivityRoute, 'activity'"));
      expect(routes, contains("GoRoute(name: 'connections', path: 'connections', redirect: (_, _) => museActivityLocation(MuseActivityTab.connections))"));
      expect(routes, contains("GoRoute(name: 'logs', path: 'logs', redirect: (_, _) => museActivityLocation(MuseActivityTab.logs))"));
      expect(museShellExtras(logCapture: true, logsAvailable: true).map((e) => e.title), ['活动']);
      expect(museShellActivity.path, museActivityPath);

      final byTitle = {for (final e in museSettingEntries) e.title: e};
      for (final t in ['活动', '连接', '日志', 'DNS 查询']) {
        expect(byTitle[t]?.page, MuseSettingPage.activity, reason: t);
      }
      expect(museActivityTabForSetting('日志'), MuseActivityTab.logs);
      expect(museActivityTabForSetting('DNS 查询'), MuseActivityTab.dns);
      expect(museActivityTabForSetting('连接'), MuseActivityTab.connections);
      expect(museSearchSettings('DNS 查询', android: true, windows: false).map((e) => e.title), contains('DNS 查询'));

      final settings = File('lib/features/settings/overview/settings_page.dart').readAsStringSync();
      expect(settings, contains("ValueKey('settings_activity')"));
      expect(settings, contains('case MuseSettingPage.activity:'));
      expect(settings.contains("goNamed('connections')") || settings.contains("goNamed('logs')"), isFalse);
      final home = File('lib/features/muse/home/dashboard_cards.dart').readAsStringSync();
      expect(home, contains('museActivityLocation(MuseActivityTab.connections)'));
    });

    test('no new timers or polling; DNS stream has no grace period', () {
      final providers = File('lib/features/muse/local_api/local_api_providers.dart').readAsStringSync();
      final dns = providers.substring(providers.indexOf('final museDnsQueriesProvider'), providers.indexOf('/// 清空'));
      expect(dns.contains('museKeepFor'), isFalse);
      for (final f in ['lib/features/muse/activity/activity_page.dart', 'lib/features/muse/activity/dns_view.dart', 'lib/features/muse/local_api/dns_queries.dart']) {
        final s = File(f).readAsStringSync();
        expect(s.contains('Timer'), isFalse, reason: f);
        expect(s.contains('periodic'), isFalse, reason: f);
        expect(s.contains('AnimationController'), isFalse, reason: f);
      }
    });

    test('new files do not name upstream projects', () {
      for (final p in [
        'lib/features/muse/activity/activity_page.dart',
        'lib/features/muse/activity/dns_view.dart',
        'lib/features/muse/local_api/dns_queries.dart',
      ]) {
        final s = File(p).readAsLinesSync().where((l) => !l.startsWith('import ')).join('\n').toLowerCase();
        for (final w in ['flclash', 'clash', 'hiddify', 'sing-box', 'singbox', 'mihomo']) {
          expect(s.contains(w), isFalse, reason: '$p: $w');
        }
      }
    });

    test('1.8.0 notes kept, core 5.0.0-muse.19, 兼容内核 source pinned, 更新说明 and CHANGELOG', () {
      expect(museChangelog.keys, contains('1.8.0'));
      expect(museChangelog['1.8.0'], hasLength(3));
      final props = File('dependencies.properties').readAsStringSync();
      // 1.10.0: standard core 5.0.0-muse.20 (Go 1.26.10); 1.10.3: muse.21 (测速 on congested lines)
      expect(RegExp(r'muse\.core\.version=(\S+)').firstMatch(props)?.group(1), museCoreRelease);
      expect(museCoreRelease, '5.0.0-muse.21');
      expect(props, matches(RegExp(r'muse\.compat\.ref=[0-9a-f]{40}')));
      final md = File('CHANGELOG.md').readAsStringSync();
      expect(md.indexOf('### 1.8.0'), lessThan(md.indexOf('### 1.7.1')));
    });
  });
}

class _RealHttp extends HttpOverrides {}

Future<void> _until(bool Function() ok, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
