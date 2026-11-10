// 穿云 1.12.0: 启动器快捷方式、解锁检测、测速失败原因、连接一键加规则、出口 IP 详情、自动最快限定地区、
// 端口避让、系统代理绕过、新节点自动测速、剪贴板只在需要时读取、界面文案中文化。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/port_override.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/home/clipboard_import.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/new_node_test.dart';
import 'package:hiddify/features/muse/logic/auto_region.dart';
import 'package:hiddify/features/muse/logic/exit_detail.dart';
import 'package:hiddify/features/muse/logic/fail_reason.dart';
import 'package:hiddify/features/muse/logic/quick_rules.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/service_probe.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/logic/unlock_check.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

String _src(String p) => File(p).readAsStringSync();

MuseService _svc(String key) => museServices.firstWhere((s) => s.key == key);

void main() {
  group('#5 启动器快捷方式 chuanyun://mode / scan / speedtest', () {
    test('links parse to their action', () {
      expect(museParseDeepLink('chuanyun://mode')?.quick, MuseQuickAction.mode);
      expect(museParseDeepLink('chuanyun://scan')?.quick, MuseQuickAction.scan);
      expect(museParseDeepLink('CHUANYUN://speedtest')?.quick, MuseQuickAction.speedtest);
      expect(museParseDeepLink('chuanyun://connect')?.quick, isNull);
      expect(museParseDeepLink('chuanyun://connect')?.connect, isTrue);
      expect(museParseDeepLink('chuanyun://nothing'), isNull);
    });

    test('the router hands them to the same code as the app buttons; Android shortcuts point at them', () {
      final router = _src('lib/core/router/go_router/routing_config_notifier.dart');
      expect(router, contains('museRunQuickAction(ref, quick)'));
      expect(router, contains("quick == MuseQuickAction.speedtest ? '/nodes' : '/home'"));
      final qa = _src('lib/features/muse/home/quick_actions.dart');
      expect(qa, contains('MuseDesktopAction.toggleMode'));
      expect(qa, contains('showAddProfile(action: MuseAddAction.qr)'));
      expect(qa, contains('.urlTest(group.tag)'));
      expect(qa, isNot(contains('Timer')));
      final sc = _src('android/app/src/main/res/xml/shortcuts.xml');
      for (final l in ['chuanyun://mode', 'chuanyun://scan', 'chuanyun://speedtest']) {
        expect(sc, contains(l));
      }
      final strings = _src('android/app/src/main/res/values/strings.xml');
      expect(strings, contains('切换规则/全局'));
      expect(strings, contains('扫码添加'));
    });
  });

  group('#7 解锁检测', () {
    test('Netflix: licensed title shown = 可用 with region; 404 on both = 仅自制剧; 403 = 不支持', () {
      final ok = museNetflixVerdict(const MuseHttpAnswer(200, body: '"requestCountry":{"id":"HK","x":1}'), null);
      expect(ok.state, MuseSvcState.ok);
      expect(ok.region, 'HK');
      final redirect = museNetflixVerdict(const MuseHttpAnswer(301, location: 'https://www.netflix.com/sg-zh/title/81280792'), null);
      expect(redirect.state, MuseSvcState.ok);
      expect(redirect.region, 'SG');
      expect(museNetflixVerdict(const MuseHttpAnswer(404), const MuseHttpAnswer(404)).state, MuseSvcState.originals);
      expect(museNetflixVerdict(const MuseHttpAnswer(404), const MuseHttpAnswer(200)).state, MuseSvcState.ok);
      expect(museNetflixVerdict(const MuseHttpAnswer(403), null).state, MuseSvcState.unsupported);
      expect(museNetflixVerdict(null, null).state, MuseSvcState.failed);
    });

    test('YouTube Premium, Disney+, ChatGPT / Claude, TikTok', () {
      expect(museYoutubeVerdict(const MuseHttpAnswer(200, body: 'Premium is not available in your country')).state, MuseSvcState.unsupported);
      final yt = museYoutubeVerdict(const MuseHttpAnswer(200, body: '{"GL":"JP"}'));
      expect((yt.state, yt.region), (MuseSvcState.ok, 'JP'));
      expect(museDisneyVerdict(const MuseHttpAnswer(302, location: 'https://www.disneyplus.com/unavailable')).state, MuseSvcState.unsupported);
      expect(museDisneyVerdict(const MuseHttpAnswer(200)).state, MuseSvcState.ok);
      final hk = museAiVerdict(const MuseHttpAnswer(200, body: 'fl=1\nloc=HK\ntls=TLSv1.3\n'), null);
      expect((hk.state, hk.region), (MuseSvcState.unsupported, 'HK'));
      final us = museAiVerdict(const MuseHttpAnswer(200, body: 'loc=US\n'), const MuseHttpAnswer(200));
      expect((us.state, us.region), (MuseSvcState.ok, 'US'));
      expect(museAiVerdict(const MuseHttpAnswer(200, body: 'loc=US\n'), const MuseHttpAnswer(403)).state, MuseSvcState.limited);
      expect(museAiVerdict(null, const MuseHttpAnswer(302, location: '/unavailable-in-region')).state, MuseSvcState.unsupported);
      expect(museAiVerdict(null, null).state, MuseSvcState.failed);
      final tt = museRegionPageVerdict(const MuseHttpAnswer(200, body: '"region":"TW"'), RegExp(r'"region":"([A-Z]{2})"'));
      expect((tt.state, tt.region), (MuseSvcState.ok, 'TW'));
    });

    test('museCheckUnlock asks the right pages; others only check the status', () async {
      final asked = <String>[];
      Future<MuseHttpAnswer?> fetch(String url) async {
        asked.add(url);
        if (url.contains('netflix')) return const MuseHttpAnswer(404);
        if (url.endsWith('/cdn-cgi/trace')) return const MuseHttpAnswer(200, body: 'loc=JP\n');
        return const MuseHttpAnswer(204);
      }

      expect((await museCheckUnlock(_svc('netflix'), fetch)).state, MuseSvcState.originals);
      expect(asked, [museNetflixLicensed, museNetflixLicensed2]);
      asked.clear();
      final gpt = await museCheckUnlock(_svc('chatgpt'), fetch);
      expect((gpt.state, gpt.region), (MuseSvcState.ok, 'JP'));
      expect(asked, ['https://chatgpt.com/cdn-cgi/trace']);
      asked.clear();
      expect((await museCheckUnlock(_svc('google'), fetch)).state, MuseSvcState.ok);
      expect(asked, [_svc('google').url]);
    });

    test('labels: 地区 / 仅自制剧 / 不支持 / 受限 in Chinese', () {
      expect(museServiceLabel(MuseSvcState.ok, 120, region: 'HK'), '可用·香港 120 ms');
      expect(museServiceLabel(MuseSvcState.originals, 300), '仅自制剧');
      expect(museServiceLabel(MuseSvcState.unsupported, null, region: 'CN'), '不支持·中国大陆');
      expect(museServiceLabel(MuseSvcState.limited, null), '受限');
      expect(museServiceLabel(MuseSvcState.ok, 80, region: 'ZZ'), '可用·ZZ 80 ms');
      expect(museRegionName('jp'), '日本');
    });

    test('the notifier keeps regions with results and caches them', () async {
      var calls = 0;
      final n = MuseServicesNotifier(
        () => (s) async => 204,
        checker: () => (s) async {
          calls++;
          return (state: s.key == 'netflix' ? MuseSvcState.originals : MuseSvcState.ok, region: s.key == 'youtube' ? 'US' : null);
        },
      );
      await n.check();
      expect(calls, museServices.length);
      expect(n.state.results['netflix'], MuseSvcState.originals);
      expect(n.state.regions['youtube'], 'US');
      await n.check(); // cached
      expect(calls, museServices.length);
      expect(n.state.regions['youtube'], 'US');
      n.dispose();
    });

    test('only a tap checks: no automatic check, no timer', () {
      final src = _src('lib/features/muse/home/dashboard_cards.dart');
      final card = src.substring(src.indexOf('class _ServicesTile'), src.indexOf('class _ServicesSheet'));
      expect(card, isNot(contains('useEffect')));
      expect(card, isNot(contains('Timer')));
      expect(card, contains('check(force: true)'));
      final unlock = _src('lib/features/muse/logic/unlock_check.dart');
      expect(unlock, isNot(contains('Timer')));
      expect(unlock, contains('req.followRedirects = false'));
      expect(unlock, contains('client.close(force: true)'));
    });
  });

  group('测速失败原因', () {
    test('core reason words become short Chinese words; unknown = 超时', () {
      expect(MuseFailReason.parse('refused').word, '拒绝连接');
      expect(MuseFailReason.parse('DNS').word, '解析失败');
      expect(MuseFailReason.parse('handshake').word, '握手失败');
      expect(MuseFailReason.parse('').word, '超时');
      expect(MuseFailReason.parse('something').word, '超时');
      for (final r in MuseFailReason.values) {
        expect(r.word.length, lessThanOrEqualTo(4));
        if (r != MuseFailReason.timeout) expect(r.advice, isNotEmpty);
      }
    });
  });

  group('连接一键加规则', () {
    test('one rule per host, parse / save round trip, remove', () {
      var rules = museSetQuickRule(const [], 'Example.COM ', MuseQuickWay.direct);
      rules = museSetQuickRule(rules, 'example.com', MuseQuickWay.proxy);
      expect(rules, [const MuseQuickRule('example.com', MuseQuickWay.proxy)]);
      expect(museParseQuickRules(museQuickRulesToRaw(rules)), rules);
      expect(museParseQuickRules('not json'), isEmpty);
      expect(museRemoveQuickRule(rules, 'EXAMPLE.com'), isEmpty);
    });

    test('rules go after 局域网 / 屏蔽 and before the user rules; IPs become CIDRs', () {
      final base = [
        Rule(name: museLanRuleName, enabled: true),
        Rule(name: 'mine', enabled: true),
      ];
      final out = museApplyQuickRules(base, const [
        MuseQuickRule('a.com', MuseQuickWay.direct),
        MuseQuickRule('1.2.3.4', MuseQuickWay.proxy),
      ]);
      expect(out.map((r) => r.name), [museLanRuleName, '$museQuickRuleName:direct', '$museQuickRuleName:proxy:ip', 'mine']);
      expect(out[1].domainSuffixes, ['a.com']);
      expect(out[2].ipCidrs, ['1.2.3.4/32']);
      expect([for (final r in out) r.listOrder], [0, 1, 2, 3]);
      expect(museApplyQuickRules(base, const []), same(base));
    });

    test('指定节点: a host moves to the chosen node; 仅本次 wins', () {
      var r = museAddHostToNodeRule(const [], 'JP-1', 'a.com');
      r = museAddHostToNodeRule(r, 'US-1', 'a.com');
      expect(r.length, 1);
      expect(r.single.node, 'US-1');
      final merged = museMergeNodeRules(r, [const MuseNodeRule(node: 'HK-1', domains: ['a.com'])]);
      expect(merged.single.node, 'HK-1');
    });
  });

  group('出口 IP 详情', () {
    test('ip-api and ipwho answers', () {
      final a = museParseIpApi(
        '{"status":"success","query":"1.2.3.4","countryCode":"jp","regionName":"Tokyo","city":"Tokyo","isp":"X","as":"AS2516 KDDI","hosting":true}',
      )!;
      expect((a.ip, a.country, a.asn, a.kind, a.place), ('1.2.3.4', 'JP', 'AS2516', MuseIpKind.hosting, 'Tokyo'));
      expect(museParseIpApi('{"status":"fail"}'), isNull);
      final w = museParseIpWho('{"ip":"2001:db8::1","country_code":"us","connection":{"asn":13335,"isp":"CF"}}')!;
      expect((w.isV6, w.asn, w.isp), (true, 'AS13335', 'CF'));
      expect(museParseIpWho('garbage'), isNull);
      expect(MuseExitDetail.fromJson(a.toJson())!.asn, 'AS2516');
      expect(museExitChanged('', '1.1.1.1'), isNull);
      expect(museExitChanged('1.1.1.1', '2.2.2.2'), isTrue);
    });
  });

  group('自动最快限定地区', () {
    test('filter matches flag or name; empty = every node', () {
      expect(museAutoRegionFilter(''), '');
      expect(museAutoFilterExtras(''), isEmpty);
      expect(museInAutoRegion('🇯🇵 东京 01', 'JP'), isTrue);
      expect(museInAutoRegion('🇭🇰 香港 01', 'JP'), isFalse);
      expect(museInAutoRegion('anything', ''), isTrue);
      expect(museAutoFilterExtras(museAutoRegionFilter('HK')), containsPair('muse-auto-filter', isNotEmpty));
    });
  });

  group('端口被占用自动避让', () {
    test('the saved port when free, else the next free one', () async {
      expect(await musePickMixedPort(7890, isFree: (p) async => true), (7890, false));
      expect(await musePickMixedPort(7890, avoid: {7891}, isFree: (p) async => p == 7891 || p == 7892), (7892, true));
      expect(await musePickMixedPort(7890, isFree: (p) async => false), (7890, false));
      expect(musePortMovedText(7890, 7892), '端口 7890 被占用，本次改用 7892');
    });
  });

  group('系统代理绕过列表', () {
    test('default includes local and LAN; user list is split and deduplicated', () {
      expect(museProxyBypassList(''), museDefaultProxyBypass);
      expect(museDefaultProxyBypass, containsAll(['localhost', '192.168.*', '*.local', '<local>']));
      expect(museProxyBypassList('a.lan\nb.lan; a.lan'), ['a.lan', 'b.lan']);
      expect(museProxyBypassString('x;y'), 'x;y');
    });
  });

  group('订阅更新后自动测新节点', () {
    test('only in front and connected, only the new nodes', () {
      final g = OutboundGroup(tag: 'select', items: [OutboundInfo(tag: 'a'), OutboundInfo(tag: 'b')]);
      expect(museNewNodeTags(g, {'b'}), ['b']);
      expect(museNewNodeTags(null, {'b'}), isEmpty);
      expect(museShouldTestNewNodes(running: true, foreground: true, tags: ['b']), isTrue);
      expect(museShouldTestNewNodes(running: true, foreground: false, tags: ['b']), isFalse);
      expect(museShouldTestNewNodes(running: false, foreground: true, tags: ['b']), isFalse);
    });
  });

  group('剪贴板只在打开「添加」时读取', () {
    test('offer rules', () {
      const link = 'https://sub.example.com/api?token=1';
      expect(museClipboardOfferFor(link, lastOffered: null, subscriptionUrls: const []), link);
      expect(museClipboardOfferFor(link, lastOffered: link, subscriptionUrls: const []), isNull);
      expect(museClipboardOfferFor(link, lastOffered: null, subscriptionUrls: const [link]), isNull);
      expect(museClipboardOfferFor('hello', lastOffered: null, subscriptionUrls: const []), isNull);
    });

    test('coming back to the front only asks whether there is text', () {
      final src = _src('lib/features/muse/home/clipboard_import.dart');
      final watcher = src.substring(src.indexOf('void useMuseClipboardWatcher'), src.indexOf('String? museClipboardOfferFor'));
      expect(watcher, contains('Clipboard.hasStrings()'));
      expect(watcher, isNot(contains('Clipboard.getData')));
    });
  });

  group('界面文案中文化', () {
    // Proper names and technical terms with no common Chinese word may stay; everything else on
    // screen is Chinese. A new English UI string fails here.
    const allowed = {
      'IP', 'IPv4', 'IPv6', 'DNS', 'TUN', 'TCP', 'UDP', 'TLS', 'QUIC', 'HTTP', 'HTTPS', 'SNI', 'JSON', 'UA', 'CDN', 'BT',
      'ASN', 'Fake-IP', 'GeoSite', 'GeoIP', 'hosts', 'Wi', 'Fi', 'AI', 'App', 'Ctrl', 'Alt', 'Win', 'Shift', 'ms', 'MB', 'KB',
      'GPL-3.0', 'GPLv3', 'GNU', 'Hiddify', 'FlClash', 'chen08209', 'sing-box', 'mihomo', 'REALITY', 'VLESS', 'vless', 'ss',
      'Android', 'Windows', 'IPLC', 'HK', 'DOMAIN-SUFFIX', 'Proxy', 'https', 'json', 'srs',
      'Google', 'YouTube', 'Netflix', 'Spotify', 'TikTok', 'Telegram', 'Twitter', 'Meta', 'Facebook', 'Instagram', 'WhatsApp',
      'Discord', 'Amazon', 'GitHub', 'npm', 'PyPI', 'Docker', 'Hub', 'PayPal', 'Stripe', 'Steam', 'QQ', 'ChatGPT', 'Claude',
      'Gemini', 'Disney+', 'HBO', 'Prime', 'Video',
      // 1.13.0: VPN has no common Chinese word (连不上诊断「其他 VPN」、「已被其他 VPN 断开」)
      'VPN',
      // 1.14.0 R21: transport name in 手动添加节点 (no common Chinese word)
      'WebSocket',
      // 1.18.0 P7: the bundled font and its licence (关于 › 开源许可与致谢)
      'Inter', 'SIL',
      // 1.20.0: the map data credited on 关于 › 开源许可与致谢 (a proper name, public domain)
      'Natural', 'Earth',
    };
    final ui = RegExp(
      r'''(?:\bText\(|\b(?:title|label|tooltip|hintText|labelText|helperText|subtitle|header|footer|message|hint|semanticsLabel)\s*:|\bshow(?:Success|Error|Info)Toast\(|\bmuseAskText\(\s*context\s*,)\s*(?:const\s+)?(?:Text\(\s*)?(['"])((?:\\.|(?!\1).)*?)\1''',
    );
    final word = RegExp(r'[A-Za-z][A-Za-z0-9]*(?:[-+.][A-Za-z0-9]+)*\+?');

    test('no plain-English text on screen (proper names allowed)', () {
      final bad = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final p = f.path.replaceAll(r'\', '/');
        if (!p.endsWith('.dart') || p.contains('/gen/') || p.contains('/generated/') || p.endsWith('.g.dart') || p.endsWith('.freezed.dart')) {
          continue;
        }
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.trimLeft().startsWith('//')) continue;
          for (final m in ui.allMatches(l)) {
            final raw = m.group(2)!;
            if ('{'.allMatches(raw).length != '}'.allMatches(raw).length) continue; // cut inside an interpolation
            final text = raw.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), '');
            for (final w in word.allMatches(text).map((e) => e.group(0)!)) {
              if (w.replaceAll(RegExp('[^A-Za-z]'), '').length < 2) continue;
              if (allowed.contains(w) || w.contains('.')) continue; // names, domains, file names
              bad.add('$p:${i + 1}: $w  «${m.group(2)}»');
            }
          }
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('replaced English', () {
      expect(_src('lib/features/route_rules/notifier/generic_list_notifier.dart'), isNot(contains('Value is exist')));
      expect(_src('lib/hiddifycore/hiddify_core_service.dart'), isNot(contains('"failed to start core')));
      expect(_src('lib/hiddifycore/core_interface/core_interface_mobile.dart'), isNot(contains('starting background core')));
      expect(_src('lib/features/muse/settings/resources_page.dart'), contains("header: '地理规则库'"));
    });
  });

  group('版本 1.12.0', () {
    test('pubspec and changelog', () {
      expect(_src('pubspec.yaml'), matches(RegExp(r'version: 1\.[1-9]\d\.'))); // 1.20.0: 1.1x and later (1.2x no longer contains 「1.1」) // 1.12.x or later
      final lines = museChangelog['1.12.0']!;
      expect(museChangelog.keys, contains('1.12.0'));
      expect(lines.join(), contains('解锁'));
      expect(lines.join(), contains('快捷方式'));
      expect(_src('CHANGELOG.md'), contains('### 1.12.0'));
    });
  });
}
