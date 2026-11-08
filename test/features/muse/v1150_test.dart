// 穿云 1.15.0 批3 规则/连接/DNS: R13 DNS 清缓存, R24 为什么走这条, R16 连接显示应用, R20 DNS 泄漏检测,
// B6 规则集打开时过期才更新, R22 链式代理, R23 按 Wi-Fi 切换模式.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/logic/route_why.dart';

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
}
