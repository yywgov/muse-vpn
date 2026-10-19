// 穿云 1.2.3: 出口检测 parsing / verdicts, 节点搜索, tray 节点 submenu.
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';

void main() {
  group('出口检测', () {
    test('cloudflare trace', () {
      final info = museParseCfTrace('fl=123\nh=www.cloudflare.com\nip=203.0.113.7\nts=1\nloc=JP\ncolo=NRT\n')!;
      expect(info.ip, '203.0.113.7');
      expect(info.country, 'JP');
      expect(museParseCfTrace('loc=JP\n'), isNull);
      expect(museParseCfTrace('ip=1.1.1.1\nloc=XX\n')!.country, '');
    });

    test('masked ip and region label', () {
      expect(museMaskIp('203.0.113.7'), '203.0.*.*');
      expect(museMaskIp('2001:db8:1::5'), '2001:db8:…');
      expect(museCountryLabel('JP'), '日本');
      expect(museCountryLabel('ZZ'), 'ZZ');
      expect(museCountryLabel(''), '未知地区');
      expect(museCountryFlag('JP'), '🇯🇵');
    });

    test('ChatGPT', () {
      expect(museChatGptVerdict(200, '{"cookie_consent":false}'), MuseServiceState.ok);
      expect(museChatGptVerdict(403, '{"error":{"code":"unsupported_country"}}'), MuseServiceState.blocked);
      expect(museChatGptVerdict(403, 'You may be using a VPN'), MuseServiceState.blocked);
      expect(museChatGptVerdict(null, ''), MuseServiceState.failed);
      expect(museChatGptVerdict(502, 'bad gateway'), MuseServiceState.failed);
    });

    test('Netflix', () {
      expect(museNetflixVerdict(200, 200), MuseServiceState.ok);
      expect(museNetflixVerdict(404, 200), MuseServiceState.partial);
      expect(museNetflixVerdict(403, 403), MuseServiceState.blocked);
      expect(museNetflixVerdict(null, null), MuseServiceState.failed);
    });

    test('Google', () {
      expect(museGoogleVerdict(204), MuseServiceState.ok);
      expect(museGoogleVerdict(null), MuseServiceState.failed);
      expect(museServiceStateLabel(MuseServiceState.partial, partial: '仅自制剧'), '仅自制剧');
    });
  });

  group('节点搜索', () {
    test('name, case, several words', () {
      expect(museNodeMatches('香港 IPLC 01', 'iplc'), isTrue);
      expect(museNodeMatches('香港 IPLC 01', '香港 01'), isTrue);
      expect(museNodeMatches('香港 IPLC 01', '日本'), isFalse);
      expect(museNodeMatches('anything', '  '), isTrue);
    });

    test('a region word finds other spellings of that region', () {
      expect(museNodeMatches('🇯🇵 Tokyo 02', '日本', regionOf: museRegionCode), isTrue);
      expect(museNodeMatches('东京 BGP', 'jp', regionOf: museRegionCode), isTrue);
      expect(museNodeMatches('Hong Kong 3', 'hk', regionOf: museRegionCode), isTrue);
      expect(museNodeMatches('Hong Kong 3', '新加坡', regionOf: museRegionCode), isFalse);
    });
  });

  group('tray 节点', () {
    test('fastest first, selected always listed, delays as text', () {
      final items = [
        for (var i = 0; i < 30; i++) (tag: 'n$i', name: 'Node $i', delay: 100 + i),
        (tag: 'slow', name: 'Slow', delay: 65000),
        (tag: 'new', name: 'New', delay: 0),
      ];
      final nodes = museTrayNodes(items, selected: 'slow');
      expect(nodes.first.tag, 'slow');
      expect(nodes.first.selected, isTrue);
      expect(nodes.first.label, 'Slow   超时');
      expect(nodes[1].label, 'Node 0   100 ms');
      expect(nodes.length, museTrayMaxNodes + 1);
      expect(museTrayNodes([(tag: 'new', name: 'New', delay: 0)], selected: '').single.label, 'New');
    });

    test('submenu only while connected; top-level order unchanged', () {
      const nodes = [MuseTrayNode('a', 'A   80 ms', selected: true), MuseTrayNode('b', 'B')];
      final on = museTrayMenuSpec(const Connected(), MuseRouteMode.rule, nodes: nodes);
      expect(on.where((e) => e.key != '-').map((e) => e.label).toList(), ['断开', '规则', '全局', '节点', '显示窗口', '退出']);
      final sub = on.firstWhere((e) => e.key == 'nodes').children;
      expect(sub.first.key, 'node:a');
      expect(sub.first.checked, isTrue);
      expect(sub.last.key, 'urltest');
      final off = museTrayMenuSpec(const Disconnected(), MuseRouteMode.rule, nodes: nodes);
      expect(off.any((e) => e.key == 'nodes'), isFalse);
    });
  });
}
