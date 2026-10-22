// 穿云 1.4.0: node tools, subscription tools, 分流 presets / tester, sync merge + encryption,
// statistics, network helpers.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

void main() {
  group('节点工具', () {
    test('rename / note / hide survive by tag, round trip', () {
      var m = MuseNodeMetas.empty.set('a', const MuseNodeMeta(rename: '家宽', note: '晚上快'));
      m = m.setHidden(['b', 'c'], true);
      final back = MuseNodeMetas.parse(m.toRaw());
      expect(back.of('a').rename, '家宽');
      expect(back.of('a').note, '晚上快');
      expect(back.hiddenTags, {'b', 'c'});
      expect(back.displayName('a', '🇯🇵 东京 01'), '家宽');
      expect(back.displayName('x', '🇯🇵 东京 01'), '🇯🇵 东京 01');
      expect(back.setHidden(['b'], false).hiddenTags, {'c'});
      expect(back.set('a', const MuseNodeMeta()).byTag.containsKey('a'), isFalse);
      expect(MuseNodeMetas.parse('nope').byTag, isEmpty);
    });
    test('beautify names', () {
      expect(museBeautifyNodeName('🇭🇰🇭🇰 香港 | IPLC_01'), '🇭🇰 香港 · IPLC · 01');
      expect(museBeautifyNodeName('[官网 xx.com] 日本 02'), '日本 02');
      expect(museBeautifyNodeName('   '), '');
      expect(museBeautifyNodeName('美国|CF官方优选47'), '美国 · CF官方优选47');
    });
    test('include / exclude regex filter', () {
      expect(museNodeNamePasses('香港 01', include: '香港|日本'), isTrue);
      expect(museNodeNamePasses('美国 01', include: '香港|日本'), isFalse);
      expect(museNodeNamePasses('香港 到期', exclude: '到期|剩余'), isFalse);
      expect(museNodeNamePasses('香港', include: '(bad'), isTrue);
      expect(museNodeFilterError('(bad'), isNotNull);
      expect(museNodeFilterError('ok|fine'), isNull);
    });
    test('duplicates by protocol + address + port', () {
      final nodes = [('a', 'vless', 'h.com', 443), ('b', 'vless', 'H.com', 443), ('c', 'vmess', 'h.com', 443), ('d', 'vless', '', 0), ('e', 'vless', '', 0)];
      expect(
        museDuplicateTags(nodes, tag: (e) => e.$1, type: (e) => e.$2, host: (e) => e.$3, port: (e) => e.$4),
        {'b'},
      );
    });
    test('history, loss, jitter and health', () {
      var h = const MuseDelayHistory([]);
      for (final d in [100, 120, 0, 110, 100]) {
        h = h.add(d);
      }
      expect(h.answered, 4);
      expect(h.loss, closeTo(0.2, 1e-9));
      expect(h.median, 110);
      expect(h.jitter, closeTo((20 + 10 + 10) / 3, 1e-9));
      final score = museHealthScore(h)!;
      expect(score, inInclusiveRange(60, 80));
      expect(museHealthScore(const MuseDelayHistory([])), isNull);
      expect(museHealthScore(const MuseDelayHistory([0, 0])), 0);
      expect(museHealthScore(const MuseDelayHistory([60, 60, 60])), 100);
      expect(museHealthLabel(90), '优');
      var many = const MuseDelayHistory([]);
      for (var i = 0; i < 30; i++) {
        many = many.add(i + 1);
      }
      expect(many.samples.length, MuseDelayHistory.keep);
      final hs = MuseDelayHistories.empty.add('p', {'a': 100, 'b': 65535});
      final back = MuseDelayHistories.parse(hs.toRaw());
      expect(back.of('a').samples, [100]);
      expect(back.of('b').samples, [0]);
      expect(back.add('q', {'x': 1}).of('a').samples, isEmpty);
    });
    test('country groups with their best delay, 其他 last', () {
      final g = museCountryGroups<(String, String?, int)>(
        [('a', 'JP', 200), ('b', null, 50), ('c', 'JP', 120), ('d', 'US', 65535)],
        region: (e) => e.$2,
        delay: (e) => e.$3,
      );
      expect(g.map((e) => e.code), ['JP', 'US', null]);
      expect(g.first.bestDelay, 120);
      expect(g[1].bestDelay, 0);
      expect(g.last.items.single.$1, 'b');
    });
    test('recent and region mismatch', () {
      expect(museAddRecent(['a', 'b', 'c'], 'b'), ['b', 'a', 'c']);
      expect(museAddRecent(['a', 'b', 'c', 'd', 'e'], 'f'), ['f', 'a', 'b', 'c', 'd']);
      expect(museParseRecent('a, b,,c'), ['a', 'b', 'c']);
      expect(museRegionMismatch(nameRegion: 'JP', exitRegion: 'us'), isTrue);
      expect(museRegionMismatch(nameRegion: 'HK', exitRegion: 'HK'), isFalse);
      expect(museRegionMismatch(nameRegion: null, exitRegion: 'US'), isFalse);
    });
  });

  group('订阅工具', () {
    test('formats', () {
      expect(museDetectSubFormat('proxies:\n  - name: a'), MuseSubFormat.clash);
      expect(museDetectSubFormat('{"outbounds": []}'), MuseSubFormat.singBox);
      expect(museDetectSubFormat('{"servers": [{"server": "a"}]}'), MuseSubFormat.sip008);
      expect(museDetectSubFormat('vless://a@b:443#x\ntrojan://p@c:443#y'), MuseSubFormat.links);
      final b64 = base64.encode(utf8.encode('vmess://abc\nss://def'));
      expect(museDetectSubFormat(b64), MuseSubFormat.base64);
      expect(museDetectSubFormat('<html>nope</html>'), MuseSubFormat.unknown);
      expect(museDetectSubFormat(''), MuseSubFormat.unknown);
    });
    test('diff', () {
      final d = museSubDiff(['a', 'b', 'c'], ['b', 'c', 'd']);
      expect(d.added, ['d']);
      expect(d.removed, ['a']);
      expect(d.kept, 2);
      expect(d.summary, '新增 1 · 移除 1 · 保留 2');
      expect(museSubDiff(['a'], ['a']).summary, '节点没有变化');
    });
    test('reminders at 3 days / 10 %', () {
      final now = DateTime(2026, 10, 22);
      expect(museSubReminders(total: 100, used: 95, expire: now.add(const Duration(days: 2)), now: now), {
        MuseSubReminder.expiresSoon,
        MuseSubReminder.trafficLow,
      });
      expect(museSubReminders(total: 100, used: 50, expire: now.add(const Duration(days: 10)), now: now), isEmpty);
      expect(museSubReminders(total: 100, used: 100, expire: now.subtract(const Duration(days: 1)), now: now), {
        MuseSubReminder.expired,
        MuseSubReminder.trafficOut,
      });
      expect(museSubReminders(total: 0, used: 5, expire: DateTime(1970), now: now), isEmpty);
    });
    test('chuanyun:// links and QR payload', () {
      final l = museParseDeepLink('chuanyun://import?url=https%3A%2F%2Fa.com%2Fsub%3Ft%3D1&name=%E5%AE%B6')!;
      expect(l.url, 'https://a.com/sub?t=1');
      expect(l.name, '家');
      expect(museParseDeepLink('chuanyun://install-config?url=https://b.com/s')!.url, 'https://b.com/s');
      expect(museParseDeepLink('chuanyun://import/https%3A%2F%2Fc.com%2Fs#我的')!.url, 'https://c.com/s');
      final c = museParseDeepLink('chuanyun://connect?node=JP')!;
      expect(c.connect, isTrue);
      expect(c.node, 'JP');
      expect(museParseDeepLink('hiddify://x'), isNull);
      expect(museParseDeepLink('chuanyun://import?url=javascript:alert(1)'), isNull);
      final qr = museSubscriptionQrPayload('https://a.com/s?x=1', name: '家');
      expect(museParseDeepLink(qr)!.url, 'https://a.com/s?x=1');
      expect(museParseDeepLink(qr)!.name, '家');
    });
    test('UA and masked link', () {
      expect(museUserAgentFor('auto', appVersion: '1.4.0'), isNull);
      expect(museUserAgentFor('clash', appVersion: '1.4.0'), contains('clash'));
      expect(museMaskSubUrl('https://sub.example.com/api/v1/client/subscribe?token=abc'), 'https://sub.example.com/••••?••••');
      expect(museMaskSubUrl('nope'), '••••');
    });
  });

  group('分流', () {
    Rule rule(String name, Outbound o, {List<String> suffix = const [], int order = 0, List<String> cidr = const [], List<String> ports = const [], List<String> proc = const []}) =>
        Rule(name: name, enabled: true, outbound: o, listOrder: order, domainSuffixes: suffix, ipCidrs: cidr, portRanges: ports, processNames: proc);

    test('presets: own rules first, then presets, then built-in; orders renumbered', () {
      final rules = [
        rule('builtin:bypassLan', Outbound.direct, cidr: ['10.0.0.0/8']),
        rule('mine', Outbound.block, suffix: ['bad.com'], order: 1),
        rule('builtin:bypassRegion', Outbound.direct, order: 2),
      ];
      final out = museApplyPresets(rules, {'ai': Outbound.proxy, 'banks': Outbound.direct});
      expect(out.map((r) => r.name), ['mine', 'preset:ai', 'preset:banks', 'builtin:bypassLan', 'builtin:bypassRegion']);
      expect(out.map((r) => r.listOrder), [0, 1, 2, 3, 4]);
      expect(museApplyPresets(rules, const {}), same(rules));
      // the input is not changed
      expect(rules[1].listOrder, 1);
    });
    test('preset choice round trip, unknown keys dropped', () {
      final raw = musePresetChoiceToRaw({'ai': Outbound.proxy, 'apple': Outbound.direct});
      expect(museParsePresetChoice(raw), {'ai': Outbound.proxy, 'apple': Outbound.direct});
      expect(museParsePresetChoice('{"nope": "proxy", "telegram": "weird"}'), {'telegram': Outbound.proxy});
      expect(museRulePresets.length, greaterThanOrEqualTo(25)); // 1.4.1: more presets
    });
    test('tester walks the list like the core', () {
      final rules = museApplyPresets([
        rule('mine', Outbound.direct, suffix: ['example.com']),
        rule('ports', Outbound.block, ports: ['25', '1000:2000']),
        rule('exe', Outbound.direct, proc: ['game.exe']),
      ], {'ai': Outbound.proxy, 'telegram': Outbound.proxy});
      expect(museTestRules(rules, 'https://www.example.com/x').rule!.name, 'mine');
      expect(museTestRules(rules, 'https://chatgpt.com').rule!.name, 'preset:ai');
      expect(museTestRules(rules, '149.154.167.51').rule!.name, 'preset:telegram');
      expect(museTestRules(rules, 'smtp.foo.org', port: 25).outbound, Outbound.block);
      expect(museTestRules(rules, 'http://foo.org:1500').outbound, Outbound.block);
      expect(museTestRules(rules, 'foo.org', process: 'Game.exe').rule!.name, 'exe');
      final none = museTestRules(rules, 'unknown.net');
      expect(none.rule, isNull);
      expect(none.outbound, Outbound.proxy);
      expect(museIpInCidr('192.168.1.5', '192.168.0.0/16'), isTrue);
      expect(museIpInCidr('192.169.1.5', '192.168.0.0/16'), isFalse);
      expect(museIpInCidr('::1', '::/0'), isFalse);
    });
    test('hosts, import / export, rule-set links', () {
      expect(museParseHosts('# c\n1.2.3.4 a.com b.com\nbad line\n::1 v6.local\n5.6.7.8'), {'a.com': '1.2.3.4', 'b.com': '1.2.3.4', 'v6.local': '::1'});
      final rules = [rule('builtin:bypassLan', Outbound.direct), rule('mine', Outbound.block, suffix: ['x.com'])];
      final text = museExportRules(rules);
      final back = museImportRules(text);
      expect(back.single.name, 'mine');
      expect(back.single.domainSuffixes, ['x.com']);
      expect(back.single.outbound, Outbound.block);
      expect(() => museImportRules('{"x": 1}'), throwsFormatException);
      expect(museIsRuleSetUrl('https://a.com/geosite-openai.srs'), isTrue);
      expect(museIsRuleSetUrl('https://a.com/list.txt'), isFalse);
      expect(museIsRuleSetUrl('ftp://a.com/x.srs'), isFalse);
    });
  });

  group('同步 / 备份', () {
    test('stamp, merge field by field, latest wins, deletions', () {
      final last = MuseSnapshot({'a': const MuseSyncEntry(1, 100), 'b': const MuseSyncEntry('x', 100), 'gone': const MuseSyncEntry(true, 100)});
      final local = museStampLocal(current: {'a': 1, 'b': 'y', 'new': 5}, lastSynced: last, now: 200);
      expect(local.entries['a'], const MuseSyncEntry(1, 100));
      expect(local.entries['b'], const MuseSyncEntry('y', 200));
      expect(local.entries['new'], const MuseSyncEntry(5, 200));
      expect(local.entries['gone'], const MuseSyncEntry(null, 200));
      final remote = MuseSnapshot({'a': const MuseSyncEntry(2, 150), 'b': const MuseSyncEntry('z', 150), 'r': const MuseSyncEntry(9, 120)});
      final merged = museMergeSnapshots(local, remote);
      expect(merged.entries['a']!.value, 2);
      expect(merged.entries['b']!.value, 'y');
      expect(merged.entries['r']!.value, 9);
      expect(merged.values.containsKey('gone'), isFalse);
      expect(museSyncChanges({'a': 1, 'b': 'y', 'new': 5, 'gone': true}, merged), {'a': 2, 'r': 9, 'gone': null});
      final back = MuseSnapshot.fromJson(jsonDecode(jsonEncode(merged.toJson())) as Map<String, dynamic>);
      expect(back.entries, merged.entries);
    });
    test('same time: the local value stays', () {
      final l = MuseSnapshot({'k': const MuseSyncEntry('l', 5)});
      final r = MuseSnapshot({'k': const MuseSyncEntry('r', 5)});
      expect(museMergeSnapshots(l, r).entries['k']!.value, 'l');
    });
    test('redaction drops links and passwords', () {
      final s = MuseSnapshot({'sub:1': const MuseSyncEntry('https://x', 1), 'webdav_user': const MuseSyncEntry('u', 1), 'pref:muse_accent': const MuseSyncEntry('blue', 1)});
      expect(museRedactSnapshot(s).entries.keys, ['pref:muse_accent']);
    });
    test('AES-GCM round trip, wrong password, tamper', () {
      final enc = museEncrypt('你好 sync', 'pw', iterations: 1000, random: Random(1));
      expect(museIsEncrypted(enc), isTrue);
      expect(museIsEncrypted('{"a":1}'), isFalse);
      expect(museDecrypt(enc, 'pw'), '你好 sync');
      expect(() => museDecrypt(enc, 'nope'), throwsA(isA<MuseCryptoException>()));
      final j = jsonDecode(enc) as Map<String, dynamic>;
      final data = base64.decode(j['data'] as String);
      data[0] ^= 1;
      j['data'] = base64.encode(data);
      expect(() => museDecrypt(jsonEncode(j), 'pw'), throwsA(isA<MuseCryptoException>()));
      expect(() => museEncrypt('x', ''), throwsA(isA<MuseCryptoException>()));
      // a new salt / nonce each time
      expect(museEncrypt('x', 'pw', iterations: 1000), isNot(museEncrypt('x', 'pw', iterations: 1000)));
    });
  });

  group('统计', () {
    test('traffic per day, months, report', () {
      var log = MuseTrafficLog.empty;
      log = log.add(DateTime(2026, 10, 21), 10, 90).add(DateTime(2026, 10, 22), 5, 50).add(DateTime(2026, 10, 22), 5, 50);
      log = log.add(DateTime(2026, 9, 30), 1, 1).add(DateTime(2026, 10, 22), 0, 0);
      final back = MuseTrafficLog.parse(log.toRaw());
      expect(back.days['2026-10-22'], (10, 100));
      final last = back.lastDays(DateTime(2026, 10, 22), 3);
      expect(last.map((e) => e.$1), ['2026-10-20', '2026-10-21', '2026-10-22']);
      expect(last.first.$3, 0);
      expect(back.months(), [('2026-09', 1, 1), ('2026-10', 20, 190)]);
      final r = museMonthlyReport(back, '2026-10', bytes: (b) => '$b B');
      expect(r.first, '2026-10 共用 210 B（↑ 20 B  ↓ 190 B）');
      expect(r.last, contains('10-22'));
      expect(museMonthlyReport(back, '2025-01', bytes: (b) => '$b').single, contains('还没有'));
    });
    test('session counter turns totals into deltas', () {
      final c = MuseTrafficCounter();
      // 1.4.1: the first sample is the baseline (a running session was counted before)
      expect(c.delta(100, 200), (0, 0));
      expect(c.delta(150, 260), (50, 60));
      expect(c.delta(10, 20), (10, 20)); // new session
    });
    test('connect success rate', () {
      var s = MuseConnectStats.empty;
      s = s.record(DateTime(2026, 10, 22), ok: true).record(DateTime(2026, 10, 22), ok: false).record(DateTime(2026, 10, 21), ok: true);
      expect(MuseConnectStats.parse(s.toRaw()).rate(DateTime(2026, 10, 22)), closeTo(2 / 3, 1e-9));
      expect(MuseConnectStats.empty.rate(DateTime(2026, 10, 22)), isNull);
    });
    test('top lists and crash log', () {
      expect(museTop({'a': 5, 'b': 50, 'c': 0}).map((e) => e.key), ['b', 'a']);
      var log = <MuseCrash>[];
      for (var i = 0; i < 40; i++) {
        log = museAddCrash(log, MuseCrash(DateTime(2026, 10, 22, 0, i), 'e$i', List.filled(50, 'line').join('\n')));
      }
      expect(log.length, 30);
      expect(log.first.message, 'e10');
      expect(log.last.stack.split('\n').length, 24);
      expect(museParseCrashes(museCrashesToRaw(log)).length, 30);
      expect(museParseCrashes('x'), isEmpty);
    });
  });

  group('连接与网络', () {
    test('DNS presets and addresses', () {
      expect(museDnsPreset('cf-doh').address, 'https://1.1.1.1/dns-query');
      expect(museDnsPreset('nope').key, 'default');
      expect(museIsValidDnsAddress('tls://1.1.1.1'), isTrue);
      expect(museIsValidDnsAddress('quic://dns.adguard.com'), isTrue);
      expect(museIsValidDnsAddress('8.8.8.8'), isTrue);
      expect(museIsValidDnsAddress('ftp://x'), isFalse);
    });
    test('ports', () {
      expect(musePortError(80), isNotNull);
      expect(musePortError(12334, others: [12334]), isNotNull);
      expect(musePortError(12335, others: [12334]), isNull);
      expect(musePortError(null), isNotNull);
    });
    test('Wi‑Fi rules respect a manual disconnect', () {
      final r = museParseWifiRules(museWifiRulesToRaw({'Home': MuseWifiAction.disconnect, 'Cafe': MuseWifiAction.connect}));
      expect(museWifiDecide(r, 'Home', running: true, userStopped: false), MuseWifiAction.disconnect);
      expect(museWifiDecide(r, 'Home', running: false, userStopped: false), MuseWifiAction.none);
      expect(museWifiDecide(r, 'Cafe', running: false, userStopped: false), MuseWifiAction.connect);
      expect(museWifiDecide(r, 'Cafe', running: false, userStopped: true), MuseWifiAction.none);
      expect(museWifiDecide(r, null, running: true, userStopped: false), MuseWifiAction.none);
    });
    test('schedule fires once per minute mark', () {
      final s = MuseSchedule.parse(const MuseSchedule(connectAt: 8 * 60, disconnectAt: 23 * 60).toRaw());
      expect(museScheduleDue(s, DateTime(2026, 1, 1, 8), lastFired: -1, running: false), MuseWifiAction.connect);
      expect(
        museScheduleDue(s, DateTime(2026, 1, 1, 8), lastFired: museEpochMinute(DateTime(2026, 1, 1, 8)), running: false),
        MuseWifiAction.none,
      );
      expect(museScheduleDue(s, DateTime(2026, 1, 1, 23), lastFired: -1, running: true), MuseWifiAction.disconnect);
      expect(museScheduleDue(s, DateTime(2026, 1, 1, 23), lastFired: -1, running: false), MuseWifiAction.none);
      expect(MuseSchedule.parse('').isOff, isTrue);
      expect(museMinuteLabel(8 * 60 + 5), '08:05');
    });
    test('quality watch alerts once per bad spell', () {
      final q = MuseQualityWatch(window: 3, slowMs: 500);
      expect([q.add(100), q.add(900), q.add(0)], [false, false, true]);
      expect(q.add(0), isFalse);
      expect([q.add(100), q.add(100), q.add(100)], [false, false, false]);
      expect([q.add(0), q.add(0)], [false, true]);
    });
    test('bypass list and CLI args', () {
      expect(museBypassList('localhost\n10.*; 192.168.*\nlocalhost'), 'localhost;10.*;192.168.*');
      final a = museParseCliArgs(['--node', '东京 01', '--silent']);
      expect(a.connect, isTrue);
      expect(a.node, '东京 01');
      expect(a.silent, isTrue);
      expect(museParseCliArgs(['--node=JP']).node, 'JP');
      expect(museParseCliArgs(['--disconnect']).disconnect, isTrue);
      expect(museParseCliArgs(const []).isEmpty, isTrue);
    });
    test('update asset per ABI and beta channel', () {
      expect(museApkAssetsFor('arm64-v8a').first, 'Chuanyun-Android-arm64.apk');
      expect(museApkAssetsFor('armeabi-v7a'), ['Chuanyun-Android-universal.apk']);
      final list = [
        {'tag_name': 'v1.5.0-beta1', 'prerelease': true},
        {'tag_name': 'v1.4.1', 'draft': true},
        {'tag_name': 'v1.4.0'},
      ];
      expect(musePickRelease(list, beta: false)!['tag_name'], 'v1.4.0');
      expect(musePickRelease(list, beta: true)!['tag_name'], 'v1.5.0-beta1');
      expect(musePickRelease(const [], beta: true), isNull);
    });
  });
}
