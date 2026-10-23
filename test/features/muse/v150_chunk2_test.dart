// 穿云 1.5.0 (batch 1, chunk 2) logic: IPv6 policy, Fake-IP exclusions, 局域网 rule pinned first,
// settings applied once changes stop, core log tail, 测速 progress, node details, download speed,
// subscription fetch mode / preview / errors / traffic from entry names / per-subscription
// filters, Clash / Surge rule conversion.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';

Rule _r(String name, {Outbound o = Outbound.proxy, int order = 0, bool enabled = true}) =>
    Rule(name: name, outbound: o, listOrder: order, enabled: enabled, domainSuffixes: ['$name.com']);

void main() {
  group('#7 IPv6 policy', () {
    test('关闭 keeps the saved values; 优先 v4 / v6 set the tunnel and DNS', () {
      expect(museIpv6Options(MuseIpv6Policy.off), isNull);
      expect(museIpv6Options(MuseIpv6Policy.preferV4), (mode: IPv6Mode.enable, strategy: DomainStrategy.preferIpv4));
      expect(museIpv6Options(MuseIpv6Policy.preferV6), (mode: IPv6Mode.prefer, strategy: DomainStrategy.preferIpv6));
      expect(MuseIpv6Policy.fromKey('nonsense'), MuseIpv6Policy.off);
      expect([for (final p in MuseIpv6Policy.values) p.title], ['关闭', '优先 IPv4', '优先 IPv6']);
    });
  });

  group('#57 局域网 rule', () {
    test('pinned first and switched on, whatever the saved order', () {
      final rules = [_r('mine', order: 0), _r('preset', order: 1), _r(museLanRuleName, o: Outbound.direct, order: 2, enabled: false)];
      final out = musePinLanRule(rules);
      expect(out.map((e) => e.name), [museLanRuleName, 'mine', 'preset']);
      expect(out.first.enabled, isTrue);
      expect(out.map((e) => e.listOrder), [0, 1, 2]);
      // the input is not changed
      expect(rules[2].enabled, isFalse);
    });
    test('a list without it is unchanged', () {
      final rules = [_r('a'), _r('b', order: 1)];
      expect(identical(musePinLanRule(rules), rules), isTrue);
    });
  });

  group('#14 Fake-IP exclusions', () {
    test('only when on, right after the 局域网 rule, direct', () {
      final rules = musePinLanRule([_r('mine'), _r(museLanRuleName, o: Outbound.direct, order: 1)]);
      expect(museApplyFakeIpExclusions(rules, fakeIp: false), same(rules));
      final out = museApplyFakeIpExclusions(rules, fakeIp: true);
      expect(out.map((e) => e.name), [museLanRuleName, museFakeIpExcludeRuleName, 'mine']);
      expect(out[1].outbound, Outbound.direct);
      expect(out[1].domainSuffixes, containsAll(['lan', 'local', 'pool.ntp.org', 'msftconnecttest.com', 'time.android.com']));
      expect(out.map((e) => e.listOrder), [0, 1, 2]);
    });
  });

  group('#56 settings applied once changes stop', () {
    testWidgets('a quick series runs once, with the last change', (tester) async {
      final d = MuseDebouncer(const Duration(milliseconds: 400));
      final runs = <int>[];
      for (var i = 1; i <= 3; i++) {
        d(() => runs.add(i));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(runs, isEmpty);
      expect(d.pending, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(runs, [3]);
      d(() => runs.add(9));
      d.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(runs, [3]);
    });
  });

  group('#15 core log tail', () {
    test('newest 200 lines', () {
      final lines = [for (var i = 0; i < 450; i++) 'line $i'];
      final tail = museTailLines(lines);
      expect(tail.length, 200);
      expect(tail.first, 'line 250');
      expect(tail.last, 'line 449');
      expect(museTailLines(['a', 'b']), ['a', 'b']);
    });
  });

  group('#25 测速 progress', () {
    test('answers since the run started', () {
      final start = DateTime(2026, 10, 23, 22);
      final p = museTestProgress([null, start.subtract(const Duration(minutes: 5)), start.add(const Duration(seconds: 2)), start], start);
      expect(p, (done: 2, total: 4));
      expect(museTestProgress(const [], start), (done: 0, total: 0));
    });
  });

  group('#26 / #10 node details from the saved config', () {
    final config = jsonEncode({
      'outbounds': [
        {
          'type': 'vless',
          'tag': '🇯🇵 东京 02',
          'server': 'jp.example.com',
          'server_port': 443,
          'flow': 'xtls-rprx-vision',
          'tls': {
            'enabled': true,
            'server_name': 'www.apple.com',
            'utls': {'enabled': true, 'fingerprint': 'chrome'},
            'reality': {'enabled': true, 'public_key': 'x'},
          },
        },
        {
          'type': 'vmess',
          'tag': 'ws node',
          'server': 'ws.example.com',
          'server_port': 8443,
          'transport': {'type': 'ws', 'path': '/'},
          'tls': {'enabled': true, 'server_name': 'ws.example.com', 'alpn': ['h2', 'http/1.1'], 'insecure': true},
        },
        {
          'type': 'hysteria2',
          'tag': '🇭🇰 香港 01',
          'server': 'hk.example.com',
          'server_port': 443,
          'server_ports': ['20000:30000'],
          'up_mbps': 50,
          'down_mbps': 200,
          'tls': {'enabled': true, 'server_name': 'hk.example.com', 'alpn': ['h3']},
        },
      ],
    });
    test('REALITY + vision + fingerprint', () {
      final d = museOutboundDetail(config, '🇯🇵 东京 02')!;
      expect(d.tls, 'REALITY');
      expect(d.fingerprint, 'chrome');
      expect(d.flow, 'xtls-rprx-vision');
      expect(d.rows.map((e) => e.$1), ['安全', 'SNI', '指纹', '流控']);
    });
    test('transport, ALPN, skipped certificate check', () {
      final d = museOutboundDetail(config, 'ws node')!;
      expect(d.transport, 'WebSocket');
      expect(d.tls, 'TLS（跳过证书验证）');
      expect(d.alpn, ['h2', 'http/1.1']);
    });
    test('Hysteria2 port hopping and bandwidth', () {
      final d = museOutboundDetail(config, '🇭🇰 香港 01')!;
      expect(d.transport, 'QUIC');
      expect(d.ports, '20000-30000');
      expect(d.bandwidth, '↑ 50 · ↓ 200 Mbps');
    });
    test('found by address when the tag differs; garbage never throws', () {
      expect(museOutboundDetail(config, 'renamed', host: 'ws.example.com', port: 8443)?.transport, 'WebSocket');
      expect(museOutboundDetail(config, 'missing'), isNull);
      expect(museOutboundDetail('not json', 'x'), isNull);
      expect(museOutboundDetail('[]', 'x'), isNull);
      expect(museOutboundDetail('{"outbounds": [1, "a", null]}', 'x'), isNull);
    });
  });

  group('#24 download speed text', () {
    test('MB/s with Mbps, KB/s below 1 MB/s', () {
      expect(museSpeedText(0), '—');
      expect(museSpeedText(5 * 1024 * 1024), '5.0 MB/s（42 Mbps）');
      expect(museSpeedText(12.5 * 1024 * 1024), '13 MB/s（105 Mbps）');
      expect(museSpeedText(300 * 1024), '300 KB/s（2.5 Mbps）');
    });
  });

  group('#41 subscription fetch mode', () {
    test('auto = proxy then direct when connected; 走代理 needs the port', () {
      expect(museSubFetchMode(MuseSubFetch.auto, proxyUp: true), 'both');
      expect(museSubFetchMode(MuseSubFetch.auto, proxyUp: false), 'direct');
      expect(museSubFetchMode(MuseSubFetch.proxy, proxyUp: true), 'proxy');
      expect(museSubFetchMode(MuseSubFetch.proxy, proxyUp: false), 'direct');
      expect(museSubFetchMode(MuseSubFetch.direct, proxyUp: true), 'direct');
      expect(MuseSubFetch.fromKey('x'), MuseSubFetch.auto);
    });
  });

  group('#42 subscription preview', () {
    test('links, base64, Clash, sing-box, WireGuard', () {
      const links = 'vless://a@1.1.1.1:443#A\nvmess://eyJhIjoxfQ==\ntuic://u:p@h:1#T\nanytls://p@h:2#X\nhttps://example.com';
      expect(museSubPreview(links).nodes, 4);
      expect(museSubPreview(links).format, MuseSubFormat.links);
      final b64 = base64.encode(utf8.encode(links));
      expect(museSubPreview(b64).format, MuseSubFormat.base64);
      expect(museSubPreview(b64).nodes, 4);
      const clash = 'mixed-port: 7890\nproxies:\n  - name: A\n    type: ss\n    server: a\n  - {name: B, type: trojan}\n  - name: C\n    type: vless\nproxy-groups:\n  - name: G\n    proxies:\n      - A\n';
      expect(museSubPreview(clash).format, MuseSubFormat.clash);
      expect(museSubPreview(clash).nodes, 3);
      final sb = jsonEncode({
        'outbounds': [
          {'type': 'selector', 'tag': 's'},
          {'type': 'vless', 'tag': 'a'},
          {'type': 'direct', 'tag': 'd'},
        ],
        'endpoints': [
          {'type': 'wireguard', 'tag': 'w'},
        ],
      });
      expect(museSubPreview(sb).nodes, 2);
      const wg = '[Interface]\nPrivateKey = x\nAddress = 10.0.0.2/32\n\n[Peer]\nPublicKey = y\nEndpoint = 1.2.3.4:51820\n';
      expect(museSubPreview(wg).formatTitle, 'WireGuard');
      expect(museSubPreview(wg).nodes, 1);
    });
    test('malformed bodies never throw', () {
      for (final s in ['', '{', '{"outbounds": 3}', 'proxies:\n', '[1,2', '\u0000\u0001', 'x' * 5000]) {
        final p = museSubPreview(s);
        expect(p.nodes, greaterThanOrEqualTo(0));
      }
      expect(museSubPreview('<html>blocked</html>').empty, isTrue);
    });
  });

  group('#45 subscription errors', () {
    test('HTTP status with advice', () {
      expect(museSubFetchError(status: 403), startsWith('HTTP 403 · 订阅链接可能已失效'));
      expect(museSubFetchError(status: 404), contains('不存在'));
      expect(museSubFetchError(status: 429), contains('限流'));
      expect(museSubFetchError(status: 502), contains('稍后'));
      expect(museSubFetchError(status: 418), startsWith('HTTP 418'));
    });
    test('network failures', () {
      expect(museSubFetchError(kind: 'connectionTimeout'), startsWith('连接超时'));
      expect(museSubFetchError(detail: 'HandshakeException: CERTIFICATE_VERIFY_FAILED'), startsWith('证书校验失败'));
      expect(museSubFetchError(detail: 'SocketException: Failed host lookup'), startsWith('域名解析失败'));
      expect(museSubFetchError(detail: 'Connection reset by peer'), startsWith('连接被拒绝'));
      expect(museSubFetchError(detail: 'something else'), '');
    });
  });

  group('#46 traffic from entry names', () {
    test('剩余流量 + 到期 in link names', () {
      final body = [
        'vless://a@h:1#${Uri.encodeComponent('剩余流量：98.5 GB')}',
        'vless://a@h:1#${Uri.encodeComponent('套餐到期：2026-11-30')}',
        'vless://a@h:1#JP',
      ].join('\n');
      final info = museSubInfoFromContent(base64.encode(utf8.encode(body)))!;
      final parsed = ProfileParser.parseSubscriptionInfo(info)!;
      expect(parsed.total - parsed.consumption, (98.5 * 1024 * 1024 * 1024).round());
      expect(parsed.expire, DateTime(2026, 11, 30, 23, 59, 59));
    });
    test('STATUS= line', () {
      const body = 'STATUS=🚀↑:0.5GB,↓:10GB,TOT:100GB💡Expires:2026-12-01\nvless://a@h:1#JP';
      final parsed = ProfileParser.parseSubscriptionInfo(museSubInfoFromContent(body)!)!;
      expect(parsed.total, 100 * 1024 * 1024 * 1024);
      expect(parsed.consumption, (10.5 * 1024 * 1024 * 1024).round());
      expect(parsed.expire.year, 2026);
    });
    test('Clash names; nothing stated = null', () {
      const clash = 'proxies:\n  - name: "剩余流量: 1.5 TB"\n    type: ss\n';
      final parsed = ProfileParser.parseSubscriptionInfo(museSubInfoFromContent(clash)!)!;
      expect(parsed.total, (1.5 * 1024 * 1024 * 1024 * 1024).round());
      expect(museSubInfoFromContent('vless://a@h:1#JP'), isNull);
      expect(museSubInfoFromContent(''), isNull);
    });
    test('a header without upload still counts', () {
      final parsed = ProfileParser.parseSubscriptionInfo('download=1024; total=10240; expire=0')!;
      expect(parsed.upload, 0);
      expect(parsed.download, 1024);
    });
  });

  group('#43 per-subscription filters', () {
    test('round trip, empty entries dropped, garbage = none', () {
      final f = {'p1': const MuseSubFilter(include: '香港|日本'), 'p2': const MuseSubFilter(), 'p3': const MuseSubFilter(exclude: '倍率')};
      final back = museParseSubFilters(museSubFiltersToRaw(f));
      expect(back.keys, ['p1', 'p3']);
      expect(back['p1']!.include, '香港|日本');
      expect(back['p3']!.exclude, '倍率');
      expect(museParseSubFilters('nope'), isEmpty);
      expect(museParseSubFilters('[1]'), isEmpty);
    });
  });

  group('#59 Clash / Surge rules', () {
    test('lines → rules in order, policies mapped, groups merged', () {
      const text = '''
rules:
  - DOMAIN-SUFFIX,google.com,🚀 节点选择
  - DOMAIN-KEYWORD,youtube,Proxy
  - IP-CIDR,91.108.4.0/22,Proxy,no-resolve
  - IP-CIDR6,2001:b28:f23d::/48,Proxy
  - DOMAIN,ad.example.com,REJECT
  - DST-PORT,6881-6889,DIRECT
  - PROCESS-NAME,Telegram.exe,Proxy
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT
  - GEOIP,LAN,DIRECT
  - AND,((DOMAIN,a.com),(NETWORK,UDP)),REJECT
  - RULE-SET,https://x/y.list,Proxy
  - MATCH,Proxy
''';
      final c = museConvertClashRules(text, prefix: '粘贴');
      expect(c.converted, 9);
      expect(c.skipped, 2);
      final names = [for (final r in c.rules) r.name];
      expect(names.first, '粘贴 1 · 代理');
      final first = c.rules.first;
      expect(first.outbound, Outbound.proxy);
      expect(first.domainSuffixes, ['google.com']);
      expect(first.domainKeywords, ['youtube']);
      expect(first.ipCidrs, ['91.108.4.0/22', '2001:b28:f23d::/48']);
      expect(c.rules[1].outbound, Outbound.block);
      expect(c.rules[1].domains, ['ad.example.com']);
      expect(c.rules[2].portRanges, ['6881:6889']);
      expect(c.rules[2].outbound, Outbound.direct);
      expect(c.rules[3].processNames, ['Telegram.exe']);
      expect(c.rules[4].ruleSets, [museGeositeUrl('cn'), museGeoipUrl('cn')]);
      expect([for (final r in c.rules) r.listOrder], [0, 1, 2, 3, 4]);
    });
    test('Surge lines, comments, junk', () {
      const text = '[Rule]\n# comment\nDOMAIN-SUFFIX,openai.com,AI\nIP-CIDR,10.0.0.1,DIRECT\nFINAL,Proxy\nnonsense\n';
      final c = museConvertClashRules(text);
      expect(c.rules.length, 1);
      expect(c.rules.single.domainSuffixes, ['openai.com']);
      expect(c.skipped, 2);
      expect(museConvertClashRules('').rules, isEmpty);
    });
  });

  group('#11 protocol names', () {
    test('TUIC / AnyTLS / ShadowTLS / Hysteria2 are named', () {
      expect(museProtocolName('tuic'), 'TUIC');
      expect(museProtocolName('anytls'), 'AnyTLS');
      expect(museProtocolName('shadowtls'), 'ShadowTLS');
      expect(museProtocolName('hysteria2'), 'Hysteria2');
    });
  });
}
