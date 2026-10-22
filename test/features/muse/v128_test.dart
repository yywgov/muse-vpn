// 穿云 1.2.8
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/notify.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/diagnosis.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/logic/redact.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

void main() {
  group('tray icon / tooltip', () {
    test('icon is blue (Connected) as soon as connected, delay or not', () {
      expect(museTrayIconStatus(const Connected()), isA<Connected>());
      expect(museTrayIconStatus(const Connecting()), isA<Connecting>());
      expect(museTrayIconStatus(const Disconnected()), isA<Disconnected>());
    });
    test('delay and speed only go into the tooltip', () {
      expect(museTrayTooltip(const Connected(), 0, '已连接'), '穿云 - 已连接');
      expect(museTrayTooltip(const Connected(), 123, '已连接'), '穿云 - 已连接 · 123ms');
      expect(museTrayTooltip(const Connected(), 65535, '已连接', speed: '↓1 KB/s ↑0 B/s'), '穿云 - 已连接 · ↓1 KB/s ↑0 B/s');
      expect(museTrayTooltip(const Disconnected(), 123, '未连接', speed: 'x'), '穿云 - 未连接');
    });
    test('tray menu shows the speed while connected', () {
      final on = museTrayMenuSpec(const Connected(), MuseRouteMode.rule, speed: '↓2 KB/s ↑1 KB/s');
      expect(on.first.key, 'speed');
      expect(on.first.disabled, isTrue);
      expect(on[1].label, '断开');
      final off = museTrayMenuSpec(const Disconnected(), MuseRouteMode.rule, speed: '↓2 KB/s ↑1 KB/s');
      expect(off.first.label, '连接');
      expect(museSpeedText(1024, 2048), '↓2.0 KB/s ↑1.0 KB/s');
    });
  });
  group('去广告 温和 / 强力', () {
    List<Rule> fresh({bool adsOn = true}) => [
      for (final b in BuiltinRule.values) b.rule..enabled = b != BuiltinRule.blockAds || adsOn,
    ];
    test('默认温和', () {
      expect(MuseAdBlockLevel.fromKey(''), MuseAdBlockLevel.gentle);
      expect(MuseAdBlockLevel.fromKey('strong'), MuseAdBlockLevel.strong);
    });
    test('强力 keeps the full ad rule-set', () {
      final out = museApplyAdBlockLevel(fresh(), MuseAdBlockLevel.strong);
      expect(out.where((r) => r.ruleSets.any((s) => s.contains('category-ads'))), hasLength(1));
    });
    test('温和 drops the big list, keeps malware / phishing, adds a domain rule', () {
      final rules = fresh();
      final out = museApplyAdBlockLevel(rules, MuseAdBlockLevel.gentle);
      expect(out.any((r) => r.ruleSets.any((s) => s.contains('category-ads'))), isFalse);
      final ads = out.firstWhere((r) => r.name == 'builtin:blockAds');
      expect(ads.ruleSets.any((s) => s.contains('malware')), isTrue);
      final gentle = out.firstWhere((r) => r.name == 'builtin:blockAds:gentle');
      expect(gentle.outbound, Outbound.block);
      expect(gentle.enabled, isTrue);
      expect(gentle.listOrder, ads.listOrder);
      expect(gentle.domainSuffixes, contains('doubleclick.net'));
      expect(out.indexOf(gentle), out.indexOf(ads) + 1);
      // the user's list itself is not changed
      expect(rules.firstWhere((r) => r.name == 'builtin:blockAds').ruleSets.any((s) => s.contains('category-ads')), isTrue);
    });
    test('温和 follows the user switch', () {
      final out = museApplyAdBlockLevel(fresh(adsOn: false), MuseAdBlockLevel.gentle);
      expect(out.firstWhere((r) => r.name == 'builtin:blockAds:gentle').enabled, isFalse);
    });
    test('温和 never lists domains apps need', () {
      for (final d in ['apple.com', 'google.com', 'qq.com', 'weixin.qq.com', 'taobao.com', 'alipay.com', 'baidu.com']) {
        expect(museGentleAdDomains, isNot(contains(d)));
      }
    });
  });

  group('非节点条目', () {
    test('info lines are recognised', () {
      for (final n in ['剩余流量：12.3 GB', '套餐到期：2026-12-01', '官网 example.com', '距离下次重置剩余：3 天', 'Traffic: 1GB', 'Expire: 2026']) {
        expect(museIsInfoNode(n), isTrue, reason: n);
      }
    });
    test('real nodes are kept', () {
      for (final n in ['🇭🇰 香港 01', '日本 IPLC 0.5x', 'US-LA-02', 'Singapore 03 | 流媒体', '台湾 HiNet']) {
        expect(museIsInfoNode(n), isFalse, reason: n);
      }
    });
  });

  group('收藏置顶', () {
    test('toggle round-trip', () {
      var raw = '';
      raw = museToggleFavorite(raw, 'a');
      raw = museToggleFavorite(raw, 'b');
      expect(museParseFavorites(raw), {'a', 'b'});
      raw = museToggleFavorite(raw, 'a');
      expect(museParseFavorites(raw), {'b'});
    });
    test('groups, then favourites, then the rest, order kept', () {
      final items = ['g1', 'n1', 'n2', 'n3', 'g2'];
      final out = museFavoritesFirst<String>(items, isGroup: (e) => e.startsWith('g'), tag: (e) => e, favorites: {'n3', 'n1'});
      expect(out, ['g1', 'g2', 'n1', 'n3', 'n2']);
      expect(museFavoritesFirst<String>(items, isGroup: (e) => e.startsWith('g'), tag: (e) => e, favorites: {}), items);
    });
  });

  group('记住每个订阅的节点', () {
    test('remember and restore', () {
      var raw = '{}';
      raw = museRememberNode(raw, 'p1', 'hk');
      raw = museRememberNode(raw, 'p2', 'jp');
      expect(museNodeToRestore(raw, 'p1', selected: 'auto', tags: ['auto', 'hk']), 'hk');
      expect(museNodeToRestore(raw, 'p1', selected: 'hk', tags: ['hk']), isNull);
      expect(museNodeToRestore(raw, 'p2', selected: 'auto', tags: ['auto', 'hk']), isNull);
      expect(museNodeToRestore(raw, 'p3', selected: 'auto', tags: ['auto']), isNull);
    });
    test('bad JSON is an empty map, list capped', () {
      expect(museParseLastNodes('oops'), isEmpty);
      var raw = '';
      for (var i = 0; i < 60; i++) {
        raw = museRememberNode(raw, 'p$i', 't$i');
      }
      final m = museParseLastNodes(raw);
      expect(m.length, 50);
      expect(m['p59'], 't59');
      expect(m.containsKey('p0'), isFalse);
    });
  });

  group('订阅自动更新', () {
    test('user hours, provider may be sooner, 0 = off', () {
      expect(museEffectiveUpdateInterval(null), const Duration(hours: 12));
      expect(museEffectiveUpdateInterval(null, hours: 6), const Duration(hours: 6));
      expect(museEffectiveUpdateInterval(const Duration(hours: 2), hours: 24), const Duration(hours: 2));
      expect(museEffectiveUpdateInterval(const Duration(hours: 48), hours: 24), const Duration(hours: 24));
      expect(museEffectiveUpdateInterval(const Duration(hours: 2), hours: 0), isNull);
      expect(museAutoUpdateChoices, contains(12));
      expect(museAutoUpdateLabel(0), '关闭');
      expect(museAutoUpdateLabel(12), '每 12 小时');
    });
  });

  group('脱敏', () {
    test('links, secrets, uuids, addresses removed', () {
      const log = 'fetch https://sub.example.com/api/v1/client/subscribe?token=abc123 failed\n'
          'outbound vless://9d6e4a3c-1b2f-4c5d-8e9f-0a1b2c3d4e5f@1.2.3.4:443?sni=foo.com#HK\n'
          '{"type":"trojan","server":"hk.node.example.net","server_port":443,"password":"s3cret"}\n'
          'id 9d6e4a3c-1b2f-4c5d-8e9f-0a1b2c3d4e5f dial 203.0.113.9:8443 via 2001:db8:85a3::8a2e:370:7334 user me@mail.com\n'
          'listen 127.0.0.1:12334 at 12:34:56\n';
      final r = museRedact(log);
      for (final secret in ['sub.example.com', 'abc123', '9d6e4a3c', '1.2.3.4', 'foo.com', 'hk.node.example.net', 's3cret', '203.0.113.9', '2001:db8', 'me@mail.com']) {
        expect(r, isNot(contains(secret)), reason: secret);
      }
      expect(r, contains('127.0.0.1:12334'));
      expect(r, contains('12:34:56'));
      expect(r, contains('vless://***'));
    });
  });

  group('一键诊断', () {
    test('plain Chinese per check and a conclusion', () {
      final items = [
        museDiagNetwork(directOk: true),
        museDiagDns(domesticOk: true, foreignOk: false),
        museDiagNode(connected: true, delay: 65535, name: '香港 01'),
        museDiagRouting(connected: true, android: false, tun: false, systemProxyOurs: false),
        museDiagInternet(connected: true, ok: false),
      ];
      expect(items.map((e) => e.level), [MuseDiagLevel.ok, MuseDiagLevel.warn, MuseDiagLevel.fail, MuseDiagLevel.fail, MuseDiagLevel.fail]);
      expect(items[2].text, contains('「香港 01」'));
      expect(museDiagConclusion(items), startsWith('发现问题'));
      expect(museDiagConclusion([museDiagNetwork(directOk: true)]), '一切正常');
      expect(museDiagNode(connected: false, delay: 0).level, MuseDiagLevel.skip);
      expect(museDiagNode(connected: true, delay: 120).level, MuseDiagLevel.ok);
      expect(museDiagNode(connected: true, delay: 1500).level, MuseDiagLevel.warn);
      expect(museDiagRouting(connected: true, android: true, tun: false).level, MuseDiagLevel.ok);
    });
  });

  group('外网探测', () {
    test('204 / 200 ok, anything else failed', () {
      expect(museReachVerdict(204), MuseReach.ok);
      expect(museReachVerdict(200), MuseReach.ok);
      expect(museReachVerdict(null), MuseReach.failed);
      expect(museReachVerdict(403), MuseReach.failed);
      expect(museReachUrl, 'https://www.google.com/generate_204');
    });
  });

  group('更新说明', () {
    test('once per version, not on a fresh install', () {
      expect(museChangelogToShow(version: '1.2.8', shown: '1.2.7', introDone: true), isNotEmpty);
      expect(museChangelogToShow(version: '1.2.8', shown: '1.2.8', introDone: true), isNull);
      expect(museChangelogToShow(version: '1.2.8', shown: '', introDone: false), isNull);
      expect(museChangelogToShow(version: '9.9.9', shown: '', introDone: true), isNull);
    });
  });

  group('Windows 通知', () {
    test('text travels base64-encoded', () {
      final s = museWindowsToastScript('「订阅」提醒', "it's 80%");
      expect(s, isNot(contains('订阅')));
      expect(s, contains('ToastText02'));
    });
  });
}
