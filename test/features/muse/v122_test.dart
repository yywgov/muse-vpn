// 穿云 1.2.2: keeper vs. a system proxy the user changed, guard status parsing, update digests,
// 自动收起不可用节点.
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/desktop/connection_keeper.dart';
import 'package:hiddify/features/muse/logic/bad_nodes.dart';
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
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
            'browser_download_url': 'https://x/setup.exe',
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

  group('自动收起不可用节点', () {
    const timeout = 65000;
    var clock = 0;
    List<MuseNodeSample> round(Map<String, int> delays, {Set<String> groups = const {}}) {
      clock += 1000;
      return [
        for (final e in delays.entries)
          MuseNodeSample(tag: e.key, delay: e.value, testedAt: clock, isGroup: groups.contains(e.key)),
      ];
    }

    test('hidden after 3 failed tests in a row, back after 2 good ones', () {
      final t = MuseBadNodeTracker(hideAfter: 3, restoreAfter: 2);
      for (var i = 0; i < 2; i++) {
        t.update(selected: 'a', items: round({'a': 100, 'b': timeout}));
      }
      expect(t.hidden, isEmpty);
      expect(t.update(selected: 'a', items: round({'a': 100, 'b': timeout})), isTrue);
      expect(t.hidden, {'b'});
      t.update(selected: 'a', items: round({'a': 100, 'b': 200}));
      expect(t.hidden, {'b'});
      expect(t.update(selected: 'a', items: round({'a': 100, 'b': 200})), isTrue);
      expect(t.hidden, isEmpty);
    });

    test('a good result in between resets the count', () {
      final t = MuseBadNodeTracker(hideAfter: 3, restoreAfter: 2);
      t.update(selected: 'a', items: round({'a': 100, 'b': timeout}));
      t.update(selected: 'a', items: round({'a': 100, 'b': timeout}));
      t.update(selected: 'a', items: round({'a': 100, 'b': 300}));
      t.update(selected: 'a', items: round({'a': 100, 'b': timeout}));
      expect(t.hidden, isEmpty);
    });

    test('the same result seen again does not count twice', () {
      final t = MuseBadNodeTracker(hideAfter: 3, restoreAfter: 2);
      final same = round({'a': 100, 'b': timeout});
      for (var i = 0; i < 5; i++) {
        t.update(selected: 'a', items: same);
      }
      expect(t.hidden, isEmpty);
    });

    test('untested nodes are not counted', () {
      final t = MuseBadNodeTracker(hideAfter: 3, restoreAfter: 2);
      for (var i = 0; i < 4; i++) {
        t.update(selected: 'a', items: round({'a': 100, 'b': 0}));
      }
      expect(t.hidden, isEmpty);
    });

    test('groups and the selected node are never hidden', () {
      final t = MuseBadNodeTracker(hideAfter: 3, restoreAfter: 2);
      for (var i = 0; i < 3; i++) {
        t.update(selected: 'b', items: round({'auto': timeout, 'a': 100, 'b': timeout}, groups: {'auto'}));
      }
      expect(t.hidden, isEmpty);
      // once the user picks another node the dead one folds away on the next result
      t.update(selected: 'a', items: round({'auto': timeout, 'a': 100, 'b': timeout}, groups: {'auto'}));
      expect(t.hidden, {'b'});
    });

    test('never hides every node', () {
      final t = MuseBadNodeTracker(hideAfter: 3, restoreAfter: 2);
      for (var i = 0; i < 4; i++) {
        t.update(selected: 'auto', items: round({'auto': 0, 'a': timeout, 'b': timeout}, groups: {'auto'}));
      }
      expect(t.hidden, isEmpty);
    });

    test('nodes that left the profile are forgotten', () {
      final t = MuseBadNodeTracker(hideAfter: 3, restoreAfter: 2);
      for (var i = 0; i < 3; i++) {
        t.update(selected: 'a', items: round({'a': 100, 'b': timeout}));
      }
      expect(t.hidden, {'b'});
      t.update(selected: 'a', items: round({'a': 100}));
      expect(t.hidden, isEmpty);
    });
  });
}
