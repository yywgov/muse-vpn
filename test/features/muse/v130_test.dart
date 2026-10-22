// 穿云 1.3.0: dashboard tiles (order / hide), 智能保持连接 strategy order, node cache, 去广告 关,
// theme modes, naming.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart';
import 'package:hiddify/features/muse/logic/keep_alive.dart';
import 'package:hiddify/features/muse/logic/node_cache.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

void main() {
  group('首页 tiles', () {
    test('default order, unknown keys dropped, new tiles appended', () {
      expect(museParseTileOrder(''), MuseHomeTile.values);
      expect(
        museParseTileOrder('exit,bogus,speed,exit'),
        [MuseHomeTile.exit, MuseHomeTile.speed, MuseHomeTile.traffic, MuseHomeTile.remaining, MuseHomeTile.expiry, MuseHomeTile.adBlock],
      );
      final order = museParseTileOrder('adblock,speed');
      expect(museParseTileOrder(museTileOrderToRaw(order)), order);
    });
    test('move by one and to an index, clamped at the ends', () {
      final o = MuseHomeTile.values.toList();
      expect(museMoveTile(o, MuseHomeTile.traffic, -1).take(2), [MuseHomeTile.traffic, MuseHomeTile.speed]);
      expect(museMoveTile(o, MuseHomeTile.speed, -1), o);
      expect(museMoveTile(o, MuseHomeTile.adBlock, 1), o);
      expect(museMoveTileTo(o, MuseHomeTile.adBlock, 0).first, MuseHomeTile.adBlock);
      expect(museMoveTileTo(o, MuseHomeTile.speed, 99).last, MuseHomeTile.speed);
      expect(museMoveTileTo(o, MuseHomeTile.speed, 99).length, o.length);
    });
    test('hide / show round trip', () {
      var hidden = museParseHiddenTiles('');
      expect(hidden, isEmpty);
      hidden = museToggleHiddenTile(hidden, MuseHomeTile.exit);
      expect(museHiddenTilesToRaw(hidden), 'exit');
      expect(museParseHiddenTiles('exit,nope'), {MuseHomeTile.exit});
      expect(museToggleHiddenTile(hidden, MuseHomeTile.exit), isEmpty);
    });
    test('visible = not hidden and has data', () {
      final v = museVisibleTiles(
        MuseHomeTile.values,
        {MuseHomeTile.adBlock},
        hasData: (t) => t != MuseHomeTile.remaining,
      );
      expect(v, [MuseHomeTile.speed, MuseHomeTile.traffic, MuseHomeTile.expiry, MuseHomeTile.exit]);
    });
    test('columns: 2 phone, 3 / 4 desktop', () {
      expect(museTileColumns(380), 2);
      expect(museTileColumns(700), 3);
      expect(museTileColumns(1100), 4);
    });
    test('speed text keeps a stable shape', () {
      expect(museSpeedText(0), '0 B/s');
      expect(museSpeedText(999), '999 B/s');
      expect(museSpeedText(180 * 1024), '180 KB/s');
      expect(museSpeedText((2.4 * 1024 * 1024).round()), '2.4 MB/s');
      expect(museSpeedText(-5), '0 B/s');
    });
    test('days left', () {
      final now = DateTime(2026, 10, 22, 12);
      expect(museDaysLeft(DateTime(2026, 11, 21, 12), now: now), 30);
      expect(museDaysLeft(DateTime(2026, 10, 22, 20), now: now), 0);
      expect(museDaysLeft(DateTime(2026, 10, 20), now: now), lessThan(0));
    });
  });

  group('智能保持连接', () {
    test('one order: reconnect → switch node → restart core', () {
      expect(museKeepAliveOrder, [MuseKeepAliveStep.reconnect, MuseKeepAliveStep.switchNode, MuseKeepAliveStep.restartCore]);
      expect(MuseKeepAliveStep.values.map((e) => e.title), ['重新连接', '换到最佳节点', '重启内核']);
    });
    test('each problem starts at its step and escalates', () {
      expect(museKeepAliveLadder(MuseKeepAliveProblem.connectionLost), museKeepAliveOrder);
      expect(museKeepAliveLadder(MuseKeepAliveProblem.nodeUnreachable), [MuseKeepAliveStep.switchNode, MuseKeepAliveStep.restartCore]);
      expect(museKeepAliveLadder(MuseKeepAliveProblem.coreUnresponsive), [MuseKeepAliveStep.restartCore]);
      expect(museKeepAliveStepFor(MuseKeepAliveProblem.connectionLost, attempt: 0), MuseKeepAliveStep.reconnect);
      expect(museKeepAliveStepFor(MuseKeepAliveProblem.connectionLost, attempt: 1), MuseKeepAliveStep.switchNode);
      expect(museKeepAliveStepFor(MuseKeepAliveProblem.connectionLost, attempt: 7), MuseKeepAliveStep.restartCore);
      expect(museKeepAliveStepFor(MuseKeepAliveProblem.nodeUnreachable, attempt: 0), MuseKeepAliveStep.switchNode);
    });
    test('a manual disconnect or the switch turned off stops everything', () {
      expect(museKeepAliveStepFor(MuseKeepAliveProblem.coreUnresponsive, attempt: 0, userStopped: true), isNull);
      expect(museKeepAliveStepFor(MuseKeepAliveProblem.connectionLost, attempt: 0, enabled: false), isNull);
    });
    test('single log line format', () {
      expect(museKeepAliveLogLine(MuseKeepAliveStep.restartCore, '内核无响应'), '智能保持连接 · 重启内核：内核无响应');
    });
    test('every layer is gated by the one switch', () {
      for (final f in [
        'lib/features/muse/home/node_failover.dart',
        'lib/features/muse/home/bad_nodes.dart',
        'lib/features/muse/home/core_watchdog.dart',
        'lib/features/muse/desktop/connection_keeper.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('Preferences.museKeepAlive'), reason: f);
      }
      // the 1.2.2 race fixes stay
      final keeper = File('lib/features/muse/desktop/connection_keeper.dart').readAsStringSync();
      expect(keeper, contains('intentGeneration'));
      expect(keeper, contains('recoverConnection(generation: generation)'));
    });
  });

  group('node cache (picking while disconnected)', () {
    test('round trip, names equal to tags are not stored twice', () {
      const cache = MuseNodeCache(
        profileId: 'p1',
        groupTag: 'select',
        selected: 'lowest',
        nodes: [
          MuseCachedNode(tag: 'lowest', name: 'lowest', type: 'URLTest', isGroup: true),
          MuseCachedNode(tag: 'jp-1', name: '🇯🇵 东京 01', type: 'vless'),
        ],
      );
      final raw = cache.toRaw();
      expect(raw, isNot(contains('"lowest","lowest"')));
      final back = MuseNodeCache.parse(raw);
      expect(back.profileId, 'p1');
      expect(back.groupTag, 'select');
      expect(back.nodes.length, 2);
      expect(back.nodes.first.isGroup, isTrue);
      expect(back.nodes.first.name, 'lowest');
      expect(back.nodes.last.name, '🇯🇵 东京 01');
      expect(back.nodes.last.isGroup, isFalse);
    });
    test('another subscription or garbage gives nothing', () {
      expect(MuseNodeCache.parse('{bad').isEmpty, isTrue);
      expect(MuseNodeCache.parse('').isEmpty, isTrue);
      const c = MuseNodeCache(profileId: 'p1', groupTag: 'g', selected: 'a', nodes: [MuseCachedNode(tag: 'a', name: 'a', type: 'ss')]);
      expect(c.forProfile('p2').isEmpty, isTrue);
      expect(c.forProfile(null).isEmpty, isTrue);
      expect(c.forProfile('p1').isEmpty, isFalse);
    });
    test('the remembered pick wins when the subscription still has it', () {
      const c = MuseNodeCache(
        profileId: 'p1',
        groupTag: 'g',
        selected: 'a',
        nodes: [MuseCachedNode(tag: 'a', name: 'a', type: 'ss'), MuseCachedNode(tag: 'b', name: 'b', type: 'ss')],
      );
      expect(c.currentTag('b'), 'b');
      expect(c.currentTag('gone'), 'a');
      expect(c.currentTag(null), 'a');
    });
  });

  test('flag emoji stripped next to the flag box', () {
    expect(museStripFlags('🇯🇵 东京 02'), '东京 02');
    expect(museStripFlags('香港 🇭🇰 IPLC'), '香港 IPLC');
    expect(museStripFlags('🇯🇵'), '🇯🇵');
    expect(museStripFlags('plain'), 'plain');
  });

  group('去广告 关', () {
    List<Rule> rules() => [
      Rule(name: 'builtin:blockAds', enabled: true, ruleSets: ['geosite-category-ads-all', 'geosite-malware']),
      Rule(name: 'other', enabled: true),
    ];
    test('关 drops the ad sets but keeps malware / phishing', () {
      final out = museApplyAdBlockLevel(rules(), MuseAdBlockLevel.off);
      expect(out.length, 2);
      expect(out.first.ruleSets, ['geosite-malware']);
      expect(out.any((r) => r.name == 'builtin:blockAds:gentle'), isFalse);
    });
    test('a rule left with nothing is dropped', () {
      final out = museApplyAdBlockLevel(
        [Rule(name: 'builtin:blockAds', enabled: true, ruleSets: ['geosite-category-ads-all'])],
        MuseAdBlockLevel.off,
      );
      expect(out, isEmpty);
    });
    test('three levels, default 温和', () {
      expect(MuseAdBlockLevel.values.map((e) => e.title), ['关', '温和', '强力']);
      expect(MuseAdBlockLevel.fromKey('off'), MuseAdBlockLevel.off);
      expect(MuseAdBlockLevel.fromKey('x'), MuseAdBlockLevel.gentle);
    });
  });

  group('look and naming', () {
    test('dark mode is night blue again, 纯黑 is gone from the choices', () {
      expect(AppThemeMode.choices, [AppThemeMode.system, AppThemeMode.light, AppThemeMode.dark]);
      expect(AppThemeMode.black.trueBlack, isFalse);
    });
    test('四个标签 首页 / 节点 / 订阅 / 设置', () {
      final layout = File('lib/core/router/adaptive_layout/my_adaptive_layout.dart').readAsStringSync();
      for (final t in ["'首页'", "'节点'", "'订阅'", "'设置'"]) {
        expect(layout, contains(t));
      }
      expect(layout, isNot(contains("'配置'")));
    });
    test('「订阅」 everywhere, no 订阅/配置 mix', () {
      for (final f in [
        'lib/features/muse/config/muse_config_page.dart',
        'lib/features/muse/home/muse_home_page.dart',
        'lib/features/about/widget/about_page.dart',
        'lib/features/settings/overview/settings_page.dart',
      ]) {
        final s = File(f).readAsStringSync();
        for (final bad in ['订阅 / 配置', '订阅/配置', '添加订阅或配置', '规则与订阅']) {
          expect(s, isNot(contains(bad)), reason: '$f: $bad');
        }
      }
    });
    test('removed toggles and filler texts', () {
      final settings = File('lib/features/settings/overview/settings_page.dart').readAsStringSync();
      for (final gone in ['隐藏非节点条目', '出口检测', '自动收起不可用节点', '规则与订阅']) {
        expect(settings, isNot(contains("'$gone'")), reason: gone);
      }
      expect(settings, contains('智能保持连接'));
      final home = File('lib/features/muse/home/muse_home_page.dart').readAsStringSync();
      for (final gone in ['导入后点上方圆形按钮连接', '连接后显示节点', "'当前  ", '复制服务商给你的订阅链接']) {
        expect(home, isNot(contains(gone)), reason: gone);
      }
    });
    test('no stray hex colours in the redesigned screens', () {
      for (final f in [
        'lib/features/muse/home/muse_home_page.dart',
        'lib/features/muse/nodes/node_list.dart',
        'lib/features/muse/settings/diagnose_sheet.dart',
        'lib/features/settings/overview/settings_page.dart',
        'lib/features/muse/widget/grouped_list.dart',
      ]) {
        expect(File(f).readAsStringSync(), isNot(contains('Color(0x')), reason: f);
      }
    });
    test('changelog has 1.3.0', () {
      expect(museChangelog['1.3.0'], isNotEmpty);
    });
  });
}
