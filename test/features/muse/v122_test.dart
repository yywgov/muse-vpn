// 穿云 1.2.2: keeper vs. a system proxy the user changed, guard status parsing, update digests,
// 自动收起不可用节点 (1.10.0: no 「不可用」 group; timed-out nodes sort to the end instead).
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/desktop/connection_keeper.dart';
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';

void main() {
  group('guard status', () {
    test('ours', () {
      expect(museParseGuardStatus('ours=1 flags=0x3 server=127.0.0.1:12334 bypass= pac= backup=1 restored=0'),
          MuseSystemProxy.ours);
    });
    test('restored by the guard', () {
      expect(
        museParseGuardStatus('ours=0 flags=0x3 server=original.example:8080 bypass= pac= backup=0 restored=1'),
        MuseSystemProxy.restoredByGuard,
      );
    });
    test('blanked / direct', () {
      expect(museParseGuardStatus('ours=0 flags=0x1 server= bypass= pac= backup=1 restored=0'), MuseSystemProxy.direct);
    });
    test('another proxy or PAC the user set', () {
      expect(museParseGuardStatus('ours=0 flags=0x3 server=other:1080 bypass= pac= backup=0 restored=0'),
          MuseSystemProxy.other);
      expect(museParseGuardStatus('ours=0 flags=0x5 server= bypass= pac=http://x/p.pac backup=0 restored=0'),
          MuseSystemProxy.other);
    });
    test('an older guard without restored= still parses', () {
      expect(museParseGuardStatus('ours=0 flags=0x1 server= bypass= pac= backup=0'), MuseSystemProxy.direct);
    });
    test('unreadable output decides nothing', () {
      expect(museParseGuardStatus(''), MuseSystemProxy.unknown);
      expect(museParseGuardStatus('usage: ChuanyunGuard ...'), MuseSystemProxy.unknown);
      expect(museParseGuardStatus('ours=0 server=x'), MuseSystemProxy.unknown);
    });
  });

  test('keeper reclaims the system proxy only after a guard restore or a blank', () {
    expect(museShouldReclaimSystemProxy(MuseSystemProxy.restoredByGuard), isTrue);
    expect(museShouldReclaimSystemProxy(MuseSystemProxy.direct), isTrue);
    expect(museShouldReclaimSystemProxy(MuseSystemProxy.other), isFalse);
    expect(museShouldReclaimSystemProxy(MuseSystemProxy.unknown), isFalse);
    expect(museShouldReclaimSystemProxy(MuseSystemProxy.ours), isFalse);
  });

  group('update digest', () {
    const hex = 'ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12';
    test('read from the asset', () {
      expect(museAssetSha256({'digest': 'sha256:$hex'}), hex);
      expect(museAssetSha256({'digest': 'SHA256:${hex.toUpperCase()}'}), hex);
      expect(museAssetSha256({}), isNull);
      expect(museAssetSha256({'digest': 'md5:abc'}), isNull);
    });
    test('carried on the release', () {
      final r = museParseRelease({
        'tag_name': 'v1.2.2',
        'prerelease': false,
        'assets': [
          {
            'name': 'Chuanyun-Windows-x64-Setup.exe',
            'browser_download_url': 'https://github.com/yywgov/muse-vpn/releases/download/v1/setup.exe',
            'size': 9,
            'digest': 'sha256:$hex',
          },
        ],
      }, windows: true);
      expect(r?.sha256, hex);
    });
  });

  test('route modes: 规则 / 全局, a saved 直连 starts as 规则', () {
    expect(MuseRouteMode.values.map((e) => e.title).toList(), ['规则', '全局']);
    expect(MuseRouteMode.fromKey('direct'), MuseRouteMode.rule);
    expect(MuseRouteMode.fromKey('global'), MuseRouteMode.global);
  });

  group('1.10.0: 超时节点排到末尾（替代「不可用」分组）', () {
    const timeout = 65000;
    List<MuseNodeSample> round(Map<String, int> delays, {Set<String> groups = const {}}) => [
      for (final e in delays.entries) MuseNodeSample(tag: e.key, delay: e.value, testedAt: 1, isGroup: groups.contains(e.key)),
    ];
    List<String> order(List<MuseNodeSample> items) => museTimeoutsLast<MuseNodeSample>(
      items,
      isGroup: (e) => e.isGroup,
      delay: (e) => e.delay,
      isValidDelay: MuseFailoverTracker.isValid,
    ).map((e) => e.tag).toList();

    test('a timed-out node moves to the end, nothing is hidden', () {
      expect(order(round({'a': timeout, 'b': 100, 'c': 200})), ['b', 'c', 'a']);
    });

    test('back in place on its first good test', () {
      expect(order(round({'a': 90, 'b': 100, 'c': 200})), ['a', 'b', 'c']);
    });

    test('untested nodes (delay 0) keep their place', () {
      expect(order(round({'a': 0, 'b': timeout, 'c': 200})), ['a', 'c', 'b']);
    });

    test('groups never move, even when their test timed out', () {
      expect(order(round({'auto': timeout, 'a': timeout, 'b': 100}, groups: {'auto'})), ['auto', 'b', 'a']);
    });

    test('every node timed out: all kept, order unchanged', () {
      expect(order(round({'a': timeout, 'b': timeout})), ['a', 'b']);
    });

    test('relative order among timed-out nodes is kept', () {
      expect(order(round({'x': timeout, 'a': 100, 'y': timeout, 'b': 50})), ['a', 'b', 'x', 'y']);
    });
  });
}
