// 穿云 1.15.0 批3 规则/连接/DNS: R13 DNS 清缓存, R24 为什么走这条, R16 连接显示应用, R20 DNS 泄漏检测,
// B6 规则集打开时过期才更新, R22 链式代理, R23 按 Wi-Fi 切换模式.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/connections/conn_app.dart';
import 'package:hiddify/features/muse/connections/connections_page.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/logic/dns_leak.dart';
import 'package:hiddify/features/muse/logic/route_why.dart';
import 'package:hiddify/features/muse/settings/dns_leak_card.dart';
import 'dart:async';
import 'dart:math';

String _src(String p) => File(p).readAsStringSync();

MuseConn _conn({String rule = '', List<String> chains = const [], String process = ''}) => MuseConn(
  id: '1',
  host: 'www.example.com',
  destination: '1.2.3.4:443',
  network: 'tcp',
  inbound: 'tun',
  chains: chains,
  rule: rule,
  process: process,
  upload: 0,
  download: 0,
  start: DateTime(2026),
);

void main() {
  group('R13 DNS 清缓存', () {
    test('POST /cache/dns/flush with the secret', () async {
      final saved = HttpOverrides.current;
      HttpOverrides.global = null; // the widget binding fakes HttpClient
      addTearDown(() => HttpOverrides.global = saved);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? seen;
      String? auth;
      server.listen((r) {
        seen = '${r.method} ${r.uri.path}';
        auth = r.headers.value(HttpHeaders.authorizationHeader);
        r.response.statusCode = 204;
        r.response.close();
      });
      final api = MuseLocalApi(port: server.port, secret: 's');
      expect(await api.flushDnsCache(), isTrue);
      expect(seen, 'POST /cache/dns/flush');
      expect(auth, 'Bearer s');
      api.close();
      await server.close(force: true);
    });

    test('DNS 页有按钮，只在点按时调用，中文提示', () {
      final s = _src('lib/features/muse/activity/dns_view.dart');
      expect(s, contains("ValueKey('dns_flush_cache')"));
      expect(s, contains("tooltip: '清空 DNS 缓存'"));
      expect(s, contains('清空失败，内核暂不可用'));
      expect(s, contains('连接后才能清空 DNS 缓存'));
    });
  });

  group('R24 为什么走这条', () {
    test('标准内核：规则集 → 代理组 → 节点', () {
      final w = museRouteWhy(_conn(rule: 'rule_set=[geosite-google] => route(节点选择)', chains: ['香港 01', '节点选择']));
      expect(w.rule, '规则集 geosite-google');
      expect(w.outbound, '节点选择');
      expect(w.node, '香港 01');
      expect(w.summary, contains('实际经节点「香港 01」'));
    });

    test('直连、默认、拦截、组合条件、取反', () {
      final d = museRouteWhy(_conn(rule: 'domain_suffix=[.cn] => route(direct)', chains: ['direct']));
      expect(d.rule, '域名后缀 .cn');
      expect(d.outbound, '直连');
      expect(d.node, '');
      expect(museRouteWhy(_conn(rule: 'final', chains: ['select'])).rule, '未命中规则（默认出站）');
      expect(museRouteWhy(_conn(rule: 'domain=[ad.example.com] => reject')).summary, contains('已拦截'));
      expect(museRuleText('network=udp port=443 => reject'), '网络类型 udp 且 端口 443');
      expect(museRuleText('!(ip_is_private=true) => route(x)'), '不符合（局域网地址）');
      expect(museRuleText('domain_suffix=[a.com b.com c.com d.com] => route(x)'), '域名后缀 a.com、b.com、c.com 等 4 项');
    });

    test('兼容内核：RuleSet(payload) / Match', () {
      expect(museRouteWhy(_conn(rule: 'RuleSet(geosite-cn)', chains: ['DIRECT'])).rule, '规则集 geosite-cn');
      expect(museRouteWhy(_conn(rule: 'Match', chains: ['a', 'Proxy'])).rule, '未命中规则（默认出站）');
      expect(museRouteWhy(_conn(rule: 'DomainSuffix(google.com)', chains: ['a', 'b', 'c'])).summary, contains('经 b'));
    });

    test('连接详情显示「为什么走这条」', () {
      final s = _src('lib/features/muse/connections/connections_page.dart');
      expect(s, contains("ValueKey('conn_why')"));
      expect(s, contains("title: '为什么走这条'"));
      expect(s, contains("kv('命中规则', why.rule)"));
    });
  });

  group('R16 连接显示应用', () {
    test('进程字段 → 包名 / 程序名', () {
      expect(museProcessPackage('com.tencent.mm (10123)'), 'com.tencent.mm');
      expect(museProcessPackage('com.android.chrome'), 'com.android.chrome');
      expect(museProcessPackage(r'C:\Program Files\Google\chrome.exe'), isNull);
      expect(museProcessPackage('chrome.exe'), isNull);
      expect(museProcessPackage('10123'), isNull);
      final labels = museParseAppLabels('[{"package-name":"com.tencent.mm","name":"微信","is-system-app":false},{"package-name":"x.y","name":"null"}]');
      expect(labels, {'com.tencent.mm': '微信'});
      expect(museParseAppLabels('坏'), isEmpty);
      final a = museConnApp('com.tencent.mm (10123)', labels)!;
      expect((a.name, a.package), ('微信', 'com.tencent.mm'));
      expect(museConnApp('com.example.x', labels)!.name, 'com.example.x');
      expect(museConnApp(r'C:\Apps\chrome.exe', labels)!.name, 'chrome.exe');
      expect(museConnApp('10123', labels), isNull);
      expect(museConnApp('', labels), isNull);
    });

    test('图标缓存有上限，最近用过的留下', () {
      final c = MuseLru<String, int>(2)
        ..put('a', 1)
        ..put('b', 2);
      expect(c.get('a'), 1);
      c.put('c', 3);
      expect(c.get('b'), isNull);
      expect(c.get('a'), 1);
      expect(c.length, 2);
      expect(museAppIconCacheMax, lessThanOrEqualTo(64));
    });

    testWidgets('连接行显示应用名与图标，详情显示「应用」', (t) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final conns = [
        MuseConn.fromJson({
          'id': 'a',
          'metadata': {'network': 'tcp', 'type': 'tun', 'destinationIP': '1.2.3.4', 'destinationPort': '443', 'host': 'weixin.qq.com', 'processPath': 'com.tencent.mm (10123)'},
          'upload': 1,
          'download': 2,
          'start': '2026-11-08T09:00:00+08:00',
          'chains': ['direct'],
          'rule': 'rule_set=[geosite-cn] => route(direct)',
          'rulePayload': '',
        })!,
        MuseConn.fromJson({
          'id': 'b',
          'metadata': {'network': 'tcp', 'type': 'tun', 'destinationIP': '1.2.3.5', 'destinationPort': '443', 'host': 'no-app.example.com'},
          'chains': ['direct'],
          'rule': 'final',
        })!,
      ];
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => sp),
          museRunningProvider.overrideWithValue(true),
          museConnectionsProvider.overrideWith((ref) => Stream.value(MuseConnState(connections: conns))),
          museConnAppsEnabledProvider.overrideWithValue(true),
          museAppLabelsProvider.overrideWith((ref) async => {'com.tencent.mm': '微信'}),
          museAppIconProvider.overrideWith((ref, pkg) async => null),
        ],
      );
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(sharedPreferencesProvider.future));
      t.view.physicalSize = const Size(412, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)), home: const MuseConnectionsPage()),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('微信 · direct'), findsOneWidget);
      expect(find.byType(MuseConnAppIcon), findsOneWidget); // 没有进程信息的连接不显示图标
      await t.tap(find.text('weixin.qq.com'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('conn_why')), findsOneWidget);
      expect(find.text('应用'), findsOneWidget);
      expect(find.text('规则集 geosite-cn'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
    });

    test('只在 Android 读应用信息，页面离开即释放', () {
      final s = _src('lib/features/muse/connections/conn_app.dart');
      expect(s, contains('Platform.isAndroid'));
      expect(s, contains('FutureProvider.autoDispose<Map<String, String>>'));
      expect(s, contains('FutureProvider.autoDispose.family<Uint8List?, String>'));
      expect(s, isNot(contains('Timer.periodic')));
    });
  });

  group('R20 DNS 泄漏检测', () {
    test('随机子域名、结论', () {
      final h = museDnsLeakHost(Random(1));
      expect(h, matches(RegExp(r'^[0-9a-f]{32}\.edns\.ip-api\.com$')));
      expect(museDnsLeakHost(), isNot(h));
      expect(museDnsLeakUrl(h), 'http://$h/json');
      final leak = museParseDnsLeak('{"dns":{"geo":"China - Chinanet","ip":"202.96.1.1"}}', connected: true);
      expect(leak.verdict, MuseDnsLeakVerdict.leak);
      expect(leak.text, contains('运营商'));
      final safe = museParseDnsLeak('{"dns":{"geo":"Japan - Google LLC","ip":"74.125.1.1"},"edns":{}}', connected: true);
      expect(safe.verdict, MuseDnsLeakVerdict.safe);
      expect(safe.resolverIp, '74.125.1.1');
      // 香港不是大陆
      expect(museParseDnsLeak('{"dns":{"geo":"Hong Kong - X","ip":"1.1.1.1"}}', connected: true).verdict, MuseDnsLeakVerdict.safe);
      expect(museParseDnsLeak('{"dns":{"geo":"China - X","ip":"1.1.1.1"}}', connected: false).verdict, MuseDnsLeakVerdict.unknown);
      final bad = museParseDnsLeak('<html>', connected: true);
      expect(bad.failed, isTrue);
      expect(bad.error, '检测服务返回了无法识别的结果');
    });

    test('失败显示中文原因', () async {
      expect(museDnsLeakErrorText(TimeoutException('x')), '检测超时，请检查网络后重试');
      expect(museDnsLeakErrorText(const SocketException('x')), '无法连接检测服务，请稍后重试');
      final r = await museRunDnsLeakTest(port: 1, connected: true, get: (_, _) async => throw const SocketException('x'));
      expect(r.failed, isTrue);
      expect(r.text, '无法连接检测服务，请稍后重试');
      String? url;
      final ok = await museRunDnsLeakTest(port: 7890, connected: true, get: (u, p) async {
        url = u;
        return '{"dns":{"geo":"United States - Cloudflare","ip":"172.64.1.1"}}';
      });
      expect(url, startsWith('http://'));
      expect(ok.verdict, MuseDnsLeakVerdict.safe);
    });

    testWidgets('诊断里点按才测', (t) async {
      var calls = 0;
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MuseDnsLeakCard(run: () async {
              calls++;
              return museParseDnsLeak('{"dns":{"geo":"China - Chinanet","ip":"202.96.1.1"}}', connected: true);
            }),
          ),
        ),
      ));
      expect(calls, 0);
      expect(find.text('开始检测'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('dns_leak_start')));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('DNS 泄漏检测：可能泄漏'), findsOneWidget);
      expect(find.text('重新检测'), findsOneWidget);
      expect(_src('lib/features/muse/settings/diagnose_sheet.dart'), contains('const MuseDnsLeakCard()'));
      expect(_src('lib/features/muse/logic/dns_leak.dart'), isNot(contains('Timer')));
    });
  });
}
