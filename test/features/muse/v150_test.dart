// 穿云 1.5.0 (batch 1): connect state machine + stages, config pre-check, plain-words errors,
// single-column tiles at large text, small updates without the dialog, contrast, default-hidden
// 去广告 tile, loopback-only ports, one line-icon set.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/connect_flow.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

double _lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a);
  final lb = _lum(b);
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

const _light = MuseThemeForTest(false);
const _dark = MuseThemeForTest(true);

/// The resolved palette without a BuildContext.
class MuseThemeForTest {
  const MuseThemeForTest(this.dark);

  final bool dark;
  Color get text2 => dark ? MusePalette.darkText2 : MusePalette.lightText2;
  Color get text3 => dark ? MusePalette.darkText3 : MusePalette.lightText3;
  List<Color> get surfaces => dark
      ? const [MusePalette.darkCard, MusePalette.darkBgTop, MusePalette.darkBgBottom, MusePalette.darkInner, MusePalette.darkSelected, MusePalette.darkHeroIdle]
      : const [MusePalette.lightCard, MusePalette.lightBgTop, MusePalette.lightBgBottom, MusePalette.lightInner, MusePalette.lightSelected];
}

void main() {
  group('#3 connect button state machine', () {
    test('connect / disconnect / cancel / ignore', () {
      expect(museConnectActionFor(MuseLinkState.disconnected), MuseConnectAction.connect);
      expect(museConnectActionFor(MuseLinkState.connected), MuseConnectAction.disconnect);
      expect(museConnectActionFor(MuseLinkState.connecting), MuseConnectAction.cancel);
      expect(museConnectActionFor(MuseLinkState.disconnecting), MuseConnectAction.ignore);
    });
  });

  group('#82 connecting stages', () {
    test('准备配置 → 启动核心 → 测试连通 → nothing', () {
      expect(museConnectStageFor(MuseLinkState.disconnected, preparing: false, reachChecking: false), isNull);
      expect(museConnectStageFor(MuseLinkState.connecting, preparing: false, reachChecking: false), MuseConnectStage.starting);
      expect(museConnectStageFor(MuseLinkState.disconnected, preparing: true, reachChecking: false), MuseConnectStage.preparing);
      expect(museConnectStageFor(MuseLinkState.connected, preparing: false, reachChecking: true), MuseConnectStage.testing);
      expect(museConnectStageFor(MuseLinkState.connected, preparing: false, reachChecking: false), isNull);
      expect(museConnectStageFor(MuseLinkState.disconnecting, preparing: true, reachChecking: true), isNull);
      expect([for (final s in MuseConnectStage.values) s.title], ['准备配置', '启动核心', '测试连通']);
    });
  });

  group('#4 config pre-check', () {
    List<MuseConfigIssue> check({
      int? bytes = 2048,
      int mixed = 12334,
      bool clash = true,
      int clashPort = 16756,
      bool tun = false,
      int mtu = 9000,
      String dns = 'https://1.1.1.1/dns-query',
      String url = 'http://cp.cloudflare.com',
    }) => museConfigPrecheck(
      profileBytes: bytes,
      mixedPort: mixed,
      clashApi: clash,
      clashApiPort: clashPort,
      tun: tun,
      mtu: mtu,
      remoteDns: dns,
      testUrl: url,
    );

    test('a normal config passes', () {
      expect(check(), isEmpty);
      expect(check(tun: true, mtu: 1500), isEmpty);
      // the clash port only matters while the API is on
      expect(check(clash: false, clashPort: 12334), isEmpty);
    });

    test('each sure failure names its setting', () {
      expect(check(bytes: null).single.field, '订阅');
      expect(check(bytes: 0).single.field, '订阅');
      expect(check(mixed: 0).single.field, '代理端口');
      expect(check(mixed: 70000).map((e) => e.field), contains('代理端口'));
      expect(check(clashPort: 12334).single.toString(), contains('控制端口'));
      expect(check(clashPort: 99999).single.field, '控制端口');
      expect(check(tun: true, mtu: 100).single.field, 'MTU');
      expect(check(mtu: 100), isEmpty);
      expect(check(dns: '  ').single.field, '远程 DNS');
      expect(check(url: 'cp.cloudflare.com').single.field, '测速地址');
      expect(check(url: 'ftp://x').single.field, '测速地址');
    });
  });

  group('#5 errors in plain words', () {
    test('common errors', () {
      expect(museFriendlyError('x509: certificate signed by unknown authority')!.title, '证书校验失败');
      expect(museFriendlyError('x509: certificate has expired or is not yet valid')!.title, '系统时间不对');
      expect(museFriendlyError('dial tcp 1.2.3.4:443: connect: connection refused')!.title, '服务器拒绝连接');
      expect(museFriendlyError('listen tcp 127.0.0.1:12334: bind: address already in use')!.title, '本地端口被占用');
      expect(
        museFriendlyError('listen tcp 127.0.0.1:12334: bind: Only one usage of each socket address is normally permitted')!.title,
        '本地端口被占用',
      );
      expect(museFriendlyError('read: connection reset by peer')!.title, '连接被中途切断');
      expect(museFriendlyError('dial tcp: lookup a.example: no such host')!.title, '域名解析失败');
      expect(museFriendlyError('i/o timeout')!.title, '连接超时');
      expect(museFriendlyError('start service: permission denied')!.title, '没有权限');
      expect(museFriendlyError('something new'), isNull);
    });

    test('dialog text keeps the raw error as 详细信息', () {
      final p = museFriendlyPresent((type: '意外错误', message: 'failed to start core: connection refused'));
      expect(p.type, '服务器拒绝连接');
      expect(p.message, contains('详细信息：failed to start core: connection refused'));
      const unknown = (type: '意外错误', message: 'weird');
      expect(museFriendlyPresent(unknown), unknown);
    });
  });

  group('#80 tile columns follow the text size', () {
    test('320 px phone: 2 columns at 1×, 1 column at 2×', () {
      const content = 320.0 - 2 * MuseSpace.s16;
      expect(museTileColumnsFor(content, 6), 2);
      expect(museTileColumnsFor(content, 6, textScale: 2), 1);
      expect(museTileColumnsFor(content, 6, textScale: 1.3), 1);
      // a normal phone keeps 2 columns at 1.3×
      expect(museTileColumnsFor(412 - 32, 6, textScale: 1.3), 2);
    });

    test('desktop drops columns before squeezing, still without a lone tile', () {
      expect(museTileColumnsFor(860, 6), 3);
      expect(museTileColumnsFor(860, 6, textScale: 2), 3);
      expect(museTileColumnsFor(600, 6, textScale: 2), 2);
      expect(museTileColumnsFor(1200, 8, textScale: 2), 4);
    });
  });

  group('#123 small updates: dot, no dialog', () {
    test('patch release is small, feature release is not', () {
      expect(museIsSmallUpdate(version: '1.5.1', from: '1.5.0'), isTrue);
      expect(museIsSmallUpdate(version: '1.5.0', from: '1.4.1'), isFalse);
      expect(museIsSmallUpdate(version: '2.0.0', from: '1.9.9'), isFalse);
      expect(museIsSmallUpdate(version: '1.5.0', from: ''), isFalse);
      expect(museIsSmallUpdate(version: '1.5.0', from: '1.5.0'), isFalse);
      expect(museIsSmallUpdate(version: '1.5.1+151', from: '1.5.0+150'), isTrue);
    });

    test('the dialog only for a feature release; unread until seen', () {
      expect(museChangelogToShow(version: '1.4.1', shown: '1.4.0', introDone: true), isNull);
      expect(museChangelogToShow(version: '1.4.0', shown: '1.3.0', introDone: true), isNotEmpty);
      expect(museChangelogUnread(version: '1.4.1', seen: '1.4.0'), isTrue);
      expect(museChangelogUnread(version: '1.4.1', seen: '1.4.1'), isFalse);
      expect(museChangelogUnread(version: '9.9.9', seen: ''), isFalse);
    });
  });

  group('#83 contrast', () {
    for (final t in [_light, _dark]) {
      final name = t.dark ? 'dark' : 'light';
      test('$name: secondary text ≥ 4.5:1 and tertiary (icons) ≥ 3:1 on every surface', () {
        for (final s in t.surfaces) {
          expect(contrast(t.text2, s), greaterThanOrEqualTo(4.5), reason: 'text2 on $s');
          expect(contrast(t.text3, s), greaterThanOrEqualTo(3.0), reason: 'text3 on $s');
        }
      });
    }

    test('tertiary text colour is not used for text (icons only)', () {
      final hits = <String>[];
      for (final f in Directory('lib/features/muse').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('muse_tokens.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!RegExp(r'\btext3\b|tertiaryText').hasMatch(lines[i]) || lines[i].trimLeft().startsWith('//')) continue;
          if (f.path.endsWith('grouped_list.dart') && lines[i].contains('static Color tertiaryText')) continue;
          final window = lines.sublist(i < 6 ? 0 : i - 6, i + 1).join(' ');
          // a status dot is not text either
          if (!window.contains('Icon(') && !window.contains('Icons.') && !window.contains('dot')) hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  group('#121 去广告 tile', () {
    test('hidden by default', () {
      expect(museParseHiddenTiles(museDefaultHiddenTiles), {MuseHomeTile.adBlock, ...museNewTiles16}); // 1.6.0: the new cards too
      expect(museVisibleTiles(museParseTileOrder(''), museParseHiddenTiles(museDefaultHiddenTiles), hasData: (_) => true), isNot(contains(MuseHomeTile.adBlock)));
    });
  });

  group('#184 ports', () {
    test('the proxy / control ports stay on loopback (no LAN switch)', () {
      final src = File('lib/features/settings/data/config_option_repository.dart').readAsStringSync();
      expect(src, contains('allowConnectionFromLan: false,'));
    });
  });

  group('#85 one line-icon set', () {
    test('Material outlined icons only (filled star = favourite on)', () {
      const dirs = [
        'lib/features/muse',
        'lib/features/settings/overview',
        'lib/features/route_rules',
        'lib/features/app_based_routing/overview',
        'lib/features/about',
        'lib/features/profile',
        'lib/core/router',
      ];
      const allowed = {'star_rounded'};
      final hits = <String>[];
      for (final d in dirs) {
        for (final f in Directory(d).listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
          final s = f.readAsStringSync();
          if (s.contains('FluentIcons.')) hits.add('${f.path}: FluentIcons');
          for (final m in RegExp(r'(?<![A-Za-z])Icons\.([a-z0-9_]+)').allMatches(s)) {
            final n = m.group(1)!;
            if (!n.endsWith('_outlined') && !allowed.contains(n)) hits.add('${f.path}: $n');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  group('#118 / #119 / #120 already in place (verified)', () {
    test('检查更新 lives on 关于 (no separate update page)', () {
      final about = File('lib/features/about/widget/about_page.dart').readAsStringSync();
      expect(about, contains("title: '检查更新'"));
      expect(about, contains("title: '更新内容'"));
    });

    test('隐藏非节点条目 is always on, no switch; no 不可用 threshold setting', () {
      final prefs = File('lib/core/preferences/general_preferences.dart').readAsStringSync();
      expect(prefs, contains('"muse_hide_info_nodes", true, overrideValue: true'));
      for (final f in ['lib/features/settings/overview/settings_page.dart', 'lib/features/muse/settings/more_settings.dart']) {
        final src = File(f).readAsStringSync();
        expect(src, isNot(contains("title: '隐藏非节点条目'")), reason: f);
        expect(src, isNot(contains('阈值')), reason: f);
      }
    });
  });
}
