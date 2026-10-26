// 穿云 1.6.0 (batch 2, nodes B): #30 节点二维码, #31 去重规则, #34 收藏排序, #35 复制三种格式,
// #36 中转入口/出口, #38 顶部固定当前节点卡, #40 清除不可用前预览且可撤销.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/bad_nodes.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/logic/node_share.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

OutboundInfo _n(String tag, String type, {String host = '', int port = 0}) =>
    OutboundInfo(tag: tag, tagDisplay: tag, type: type, host: host, port: port);

const _vlessReality = {
  'type': 'vless',
  'tag': '🇯🇵 东京 02',
  'server': 'jp.example.com',
  'server_port': 443,
  'uuid': '11111111-2222-3333-4444-555555555555',
  'flow': 'xtls-rprx-vision',
  'tls': {
    'enabled': true,
    'server_name': 'www.apple.com',
    'utls': {'enabled': true, 'fingerprint': 'chrome'},
    'reality': {'enabled': true, 'public_key': 'PBK', 'short_id': 'ab12'},
  },
};

final _config = jsonEncode({
  'outbounds': [
    _vlessReality,
    {
      'type': 'vmess',
      'tag': 'vm',
      'server': '1.2.3.4',
      'server_port': 8443,
      'uuid': 'u-1',
      'security': 'auto',
      'alter_id': 0,
      'tls': {'enabled': true, 'server_name': 'cdn.example.com'},
      'transport': {'type': 'ws', 'path': '/ray', 'headers': {'Host': 'cdn.example.com'}},
    },
    {
      'type': 'trojan',
      'tag': 'tj',
      'server': 'tj.example.com',
      'server_port': 443,
      'password': 'p@ss word',
      'tls': {'enabled': true, 'server_name': 'tj.example.com', 'insecure': true},
      'transport': {'type': 'grpc', 'service_name': 'svc'},
    },
    {
      'type': 'shadowsocks',
      'tag': 'ss',
      'server': 'ss.example.com',
      'server_port': 8388,
      'method': 'aes-256-gcm',
      'password': 'secret',
      'plugin': 'obfs-local',
      'plugin_opts': 'obfs=http;obfs-host=bing.com',
    },
    {
      'type': 'hysteria2',
      'tag': '🇭🇰 香港 01',
      'server': 'hk.example.com',
      'server_port': 443,
      'server_ports': ['20000:30000'],
      'password': 'hy',
      'obfs': {'type': 'salamander', 'password': 'ob'},
      'tls': {'enabled': true, 'server_name': 'hk.example.com', 'alpn': ['h3']},
    },
    {
      'type': 'tuic',
      'tag': 'tu',
      'server': 'tu.example.com',
      'server_port': 443,
      'uuid': 'u-2',
      'password': 'pw',
      'congestion_control': 'bbr',
      'tls': {'enabled': true, 'server_name': 'tu.example.com', 'alpn': ['h3']},
    },
    {'type': 'wireguard', 'tag': 'wg', 'server': 'wg.example.com', 'server_port': 51820},
    // the same server twice under other names, differing only in the password
    {'type': 'trojan', 'tag': 'dupA', 'server': 'd.example.com', 'server_port': 443, 'password': 'a'},
    {'type': 'trojan', 'tag': 'dupB', 'server': 'd.example.com', 'server_port': 443, 'password': 'a'},
    {'type': 'trojan', 'tag': 'dupC', 'server': 'd.example.com', 'server_port': 443, 'password': 'c'},
    {'type': 'vless', 'tag': 'dupD', 'server': 'd.example.com', 'server_port': 443, 'uuid': 'x'},
  ],
});

final _group = OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '🇯🇵 东京 02',
  selectable: true,
  items: [
    _n('🇯🇵 东京 02', 'vless', host: 'jp.example.com', port: 443),
    _n('🇭🇰 香港 01', 'hysteria2', host: 'hk.example.com', port: 443),
    _n('沪日 IPLC 01', 'vless', host: 'relay.example.com', port: 10001),
    _n('🇸🇬 新加坡 03', 'trojan', host: 'sg.example.com', port: 443),
    _n('🇺🇸 洛杉矶 01', 'vless', host: 'us.example.com', port: 443),
    _n('dupA', 'trojan', host: 'd.example.com', port: 443),
    _n('dupB', 'trojan', host: 'd.example.com', port: 443),
    _n('dupC', 'trojan', host: 'd.example.com', port: 443),
    _n('dupD', 'vless', host: 'd.example.com', port: 443),
  ],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  Size size = const Size(412, 900),
  double scale = 1,
  bool pin = false,
  Set<String> unavailable = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      museRunningProvider.overrideWithValue(true),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('机场'),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
      museActiveConfigProvider.overrideWith((ref) async => _config),
      museConnectedSinceProvider.overrideWith((ref) async => null),
      museHiddenNodesProvider.overrideWith((ref) => unavailable),
    ],
  );
  addTearDown(c.dispose);
  await tester.runAsync(() => c.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => c.read(museActiveConfigProvider.future));
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: MuseNodeList(pinCurrent: pin)),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return c;
}

String? _clipboard;

void _mockClipboard(WidgetTester tester) {
  _clipboard = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') _clipboard = (call.arguments as Map)['text'] as String?;
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

double _y(WidgetTester tester, String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;

void main() {
  group('logic', () {
    test('#30 / #35 share links', () {
      final vless = museNodeShareLink(_config, '🇯🇵 东京 02', name: '东京 02')!;
      final u = Uri.parse(vless);
      expect(u.scheme, 'vless');
      expect(u.userInfo, '11111111-2222-3333-4444-555555555555');
      expect(u.host, 'jp.example.com');
      expect(u.port, 443);
      expect(u.queryParameters['security'], 'reality');
      expect(u.queryParameters['pbk'], 'PBK');
      expect(u.queryParameters['sid'], 'ab12');
      expect(u.queryParameters['fp'], 'chrome');
      expect(u.queryParameters['flow'], 'xtls-rprx-vision');
      expect(u.queryParameters['type'], 'tcp');
      expect(Uri.decodeComponent(u.fragment), '东京 02');

      final vm = museNodeShareLink(_config, 'vm')!;
      final j = jsonDecode(utf8.decode(base64.decode(vm.substring('vmess://'.length)))) as Map;
      expect(j['add'], '1.2.3.4');
      expect(j['net'], 'ws');
      expect(j['path'], '/ray');
      expect(j['host'], 'cdn.example.com');
      expect(j['tls'], 'tls');
      expect(j['ps'], 'vm');

      final tj = Uri.parse(museNodeShareLink(_config, 'tj')!);
      expect(Uri.decodeComponent(tj.userInfo), 'p@ss word');
      expect(tj.queryParameters['type'], 'grpc');
      expect(tj.queryParameters['serviceName'], 'svc');
      expect(tj.queryParameters['allowInsecure'], '1');

      final ss = museNodeShareLink(_config, 'ss')!;
      expect(ss, startsWith('ss://'));
      final user = Uri.parse(ss).userInfo;
      expect(utf8.decode(base64Url.decode(base64Url.normalize(user))), 'aes-256-gcm:secret');
      expect(Uri.parse(ss).queryParameters['plugin'], 'obfs-local;obfs=http;obfs-host=bing.com');

      final hy = Uri.parse(museNodeShareLink(_config, '🇭🇰 香港 01')!);
      expect(hy.scheme, 'hysteria2');
      expect(hy.queryParameters['obfs'], 'salamander');
      expect(hy.queryParameters['mport'], '20000-30000');

      final tu = Uri.parse(museNodeShareLink(_config, 'tu')!);
      expect(tu.userInfo, 'u-2:pw');
      expect(tu.queryParameters['congestion_control'], 'bbr');

      expect(museNodeShareLink(_config, 'wg'), isNull, reason: 'no common link form');
      expect(museNodeShareLink(_config, 'gone'), isNull);
      expect(museNodeShareLink('not json', 'vm'), isNull);
    });

    test('#35 Clash and JSON 配置', () {
      final c = museNodeAsClash(_config, '🇯🇵 东京 02', name: '东京 02')!;
      expect(c, startsWith('- name: "东京 02"'));
      expect(c, contains('  type: "vless"'));
      expect(c, contains('  server: "jp.example.com"'));
      expect(c, contains('  port: 443'));
      expect(c, contains('  reality-opts: {public-key: "PBK", short-id: "ab12"}'));
      expect(c, contains('  client-fingerprint: "chrome"'));
      final vm = museNodeAsClash(_config, 'vm')!;
      expect(vm, contains('  network: "ws"'));
      expect(vm, contains('  ws-opts: {path: "/ray", headers: {Host: "cdn.example.com"}}'));
      final ss = museNodeAsClash(_config, 'ss')!;
      expect(ss, contains('  type: "ss"'));
      expect(ss, contains('  plugin: "obfs"'));
      expect(ss, contains('  plugin-opts: {mode: "http", host: "bing.com"}'));
      final hy = museNodeAsClash(_config, '🇭🇰 香港 01')!;
      expect(hy, contains('  ports: "20000-30000"'));
      expect(hy, contains('  alpn: ["h3"]'));
      expect(museNodeAsClash(_config, 'wg'), isNull);

      final js = museNodeAsJsonConfig(_config, 'tu')!;
      expect(jsonDecode(js), containsPair('congestion_control', 'bbr'));
      expect(museNodeCopyText(_config, 'wg', MuseNodeCopyFormat.json), isNotNull);
      expect(museNodeCopyText(_config, 'wg', MuseNodeCopyFormat.link), isNull);
      expect(MuseNodeCopyFormat.values.map((e) => e.label), ['链接', 'Clash', 'JSON 配置']);
    });

    test('#31 full-parameter duplicates ignore the name only', () {
      final p = museOutboundParamsByTag(_config);
      expect(p['dupA'], p['dupB']);
      expect(p['dupA'], isNot(p['dupC']));
      expect(museOutboundParamsByTag('bad'), isEmpty);
      expect(museDedupModes.keys, ['protocol', 'address', 'full']);
    });

    test('#36 relay entry / exit', () {
      expect(museRelayInfo('沪日 IPLC 01', nameRegion: 'JP'), const MuseRelayInfo(entry: '上海', exit: 'JP'));
      // the region character after the entry city when the name has no region of its own
      expect(museRelayInfo('沪日 IPLC 01'), const MuseRelayInfo(entry: '上海', exit: 'JP'));
      expect(museRelayInfo('莞美 02'), const MuseRelayInfo(entry: '东莞', exit: 'US'));
      expect(museRelayInfo('深港 01', nameRegion: 'HK'), const MuseRelayInfo(entry: '深圳', exit: 'HK'));
      expect(museRelayInfo('广州-日本 专线', nameRegion: 'JP')!.entry, '广州');
      expect(museRelayInfo('香港 IEPL 02', nameRegion: 'HK'), const MuseRelayInfo(entry: '', exit: 'HK'));
      // the landing IP wins over the name
      expect(museRelayInfo('沪日 01', nameRegion: 'JP', exitCode: 'us'), const MuseRelayInfo(entry: '上海', exit: 'US', exitFromLanding: true));
      // not relays
      expect(museRelayInfo('🇯🇵 东京 02', nameRegion: 'JP'), isNull);
      expect(museRelayInfo('南京 01', nameRegion: 'CN'), isNull);
      expect(museRelayInfo('上海 01', nameRegion: 'CN'), isNull);
      expect(museRelayInfo('🇭🇰 香港 01', nameRegion: 'HK'), isNull);
    });

    test('#34 favourites in the user order', () {
      final items = ['g', 'a', 'b', 'c', 'd'];
      List<String> order(List<String>? fav) =>
          museFavoritesFirst(items, isGroup: (e) => e == 'g', tag: (e) => e, favorites: {'b', 'c', 'd'}, favoriteOrder: fav);
      expect(order(null), ['g', 'b', 'c', 'd', 'a']);
      expect(order(['d', 'b', 'c']), ['g', 'd', 'b', 'c', 'a']);
      // a favourite missing from the saved order goes last
      expect(order(['c']), ['g', 'c', 'b', 'd', 'a']);
    });
  });

  group('node list', () {
    testWidgets('#31 dedup by address + port / by full parameters', (tester) async {
      final c = await _pump(tester, prefs: {'muse_hide_duplicates': true});
      // default: protocol + address + port → dupB, dupC hidden; dupD (other protocol) stays
      expect(find.byKey(const ValueKey('dupA')), findsOneWidget);
      expect(find.byKey(const ValueKey('dupB')), findsNothing);
      expect(find.byKey(const ValueKey('dupD')), findsOneWidget);
      await c.read(MusePrefs.dedupMode.notifier).update('address');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('dupD')), findsNothing);
      expect(find.byKey(const ValueKey('dupC')), findsNothing);
      await c.read(MusePrefs.dedupMode.notifier).update('full');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('dupA')), findsOneWidget);
      expect(find.byKey(const ValueKey('dupB')), findsNothing, reason: 'same settings, other name');
      expect(find.byKey(const ValueKey('dupC')), findsOneWidget, reason: 'another password');
      expect(find.byKey(const ValueKey('dupD')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('#34 favourites follow the order arranged in 收藏排序', (tester) async {
      final c = await _pump(tester, prefs: {'muse_favorite_nodes': '🇸🇬 新加坡 03\n🇺🇸 洛杉矶 01\n别的订阅', 'muse_node_sort': 'original'});
      // not arranged yet: the list's own order (美 after 新)
      expect(_y(tester, '🇸🇬 新加坡 03'), lessThan(_y(tester, '🇺🇸 洛杉矶 01')));
      await tester.tap(find.byKey(const ValueKey('node_sort_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('node_sort_favorites')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fav_order_dialog')), findsOneWidget);
      expect(find.byKey(const ValueKey('fav_order_别的订阅')), findsNothing, reason: 'only this subscription');
      // drag 洛杉矶 above 新加坡
      await tester.timedDrag(
        find.byKey(const ValueKey('fav_order_handle_🇺🇸 洛杉矶 01')),
        const Offset(0, -120),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fav_order_save')));
      await tester.pumpAndSettle();
      expect(c.read(Preferences.museFavoriteNodes), '🇺🇸 洛杉矶 01\n🇸🇬 新加坡 03\n别的订阅');
      expect(c.read(MusePrefs.favoriteManualOrder), isTrue);
      expect(_y(tester, '🇺🇸 洛杉矶 01'), lessThan(_y(tester, '🇸🇬 新加坡 03')));
      // 按列表顺序 goes back
      await tester.tap(find.byKey(const ValueKey('node_sort_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('node_sort_favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fav_order_auto')));
      await tester.pumpAndSettle();
      expect(c.read(MusePrefs.favoriteManualOrder), isFalse);
      expect(_y(tester, '🇸🇬 新加坡 03'), lessThan(_y(tester, '🇺🇸 洛杉矶 01')));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('#30 QR and #35 copy formats from the node detail', (tester) async {
      _mockClipboard(tester);
      await _pump(tester, size: const Size(412, 1400));
      await tester.longPress(find.byKey(const ValueKey('🇯🇵 东京 02')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('node_qr')));
      await tester.tap(find.byKey(const ValueKey('node_qr')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('muse_qr')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qr_copy')));
      await tester.pumpAndSettle();
      expect(_clipboard, startsWith('vless://11111111-2222-3333-4444-555555555555@jp.example.com:443?'));

      for (final (f, check) in [
        (MuseNodeCopyFormat.clash, (String t) => t.startsWith('- name: ')),
        (MuseNodeCopyFormat.json, (String t) => jsonDecode(t) is Map),
        (MuseNodeCopyFormat.link, (String t) => t.startsWith('vless://')),
      ]) {
        await tester.longPress(find.byKey(const ValueKey('🇯🇵 东京 02')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('node_copy_as')));
        await tester.tap(find.byKey(const ValueKey('node_copy_as')));
        await tester.pumpAndSettle();
        expect(find.text('JSON 配置'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('node_copy_${f.name}')));
        await tester.pumpAndSettle();
        expect(check(_clipboard!), isTrue, reason: f.label);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('#36 the detail shows a relay node\'s entry and exit', (tester) async {
      await _pump(tester, size: const Size(412, 1400));
      await tester.longPress(find.byKey(const ValueKey('沪日 IPLC 01')));
      await tester.pumpAndSettle();
      expect(find.text('入口'), findsOneWidget);
      expect(find.text('上海（中转）'), findsOneWidget);
      expect(find.text('出口'), findsOneWidget);
      expect(find.textContaining('日本'), findsWidgets);
      // a node missing from the saved config has no link, so no QR
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('node_qr'))).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('#38 the node in use stays pinned while the list scrolls (${scale}x)', (tester) async {
        await _pump(tester, pin: true, size: scale == 1 ? const Size(412, 600) : const Size(320, 600), scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('node_current_card')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('node_current_card')), matching: find.text('东京 02')), findsOneWidget);
        final top = tester.getTopLeft(find.byKey(const ValueKey('node_current_card'))).dy;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(tester.getTopLeft(find.byKey(const ValueKey('node_current_card'))).dy, top);
        await tester.tap(find.byKey(const ValueKey('node_current_card')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('node_detail_sheet')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('#38 no pinned card in the 首页 picker / side column', (tester) async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('node_current_card')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('#40 清除不可用 previews, keeps favourites and the node in use, hides the rest', (tester) async {
      final c = await _pump(
        tester,
        size: const Size(412, 1400),
        prefs: {'muse_favorite_nodes': '🇸🇬 新加坡 03'},
        unavailable: {'🇭🇰 香港 01', '🇸🇬 新加坡 03', '🇺🇸 洛杉矶 01'},
      );
      expect(find.textContaining('不可用 · 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clear_unavailable')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('clear_unavailable_dialog')), findsOneWidget);
      expect(find.text('清除 2 个不可用节点'), findsOneWidget);
      final preview = find.byKey(const ValueKey('clear_unavailable_preview'));
      expect(find.descendant(of: preview, matching: find.text('🇭🇰 香港 01')), findsOneWidget);
      expect(find.descendant(of: preview, matching: find.text('🇸🇬 新加坡 03')), findsNothing);
      expect(find.textContaining('保留'), findsOneWidget);
      // cancel changes nothing
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(MuseNodeMetas.parse(c.read(MusePrefs.nodeMeta)).hiddenTags, isEmpty);
      await tester.tap(find.byKey(const ValueKey('clear_unavailable')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear_unavailable_confirm')));
      await tester.pumpAndSettle();
      expect(MuseNodeMetas.parse(c.read(MusePrefs.nodeMeta)).hiddenTags, {'🇭🇰 香港 01', '🇺🇸 洛杉矶 01'});
      expect(find.textContaining('已隐藏 · 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('#40 撤销 shows the cleared nodes again (other hidden nodes stay hidden)', (tester) async {
      final before = MuseNodeMetas.empty.set('dupA', const MuseNodeMeta(hidden: true, note: 'x'));
      final c = await _pump(tester, prefs: {'muse_node_meta': before.toRaw()});
      Future<void> Function()? undo;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Consumer(
              builder: (context, r, _) {
                return TextButton(
                  onPressed: () async => undo = await museClearUnavailable(
                    context,
                    r,
                    tags: const ['a', 'b', 'c'],
                    names: const {'a': 'A', 'b': 'B', 'c': 'C'},
                    unavailable: const {'a', 'b', 'c'},
                    selected: 'a',
                    favorites: const {},
                  ),
                  child: const Text('go'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear_unavailable_confirm')));
      await tester.pumpAndSettle();
      expect(MuseNodeMetas.parse(c.read(MusePrefs.nodeMeta)).hiddenTags, {'dupA', 'b', 'c'});
      expect(undo, isNotNull);
      await tester.runAsync(() => undo!());
      final after = MuseNodeMetas.parse(c.read(MusePrefs.nodeMeta));
      expect(after.hiddenTags, {'dupA'});
      expect(after.of('dupA').note, 'x');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
