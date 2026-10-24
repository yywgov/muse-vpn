// 穿云 1.4.1: bug-sweep regressions (traffic double count, schedule next day, sync first-join /
// deleted subscriptions / crafted iteration counts, stats chart), 局域网同步 (pairing, encryption,
// a real exchange over the LAN), more 分流 presets (bundled rule-sets, order, sections, search),
// 指定节点 / 远程规则集, update mirrors + Beta 通道, 睡眠唤醒复查, 残留系统代理, 时间校验,
// 诊断向导, Android 后台被杀检测 + 机型指引, 订阅 10 % 提醒 / 更新差异, 命令行参数 / 控制链接.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/bundled_rule_sets.dart';
import 'package:hiddify/features/muse/data/lan_sync_service.dart';
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/logic/android_keepalive.dart';
import 'package:hiddify/features/muse/logic/core_extras.dart';
import 'package:hiddify/features/muse/logic/diagnosis.dart';
import 'package:hiddify/features/muse/logic/lan_sync.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// An in-memory device for the LAN exchange (only what the LAN code uses).
class _FakeSync implements MuseSyncService {
  _FakeSync(this.values);

  Map<String, Object?> values;
  MuseSnapshot last = MuseSnapshot.empty;
  int applied = 0;

  @override
  MuseSnapshot lastSynced() => last;

  @override
  Future<MuseSnapshot> stampedLocal({Set<String> remoteKeys = const {}, int? now}) async => museStampLocal(
    current: values,
    lastSynced: last,
    now: now ?? DateTime.now().millisecondsSinceEpoch,
    remoteKeys: remoteKeys,
  );

  @override
  Future<MuseSyncResult> applyMerged(MuseSnapshot merged) async {
    final changes = museSyncChanges(values, merged);
    final next = {...values};
    changes.forEach((k, v) {
      if (k.startsWith('sub:')) {
        if (v != null) next[k] = v; // never deleted
      } else if (v == null) {
        next.remove(k);
      } else {
        next[k] = v;
      }
    });
    values = next;
    last = merged;
    applied++;
    return MuseSyncResult(changed: changes.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('bug sweep', () {
    test('traffic: a session already running at start-up is not counted twice', () {
      final c = MuseTrafficCounter();
      // the app (re)starts while the core has carried 5 GB this session
      expect(c.delta(5 << 30, 1 << 30), (0, 0));
      expect(c.delta((5 << 30) + 100, (1 << 30) + 50), (100, 50));
      c.reset();
      expect(c.delta(10, 10), (0, 0));
      expect(c.delta(30, 15), (20, 5));
      expect(c.delta(-5, -5), (0, 0)); // garbage never adds negative bytes
    });

    test('schedule: fires again on the next day at the same time, once per day', () {
      const s = MuseSchedule(connectAt: 8 * 60, disconnectAt: 23 * 60 + 30);
      final day1 = DateTime(2026, 10, 22, 8);
      expect(museScheduleDue(s, day1, lastFired: -1, running: false), MuseWifiAction.connect);
      final fired = museScheduleSlot(s, day1, MuseWifiAction.connect);
      expect(museScheduleDue(s, day1.add(const Duration(seconds: 40)), lastFired: fired, running: false), MuseWifiAction.none);
      // the old minute-of-day memory never fired again here
      expect(museScheduleDue(s, DateTime(2026, 10, 23, 8), lastFired: fired, running: false), MuseWifiAction.connect);
      // a late tick (drift) still fires within the grace, not long after
      expect(museScheduleDue(s, DateTime(2026, 10, 23, 8, 1, 30), lastFired: fired, running: false), MuseWifiAction.connect);
      expect(museScheduleDue(s, DateTime(2026, 10, 23, 8, 5), lastFired: fired, running: false), MuseWifiAction.none);
      expect(museScheduleDue(s, DateTime(2026, 10, 22, 23, 30), lastFired: fired, running: true), MuseWifiAction.disconnect);
      expect(museScheduleDue(const MuseSchedule(), day1, lastFired: -1, running: false), MuseWifiAction.none);
    });

    test('sync: a device that never synced takes the existing values', () {
      final remote = MuseSnapshot({'muse_accent': const MuseSyncEntry('purple', 1000)});
      final fresh = museStampLocal(
        current: {'muse_accent': 'blue', 'muse_hosts': '1.1.1.1 a.com'},
        lastSynced: MuseSnapshot.empty,
        now: 5000,
        remoteKeys: remote.entries.keys.toSet(),
      );
      final merged = museMergeSnapshots(fresh, remote);
      expect(merged.entries['muse_accent']!.value, 'purple');
      expect(merged.entries['muse_hosts']!.value, '1.1.1.1 a.com'); // only here: kept
    });

    test('sync: a subscription deleted elsewhere is not brought back', () {
      // last merge says the other device deleted it; this device still has it (never deletes)
      final last = MuseSnapshot({'sub:https://a/sub': const MuseSyncEntry(null, 2000)});
      final local = museStampLocal(current: {'sub:https://a/sub': 'A'}, lastSynced: last, now: 9000);
      expect(local.entries['sub:https://a/sub']!.value, isNull);
      expect(local.entries['sub:https://a/sub']!.at, 2000);
      // a setting re-set after a deletion does come back
      final last2 = MuseSnapshot({'muse_hosts': const MuseSyncEntry(null, 2000)});
      expect(museStampLocal(current: {'muse_hosts': 'x'}, lastSynced: last2, now: 9000).entries['muse_hosts']!.at, 9000);
    });

    test('decrypt: the iteration count read from a file is bounded', () {
      final env = jsonDecode(museEncrypt('hi', 'pw', iterations: 2000)) as Map<String, dynamic>;
      expect(museDecrypt(jsonEncode(env), 'pw'), 'hi');
      // a crafted file asking for a billion rounds is clamped
      expect(museClampIterations(1000000000), museMaxIterations);
      expect(museClampIterations(1), museMinIterations);
      expect(museClampIterations(60000), 60000);
      env['iter'] = 1; // too few: clamped up, so the key differs → refused, never silently weak
      expect(() => museDecrypt(jsonEncode(env), 'pw'), throwsA(isA<MuseCryptoException>()));
    });
  });

  group('局域网同步', () {
    test('keys: 160 bits, unambiguous alphabet, typed forms accepted', () {
      final k = museNewLanKey(Random(1));
      expect(k.length, 32);
      expect(RegExp(r'^[A-HJ-NP-Z2-9]+$').hasMatch(k), isTrue);
      expect(museNormalizeKey(museGroupKey(k).toLowerCase()), k);
      expect(museNormalizeKey(' ${museGroupKey(k)} '), k);
      expect(museNormalizeKey('short'), isNull);
      expect(museNormalizeKey('${k.substring(0, 31)}0'), isNull); // 0 is not in the alphabet
      expect(museNewLanKey(), isNot(museNewLanKey()));
    });

    test('pairing: QR link and typed code round trip, LAN only', () {
      final now = DateTime(2026, 10, 22, 20);
      final p = MuseLanPairing(
        host: '192.168.1.5',
        port: 43125,
        key: museNewLanKey(Random(2)),
        expiresAt: now.add(museLanPairingTtl).millisecondsSinceEpoch,
        device: 'Windows · DESKTOP-1',
      );
      final back = museParseLanPairing(p.toUri())!;
      expect((back.host, back.port, back.key, back.device), (p.host, p.port, p.key, p.device));
      expect(back.expiresAt ~/ 1000, p.expiresAt ~/ 1000);
      expect(back.expired(now), isFalse);
      expect(back.expired(now.add(const Duration(minutes: 4))), isTrue);
      final typed = museParseLanPairing(p.manualCode, now: now)!;
      expect((typed.host, typed.port, typed.key), (p.host, p.port, p.key));
      // public or loopback addresses are refused
      expect(museParseLanPairing(p.toUri().replaceFirst('192.168.1.5', '8.8.8.8')), isNull);
      expect(museParseLanPairing('127.0.0.1:43125 ${museGroupKey(p.key)}'), isNull);
      expect(museParseLanPairing('https://example.com'), isNull);
      expect(museParseLanPairing(''), isNull);
    });

    test('private addresses and the interface to listen on', () {
      for (final ip in ['10.0.0.2', '172.16.4.245', '172.31.255.1', '192.168.50.9', '169.254.3.3']) {
        expect(museIsLanAddress(ip), isTrue, reason: ip);
      }
      for (final ip in ['172.32.0.1', '8.8.8.8', '100.64.0.1', '127.0.0.1', '0.0.0.0', '1.2.3', 'x']) {
        expect(museIsLanAddress(ip), isFalse, reason: ip);
      }
      expect(
        musePickLanAddress([('vEthernet (WSL)', '172.20.0.1'), ('Wintun 穿云', '172.19.0.1'), ('WLAN', '192.168.1.8'), ('lo', '127.0.0.1')]),
        '192.168.1.8',
      );
      expect(musePickLanAddress([('vEthernet (WSL)', '172.20.0.1'), ('Ethernet', '10.1.2.3')]), '10.1.2.3');
      expect(musePickLanAddress([('lo', '127.0.0.1'), ('ppp0', '100.70.1.1')]), isNull);
    });

    test('messages: sealed with the key, refused with another key, session or type', () {
      final key = museNewLanKey(Random(3));
      final now = DateTime.now();
      final m = MuseLanMessage(
        type: 'push',
        session: museLanSession(key),
        at: now.millisecondsSinceEpoch,
        device: 'A',
        snapshot: MuseSnapshot({'muse_accent': const MuseSyncEntry('green', 5)}),
      );
      final sealed = museLanSeal(m, key);
      expect(sealed.contains('green'), isFalse);
      expect(museLanOpen(sealed, key, expectType: 'push', now: now).snapshot.values['muse_accent'], 'green');
      expect(() => museLanOpen(sealed, museNewLanKey(Random(4)), expectType: 'push', now: now), throwsA(isA<MuseLanException>()));
      expect(() => museLanOpen(sealed, key, expectType: 'merged', now: now), throwsA(isA<MuseLanException>()));
      expect(
        () => museLanOpen(sealed, key, expectType: 'push', now: now.add(const Duration(minutes: 10))),
        throwsA(isA<MuseLanException>()),
      );
      final other = museLanSeal(
        MuseLanMessage(type: 'push', session: 'someone-else', at: now.millisecondsSinceEpoch, device: 'B', snapshot: MuseSnapshot.empty),
        key,
      );
      expect(() => museLanOpen(other, key, expectType: 'push', now: now), throwsA(isA<MuseLanException>()));
    });

    test('merge: a joining device that never synced yields on shared keys', () {
      final host = MuseSnapshot({'muse_accent': const MuseSyncEntry('purple', 100), 'sub:https://h/s': const MuseSyncEntry('H', 100)});
      final client = MuseLanMessage(
        type: 'push',
        session: 's',
        at: 0,
        device: 'phone',
        firstSync: true,
        snapshot: MuseSnapshot({'muse_accent': const MuseSyncEntry('blue', 9999), 'sub:https://p/s': const MuseSyncEntry('P', 9999)}),
      );
      final merged = museLanMerge(host, client);
      expect(merged.values, {'muse_accent': 'purple', 'sub:https://h/s': 'H', 'sub:https://p/s': 'P'});
      // not a first sync: the newer change wins
      final again = museLanMerge(host, MuseLanMessage(type: 'push', session: 's', at: 0, device: 'p', snapshot: client.snapshot));
      expect(again.values['muse_accent'], 'blue');
    });

    test('a real exchange over the LAN: both devices end with the merged state', () async {
      final ip = await MuseLanHost.lanAddress();
      if (ip == null) {
        markTestSkipped('no LAN address here');
        return;
      }
      final hostSync = _FakeSync({'muse_accent': 'purple', 'sub:https://h/s': 'Home'})
        ..last = MuseSnapshot({'muse_accent': const MuseSyncEntry('blue', 1)});
      final phoneSync = _FakeSync({'muse_hosts': '1.2.3.4 nas.lan', 'sub:https://p/s': 'Phone'});
      String? asked;
      final host = MuseLanHost(
        hostSync,
        confirm: (device) async {
          asked = device;
          return true;
        },
      );
      await host.start(address: ip);
      if (host.state == MuseLanHostState.failed && host.message.startsWith('无法开始监听')) {
        markTestSkipped('cannot listen here: ${host.message}');
        return;
      }
      expect(host.state, MuseLanHostState.waiting, reason: host.message);
      expect(host.listening, isTrue);
      final pairing = museParseLanPairing(host.pairing!.toUri())!;

      // a wrong key is refused and does not use up the pairing
      final wrong = MuseLanPairing(host: pairing.host, port: pairing.port, key: museNewLanKey(), expiresAt: pairing.expiresAt);
      await expectLater(museLanSyncWith(phoneSync, wrong), throwsA(isA<MuseLanException>()));
      expect(host.state, MuseLanHostState.waiting, reason: host.message);

      final result = await museLanSyncWith(phoneSync, pairing);
      expect(asked, isNotNull);
      expect(result.changed, greaterThan(0));
      expect(phoneSync.values, hostSync.values);
      expect(phoneSync.values, {
        'muse_accent': 'purple',
        'muse_hosts': '1.2.3.4 nas.lan',
        'sub:https://h/s': 'Home',
        'sub:https://p/s': 'Phone',
      });
      expect(host.state, MuseLanHostState.done);
      // one pairing = one sync: the listener is gone
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(host.listening, isFalse);
      await expectLater(museLanSyncWith(phoneSync, pairing), throwsA(isA<MuseLanException>()));
    });

    test('the host refuses when its user says no, and expires', () async {
      final ip = await MuseLanHost.lanAddress();
      if (ip == null) {
        markTestSkipped('no LAN address here');
        return;
      }
      final hostSync = _FakeSync({'muse_accent': 'purple'});
      final host = MuseLanHost(hostSync, confirm: (_) async => false);
      await host.start(address: ip);
      if (host.state == MuseLanHostState.failed && host.message.startsWith('无法开始监听')) {
        markTestSkipped('cannot listen here: ${host.message}');
        return;
      }
      final p = museParseLanPairing(host.pairing!.toUri())!;
      await expectLater(museLanSyncWith(_FakeSync({}), p), throwsA(isA<MuseLanException>()));
      expect(hostSync.applied, 0);

      final short = MuseLanHost(hostSync, confirm: (_) async => true);
      await short.start(address: ip, ttl: const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(short.state, MuseLanHostState.expired);
      expect(short.listening, isFalse);
    });
  });

  group('分流预设 1.4.1', () {
    test('the new services are there, all off by default, each in a section', () {
      final keys = museRulePresets.map((p) => p.key).toSet();
      for (final k in [
        'google', 'youtube', 'netflix', 'spotify', 'tiktok', 'twitter', 'meta', 'discord', 'dev', 'payments', 'crypto',
        'amazon', 'cnapps', 'bt', 'cncdn', 'streaming', 'ai', 'telegram', 'banks', 'privacy',
      ]) {
        expect(keys, contains(k));
      }
      expect(keys.length, museRulePresets.length, reason: 'keys are unique');
      expect(museParsePresetChoice(''), isEmpty);
      final grouped = musePresetsByGroup();
      expect(grouped.values.expand((e) => e).length, museRulePresets.length);
      expect(grouped.keys.first, MusePresetGroup.ai);
    });

    test('search finds by name, domain and section', () {
      expect(musePresetsByGroup(query: 'youtube').values.expand((e) => e).map((p) => p.key), contains('youtube'));
      expect(musePresetsByGroup(query: 'npmjs').values.expand((e) => e).map((p) => p.key), ['dev']);
      expect(musePresetsByGroup(query: '国内直连').keys, [MusePresetGroup.domestic]);
      expect(musePresetsByGroup(query: 'zzzz'), isEmpty);
    });

    test('every geosite a preset uses is bundled (nothing downloaded at connect)', () {
      expect(musePresetGeosites, isNotEmpty);
      for (final g in musePresetGeosites) {
        final f = File('assets/rule-sets/geosite-$g.srs');
        expect(f.existsSync(), isTrue, reason: f.path);
        expect(String.fromCharCodes(f.readAsBytesSync().take(3)), 'SRS', reason: f.path);
        expect(museBundledRuleSets, contains('geosite-$g'));
      }
      // the core finds the bundled copy from the URL's file name
      for (final p in museRulePresets) {
        for (final u in p.ruleSetUrls) {
          expect(u, startsWith('https://'));
          expect(u.split('/').last, matches(RegExp(r'^geosite-[\w@\-!]+\.srs$')));
        }
      }
    });

    test('a single service overrides the broad preset: it comes first', () {
      final rules = museApplyPresets([], {
        'streaming': Outbound.proxy,
        'youtube': Outbound.direct,
        'google': Outbound.proxy,
        'privacy': Outbound.block,
      });
      final names = rules.map((r) => r.name).toList();
      expect(names.indexOf('preset:youtube'), lessThan(names.indexOf('preset:streaming')));
      expect(names.indexOf('preset:youtube'), lessThan(names.indexOf('preset:google')));
      expect(names.first, 'preset:privacy');
      // YouTube direct even though 其他流媒体 (which lists youtube.com) is on
      expect(museTestRules(rules, 'https://www.youtube.com/watch').rule!.name, 'preset:youtube');
      expect(museTestRules(rules, 'https://www.youtube.com/watch').outbound, Outbound.direct);
      expect(museTestRules(rules, 'https://www.disneyplus.com').rule!.name, 'preset:streaming');
      // blocking wins over the proxied Google list
      expect(museTestRules(rules, 'doubleclick.net').outbound, Outbound.block);
    });

    test('apps and destinations are separate rules (one rule would need both to match)', () {
      final bt = museRulePreset('bt')!;
      final rules = musePresetRules(bt, Outbound.direct);
      expect(rules.map((r) => r.name), ['preset:bt', 'preset:bt:apps', 'preset:bt:android']);
      expect(rules[0].processNames, isEmpty);
      expect(rules[0].ruleSets, isNotEmpty);
      expect(rules[1].processNames, contains('qbittorrent.exe'));
      expect(rules[1].domainSuffixes, isEmpty);
      expect(rules[2].packageNames, isNotEmpty);
      final cn = musePresetRules(museRulePreset('cnapps')!, Outbound.direct);
      expect(cn.map((r) => r.name), ['preset:cnapps', 'preset:cnapps:android']);
      // 全局 drops the direct ones, keeps block / proxy
      final yt = musePresetRules(museRulePreset('youtube')!, Outbound.proxy).single;
      expect(yt.ruleSets.single, endsWith('geosite-youtube.srs'));
    });

    test('old choices keep working (streaming / games keys unchanged)', () {
      final c = museParsePresetChoice('{"streaming":"proxy","games":"direct","gone":"proxy"}');
      expect(c, {'streaming': Outbound.proxy, 'games': Outbound.direct});
    });
  });

  group('指定节点 / 远程规则集', () {
    test('typed sites and apps are sorted into their kind', () {
      final r = museNodeRuleFromText('🇭🇰 香港 01', 'netflix.com\nhttps://www.hulu.com/x, chrome.exe\ncom.android.chrome；*.disneyplus.com 垃圾!!');
      expect(r.domains, ['netflix.com', 'www.hulu.com', 'disneyplus.com']);
      expect(r.processes, ['chrome.exe']);
      expect(r.packages, ['com.android.chrome']);
      expect(museNodeRuleFromText('n', '   ').isEmpty, isTrue);
    });

    test('round trip, junk dropped, sent to the core as muse-node-rules', () {
      final raw = museNodeRulesToRaw([
        const MuseNodeRule(node: 'a', domains: ['x.com']),
        const MuseNodeRule(node: '', domains: ['y.com']),
        const MuseNodeRule(node: 'b'),
      ]);
      final back = museParseNodeRules(raw);
      expect(back.length, 1);
      expect(back.single.toJson(), {'domain_suffix': ['x.com'], 'outbound': 'a'});
      expect(museParseNodeRules('nope'), isEmpty);
      expect(museNodeRulesExtras([back.single.toJson()]), {'muse-node-rules': [back.single.toJson()]});
      expect(museNodeRulesExtras([]), isEmpty);
    });

    test('remote rule-sets become rules after the presets', () {
      final sets = museParseRemoteRuleSets(
        museRemoteRuleSetsToRaw([const MuseRemoteRuleSet('https://e.com/a.srs', Outbound.direct)]) .replaceFirst(']', ',{"url":"ftp://x"}]'),
      );
      expect(sets.length, 1);
      final rules = museApplyPresets([Rule(name: 'builtin:bypassLan')], {'ai': Outbound.proxy}, remote: sets);
      expect(rules.map((r) => r.name), ['preset:ai', 'remote:0', 'builtin:bypassLan']);
      expect(rules[1].ruleSets, ['https://e.com/a.srs']);
      expect(rules[1].outbound, Outbound.direct);
    });
  });

  group('更新', () {
    test('mirrors: the fastest working source first, failed ones kept last', () {
      const u = 'https://github.com/yywgov/muse-vpn/releases/download/v1.4.1/a.apk';
      final s = museDownloadSources(u, proxyPort: 1);
      expect(s.length, museDownloadMirrors.length + 2);
      final ranked = museRankSources(s, {
        u: null,
        'https://gh.llkk.cc/$u': 900000,
        'https://ghfast.top/$u': 300000,
        'https://hk.gh-proxy.com/$u': 0,
      });
      expect(ranked.first.url, 'https://gh.llkk.cc/$u');
      expect(ranked[1].url, 'https://ghfast.top/$u');
      expect(ranked.length, s.length);
      expect(ranked.last, (url: u, proxyPort: null));
    });

    test('release info can only point at this repository', () {
      Map<String, dynamic> rel(String url, {bool pre = false}) => {
        'tag_name': 'v1.5.0',
        'prerelease': pre,
        'html_url': 'https://github.com/yywgov/muse-vpn/releases/tag/v1.5.0',
        'assets': [
          {'name': 'Chuanyun-Android-arm64.apk', 'browser_download_url': url, 'size': 1},
        ],
      };
      expect(museParseRelease(rel('${museReleaseDownloadPrefix}v1.5.0/Chuanyun-Android-arm64.apk')), isNotNull);
      expect(museParseRelease(rel('https://evil.example/Chuanyun-Android-arm64.apk')), isNull);
      // 1.5.1: prereleases are never offered (Beta 通道 removed)
      final pre = rel('${museReleaseDownloadPrefix}v1.5.0/Chuanyun-Android-arm64.apk', pre: true);
      expect(museParseRelease(pre), isNull);
      expect(musePickRelease([pre, rel('x')])!['prerelease'], false);
    });

    test('Windows installs silently only with info straight from GitHub', () {
      const r = (version: '1.5.0', apkUrl: 'x.exe', apkSize: 1, pageUrl: 'p', sha256: 'ab');
      expect(museCanInstallSilently(r, viaMirror: false), isTrue);
      expect(museCanInstallSilently(r, viaMirror: true), isFalse);
      expect(museCanInstallSilently((version: '1', apkUrl: 'x.exe', apkSize: 1, pageUrl: 'p', sha256: null), viaMirror: false), isFalse);
    });
  });

  group('连接', () {
    test('wake: a late tick means the device slept', () {
      final d = MuseWakeDetector();
      final t0 = DateTime(2026, 10, 22, 20);
      expect(d.tick(t0), isNull);
      expect(d.tick(t0.add(const Duration(seconds: 15))), isNull);
      expect(d.tick(t0.add(const Duration(seconds: 50))), isNull);
      expect(d.tick(t0.add(const Duration(minutes: 30))), isNotNull);
    });

    test('wake: recheck, reconnect only when the network is back but the tunnel is not', () {
      expect(museWakeDecide(wantConnected: true, keepAlive: true, running: true), MuseWakeAction.recheck);
      expect(museWakeDecide(wantConnected: true, keepAlive: true, running: true, reachOk: false), MuseWakeAction.reconnect);
      expect(museWakeDecide(wantConnected: true, keepAlive: true, running: true, reachOk: false, directOk: false), MuseWakeAction.none);
      expect(museWakeDecide(wantConnected: true, keepAlive: true, running: true, reachOk: true), MuseWakeAction.none);
      expect(museWakeDecide(wantConnected: false, keepAlive: true, running: true), MuseWakeAction.none);
      expect(museWakeDecide(wantConnected: true, keepAlive: false, running: true), MuseWakeAction.none);
    });

    test('leftover system proxy: local port with nothing listening while disconnected', () {
      const ours = MuseProxySetting(enabled: true, server: '127.0.0.1:12334');
      expect(ours.loopbackPort, 12334);
      expect(museIsStaleProxy(ours, connected: false, listening: false), isTrue);
      expect(museIsStaleProxy(ours, connected: false, listening: true), isFalse);
      expect(museIsStaleProxy(ours, connected: true, listening: false), isFalse);
      expect(const MuseProxySetting(enabled: true, server: 'http=localhost:7890;https=localhost:7890').loopbackPort, 7890);
      expect(const MuseProxySetting(enabled: true, server: 'proxy.corp:8080').loopbackPort, isNull);
      expect(const MuseProxySetting(enabled: false, server: '127.0.0.1:1').loopbackPort, isNull);
    });

    test('clock skew from a Date header', () {
      final local = DateTime.utc(2026, 10, 22, 12, 5);
      expect(museClockSkew('Thu, 22 Oct 2026 12:00:00 GMT', local), const Duration(minutes: 5));
      expect(museClockSkew('garbage', local), isNull);
      expect(museClockSkew(null, local), isNull);
      expect(museDiagClock(const Duration(seconds: 20)).level, MuseDiagLevel.ok);
      expect(museDiagClock(const Duration(minutes: 5)).level, MuseDiagLevel.fail);
      expect(museDiagClock(const Duration(minutes: -5)).text, contains('慢'));
    });

    test('diagnosis wizard offers the fix for what failed', () {
      final offline = [museDiagNetwork(directOk: false), museDiagStaleProxy(stale: true, port: 7890)];
      expect(museDiagActions(offline, connected: false), [MuseDiagAction.repairProxy]);
      expect(museDiagActions([museDiagNetwork(directOk: true)], connected: false), [MuseDiagAction.connect]);
      final deadNode = [
        museDiagNetwork(directOk: true),
        museDiagNode(connected: true, delay: 65535),
        museDiagInternet(connected: true, ok: false),
      ];
      expect(museDiagActions(deadNode, connected: true), [MuseDiagAction.switchNode, MuseDiagAction.testNodes, MuseDiagAction.updateSubs]);
      final ok = [museDiagNetwork(directOk: true), museDiagNode(connected: true, delay: 80), museDiagInternet(connected: true, ok: true)];
      expect(museDiagActions(ok, connected: true), isEmpty);
      expect(museDiagActions([museDiagClock(const Duration(minutes: 10))], connected: false).first, MuseDiagAction.fixClock);
    });
  });

  group('Android 后台', () {
    test('killed vs stopped, rebooted, updated or already reported', () {
      bool k({int since = 5000, bool running = false, int boot = 1000, bool updated = false, int reported = 0}) =>
          museWasKilledInBackground(connectedSince: since, running: running, bootTime: boot, appUpdated: updated, lastReported: reported);
      expect(k(), isTrue);
      expect(k(since: 0), isFalse); // stopped normally
      expect(k(running: true), isFalse);
      expect(k(boot: 6000), isFalse); // rebooted since
      expect(k(updated: true), isFalse);
      expect(k(reported: 5000), isFalse);
    });

    test('brand guides', () {
      expect(museOemGuide('Xiaomi').brand, contains('小米'));
      expect(museOemGuide('HUAWEI').steps.first, contains('启动'));
      expect(museOemGuide('OnePlus').brand, contains('一加'));
      expect(museOemGuide('vivo').brand, contains('vivo'));
      expect(museOemGuide('samsung').brand, '三星');
      expect(museOemGuide('Google', brand: 'google').steps, isNotEmpty);
      expect(museOemGuide('unknown').brand, 'Android');
    });
  });

  group('订阅 / 控制', () {
    test('node names out of a stored config and the update diff', () {
      final before = jsonEncode({
        'outbounds': [
          {'type': 'selector', 'tag': 'select'},
          {'type': 'vless', 'tag': 'A'},
          {'type': 'trojan', 'tag': 'B'},
          {'type': 'direct', 'tag': 'direct'},
        ],
      });
      final after = jsonEncode({
        'outbounds': [
          {'type': 'vless', 'tag': 'A'},
          {'type': 'hysteria2', 'tag': 'C'},
        ],
      });
      expect(museConfigNodeNames(before), ['A', 'B']);
      expect(museConfigNodeNames('proxies: []'), isEmpty);
      expect(museSubDiff(museConfigNodeNames(before), museConfigNodeNames(after)).summary, '新增 1 · 移除 1 · 保留 1');
    });

    test('command line and control links', () {
      final a = museParseCliArgs(['--node', '🇭🇰 香港 01']);
      expect((a.connect, a.node), (true, '🇭🇰 香港 01'));
      expect(museParseCliArgs(['--disconnect']).disconnect, isTrue);
      expect(museParseCliArgs(['--whatever']).isEmpty, isTrue);
      expect(museParseDeepLink('chuanyun://connect?node=%E9%A6%99%E6%B8%AF')!.node, '香港');
      expect(museParseDeepLink('chuanyun://disconnect')!.disconnect, isTrue);
      expect(museParseDeepLink('chuanyun://import?url=https%3A%2F%2Fa%2Fs')!.url, 'https://a/s');
    });
  });
}
