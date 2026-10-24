// 穿云 1.5.3: switching the subscription shows its own nodes (disconnected and connected, the
// old core's groups are never shown or saved under the new one); 节点 rows show the protocol as
// a small tag, neutral icon for unknown regions, 自动最快 / 首页 use the tidied name; 出口 IP is
// cached per node / subscription / network and only asked again when something changed.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/home/core_profile.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/node_cache.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

MuseNodeCache _cache(String p, List<String> tags) => MuseNodeCache(
  profileId: p,
  groupTag: 'select',
  selected: tags.first,
  nodes: [for (final t in tags) MuseCachedNode(tag: t, name: t, type: 'vless')],
);

OutboundGroup _live(List<String> tags) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: tags.first,
  selectable: true,
  items: [for (final t in tags) OutboundInfo(tag: t, tagDisplay: t, type: 'vless')],
);

final _running = StateProvider<bool>((ref) => true);
final _active = StateProvider<String?>((ref) => 'B');
final _liveGroup = StateProvider<OutboundGroup?>((ref) => null);

class _Proxies extends ProxiesOverviewNotifier {
  @override
  Stream<OutboundGroup?> build() {
    final g = ref.watch(_liveGroup);
    return Stream.value(g);
  }
}

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      museRunningProvider.overrideWith((ref) => ref.watch(_running)),
      serviceRunningProvider.overrideWith((ref) => ref.watch(_running)),
      museActiveProfileIdProvider.overrideWith((ref) => ref.watch(_active)),
      proxiesOverviewNotifierProvider.overrideWith(_Proxies.new),
    ],
  );
  await c.read(sharedPreferencesProvider.future);
  return c;
}

List<String> _tags(ProviderContainer c) => [for (final e in c.read(museNodeGroupProvider).valueOrNull?.items ?? <OutboundInfo>[]) e.tag];

void main() {
  group('node list follows the active subscription', () {
    test('per-subscription cache, reads the old single-list format', () {
      final legacy = _cache('A', ['a1', 'a2']).toRaw();
      final caches = MuseNodeCaches.parse(legacy);
      expect(caches.of('A').nodes.map((e) => e.tag), ['a1', 'a2']);
      final both = caches.put(_cache('B', ['b1']));
      final back = MuseNodeCaches.parse(both.toRaw());
      expect(back.of('A').nodes.length, 2);
      expect(back.of('B').nodes.single.tag, 'b1');
      expect(back.of('C').isEmpty, isTrue);
      expect(MuseNodeCaches.parse('{bad').items, isEmpty);
      var many = const MuseNodeCaches([]);
      for (var i = 0; i < 12; i++) {
        many = many.put(_cache('p$i', ['n']));
      }
      expect(many.items.length, MuseNodeCaches.max);
      expect(many.of('p11').isEmpty, isFalse);
    });

    test('source: the old core is never trusted for a new subscription', () {
      expect(museNodeSource(running: false, activeProfileId: 'B', coreProfileId: 'A'), MuseNodeSource.cache);
      expect(museNodeSource(running: true, activeProfileId: 'B', coreProfileId: 'A'), MuseNodeSource.switching);
      expect(museNodeSource(running: true, activeProfileId: 'B', coreProfileId: 'B'), MuseNodeSource.live);
      expect(museNodeSource(running: true, activeProfileId: 'B', coreProfileId: null), MuseNodeSource.live);
    });

    test('disconnected: switching A → B shows B\'s own list', () async {
      final raw = MuseNodeCaches(const []).put(_cache('A', ['a1', 'a2'])).put(_cache('B', ['b1'])).toRaw();
      final c = await _container({'muse_node_cache': raw});
      addTearDown(c.dispose);
      c.read(_running.notifier).state = false;
      c.read(_active.notifier).state = 'A';
      expect(_tags(c), ['a1', 'a2']);
      c.read(_active.notifier).state = 'B';
      expect(_tags(c), ['b1']);
      c.read(_active.notifier).state = 'C'; // never connected: empty, not A's
      expect(_tags(c), isEmpty);
    });

    test('connected: while the core still runs A, B shows its cache, then the reloaded core', () async {
      final raw = MuseNodeCaches(const []).put(_cache('B', ['b1', 'b2'])).toRaw();
      final c = await _container({'muse_node_cache': raw});
      addTearDown(c.dispose);
      final sub = c.listen(museNodeGroupProvider, (_, _) {});
      final writer = c.listen(museNodeCacheWriterProvider, (_, _) {});
      addTearDown(sub.close);
      addTearDown(writer.close);
      c.read(museCoreProfileIdProvider.notifier).state = 'A';
      c.read(_liveGroup.notifier).state = _live(['a1', 'a2', 'a3']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_tags(c), ['b1', 'b2']); // not A's live groups
      // the old core's groups were not saved as B's list
      expect(MuseNodeCaches.parse(c.read(Preferences.museNodeCache)).of('B').nodes.map((e) => e.tag), ['b1', 'b2']);
      // reload finished with B
      c.read(museCoreProfileIdProvider.notifier).state = 'B';
      c.read(_liveGroup.notifier).state = _live(['b1', 'b2', 'b3']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_tags(c), ['b1', 'b2', 'b3']);
      expect(MuseNodeCaches.parse(c.read(Preferences.museNodeCache)).of('B').nodes.length, 3);
    });

    test('connected without a saved list: loading, not the old nodes', () async {
      final c = await _container({});
      addTearDown(c.dispose);
      c.read(museCoreProfileIdProvider.notifier).state = 'A';
      c.read(_liveGroup.notifier).state = _live(['a1']);
      expect(c.read(museNodeGroupProvider).isLoading, isTrue);
    });

    test('a reload with the new subscription refreshes the group stream', () {
      final src = File('lib/features/connection/notifier/connection_notifier.dart').readAsStringSync();
      expect(src, contains('museCoreProfileIdProvider.notifier).state = profile.id'));
      expect(src, contains('ref.invalidate(proxiesOverviewNotifierProvider)'));
    });
  });

  group('节点 names and rows', () {
    test('a group pick reads like its row', () {
      const metas = MuseNodeMetas({});
      final items = [('sg30', '🇸🇬新加坡|CF官方优选30')];
      expect(metas.pickName('🇸🇬新加坡|CF官方优选30', items, beautify: true), museBeautifyNodeName('🇸🇬新加坡|CF官方优选30'));
      expect(metas.pickName('🇸🇬新加坡|CF官方优选30', items), '🇸🇬新加坡|CF官方优选30');
      final s = museGroupSubtitle(
        type: 'URLTest',
        name: 'auto',
        selectedDisplay: '🇸🇬新加坡|CF官方优选30',
        shown: (r) => museStripFlags(metas.pickName(r, items, beautify: true)),
      );
      expect(s, '新加坡 · CF官方优选30');
    });
    test('short protocol tags', () {
      expect(museProtocolShort('vless'), 'VLESS');
      expect(museProtocolShort('hysteria2'), 'HY2');
      expect(museProtocolShort('shadowsocks'), 'SS');
    });

    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('row: protocol tag, quiet subtitle, neutral icon (dark=$dark, ${scale}x)', (tester) async {
          final size = scale == 1.0 ? const Size(412, 640) : const Size(320, 640);
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          Widget r(OutboundInfo p, {String note = ''}) => MuseNodeRow(
            proxy: p,
            since: null,
            nodeCount: 57,
            selected: false,
            onTap: () {},
            note: note,
            shownPick: (raw) => museBeautifyNodeName(raw),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
              home: MediaQuery(
                data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Column(
                    children: [
                      r(OutboundInfo(tag: 'jp', tagDisplay: '🇯🇵 日本 东京 IPLC 专线 超长名字 01', type: 'vless')),
                      r(OutboundInfo(tag: 'x', tagDisplay: 'Some node', type: 'hysteria2'), note: '家里'),
                      r(
                        OutboundInfo(
                          tag: 'auto',
                          tagDisplay: 'auto',
                          type: 'URLTest',
                          isGroup: true,
                          groupSelectedTagDisplay: '🇸🇬新加坡|CF官方优选30',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          // the tag (or, when the row is too narrow for it, the short name on line 2) — once
          expect(find.textContaining('VLESS'), findsOneWidget);
          expect(find.textContaining('HY2'), findsOneWidget);
          expect(find.text('Hysteria2'), findsNothing);
          expect(find.textContaining('家里'), findsOneWidget);
          expect(find.byKey(const ValueKey('node_protocol_tag')), scale == 1.0 ? findsNWidgets(2) : findsNothing);
          expect(find.byKey(const ValueKey('flag_box_neutral')), findsOneWidget);
          expect(find.text('新加坡 · CF官方优选30'), findsOneWidget);
          expect(find.textContaining('|'), findsNothing);
        });
      }
    }
  });

  group('出口 IP cache', () {
    late String store;
    late String node;
    late String net;
    late DateTime now;
    late int fetches;
    late Completer<void>? gate;
    MuseExitNotifier make() => MuseExitNotifier(
      () => 0,
      keyBase: () => museExitKey(profileId: 'p', node: node, routeMode: 'rule', network: ''),
      network: () async => net,
      loadCache: () => store,
      saveCache: (r) => store = r,
      now: () => now,
      fetch: (start, set) async {
        fetches++;
        if (gate != null) await gate!.future;
        return start.copyWith(
          info: MuseExitInfo(ip: '1.2.3.$fetches', country: 'JP'),
          infoFailed: false,
          google: MuseServiceState.ok,
          chatGpt: MuseServiceState.ok,
          netflix: MuseServiceState.partial,
        );
      },
    );
    setUp(() {
      store = '';
      node = 'n1';
      net = '192.168.1.5';
      now = DateTime(2026, 10, 25, 12);
      fetches = 0;
      gate = null;
    });

    test('asked once, then shown from the cache (also after a restart)', () async {
      final n = make();
      await n.ensure();
      expect(fetches, 1);
      expect(n.state?.info?.ip, '1.2.3.1');
      await n.ensure();
      expect(fetches, 1);
      n.dispose();
      final again = make(); // app reopened: persisted
      await again.showCached();
      expect(again.state?.info?.ip, '1.2.3.1');
      expect(again.state?.netflix, MuseServiceState.partial);
      await again.ensure();
      expect(fetches, 1);
    });

    test('node / network change or age asks again; switching back is instant', () async {
      final n = make();
      await n.ensure();
      node = 'n2';
      await n.ensure();
      expect(fetches, 2);
      node = 'n1';
      await n.ensure();
      expect(fetches, 2);
      expect(n.state?.info?.ip, '1.2.3.1');
      net = '10.0.0.8'; // Wi-Fi → mobile
      await n.ensure();
      expect(fetches, 3);
      now = now.add(const Duration(minutes: 11));
      await n.ensure();
      expect(fetches, 4);
      await n.check(); // 刷新
      expect(fetches, 5);
    });

    test('while asking again the old value stays, with refreshing set', () async {
      final n = make();
      await n.ensure();
      gate = Completer<void>();
      final f = n.check();
      await Future<void>.delayed(Duration.zero);
      expect(n.state?.info?.ip, '1.2.3.1');
      expect(n.state?.refreshing, isTrue);
      gate!.complete();
      await f;
      expect(n.state?.refreshing, isFalse);
      expect(n.state?.info?.ip, '1.2.3.2');
    });

    test('cache format is tolerant', () {
      expect(MuseExitCache.parse('').items, isEmpty);
      expect(MuseExitCache.parse('{x').items, isEmpty);
      expect(MuseExitCache.parse('[{"k":1},{"k":"a","ip":"1.1.1.1","t":5}]').items.single.ip, '1.1.1.1');
      expect(
        museNetworkFingerprint([('wlan0', '192.168.1.5'), ('tun0', '172.19.0.1'), ('lo', '127.0.0.1')]),
        '192.168.1.5',
      );
    });
  });
}
