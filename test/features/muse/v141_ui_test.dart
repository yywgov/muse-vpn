// 穿云 1.4.1: the new / changed screens render without overflow (phone light / dark, Windows ~900
// and 1280): 分流 预设 (sections + search), 指定节点, 远程规则集, 同步 (局域网 first, WebDAV under
// 更多), the pairing sheet, 网络 (定时 / 质量提醒), 节点 多选, the 流量 tile at large text.
// MUSE_SHOTS=<dir> writes PNG screenshots for review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/data/lan_sync_service.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/nodes/muse_nodes_page.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/hiddifycore/generated/google/protobuf/timestamp.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _shotsDir = Platform.environment['MUSE_SHOTS'];
const _font = 'MuseShotSans';

class _Exit extends MuseExitNotifier {
  _Exit(MuseExitResult? r) : super(() => 0) {
    state = r;
  }
}

class _Reach extends MuseReachNotifier {
  _Reach() : super(() => 0) {
    state = MuseReach.ok;
  }
}

class _History extends MuseSpeedHistory {
  @override
  List<int> build() => [for (var i = 0; i < 30; i++) (1.2e6 + 9e5 * ((i * 7) % 5) / 4 + (i.isEven ? 3e5 : 0)).round()];
}

OutboundInfo _node(String tag, String type, int delay, {bool group = false, String pick = ''}) => OutboundInfo(
  tag: tag,
  tagDisplay: tag,
  type: type,
  isGroup: group,
  urlTestDelay: delay,
  urlTestTime: Timestamp.fromDateTime(DateTime.now()),
  groupSelectedTagDisplay: pick,
);

final _group = OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '🇯🇵 东京 02',
  selectable: true,
  items: [
    _node('lowest', 'URLTest', 86, group: true, pick: '🇯🇵 东京 02'),
    _node('🇯🇵 东京 02', 'vless', 86),
    _node('🇭🇰 香港 01', 'hysteria2', 42),
    _node('🇸🇬 新加坡 03', 'trojan', 120),
    _node('🇺🇸 洛杉矶 01', 'vless', 386),
    _node('🇹🇼 台北 01', 'vmess', 652),
    _node('🇰🇷 首尔 01', 'anytls', 154),
    _node('🇩🇪 法兰克福 01', 'shadowsocks', 238),
    _node('🇬🇧 伦敦 01', 'trojan', 65535),
  ],
);

Future<void> _loadFonts() async {
  if (_shotsDir == null) return;
  Future<void> load(String family, String path) async {
    final bytes = File(path).readAsBytesSync();
    await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }

  // static weights cut from the variable Noto Sans SC (MUSE_SHOT_FONTS), else the variable font
  final fontDir = Platform.environment['MUSE_SHOT_FONTS'];
  if (fontDir != null && Directory(fontDir).existsSync()) {
    final loader = FontLoader(_font);
    for (final f in Directory(fontDir).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  } else {
    await load(_font, '/workspace/work/mock/NotoSansSC.ttf');
  }
  await load('Emoji', 'assets/fonts/Emoji.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/workspace/tools/flutter';
  await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget page,
  required Brightness brightness,
  required Size size,
  bool desktop = false,
  int tab = 0,
  bool connected = true,
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final since = DateTime.now().subtract(const Duration(minutes: 12, seconds: 34));
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => prefs),
      museConnectionProvider.overrideWithValue(AsyncData(connected ? const Connected() : const Disconnected())),
      museRunningProvider.overrideWithValue(connected),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('机场订阅'),
      museAppVersionProvider.overrideWithValue(null),
      museSubInfoProvider.overrideWithValue(
        SubscriptionInfo(
          upload: 3 * 1024 * 1024 * 1024,
          download: 30 * 1024 * 1024 * 1024 + 800 * 1024 * 1024,
          total: 120 * 1024 * 1024 * 1024,
          expire: DateTime.now().add(const Duration(days: 29, hours: 2)),
        ),
      ),
      museStatsProvider.overrideWithValue(
        SystemInfo(
          uplink: Int64(180 * 1024),
          downlink: Int64((2.4 * 1024 * 1024).round()),
          uplinkTotal: Int64(96 * 1024 * 1024),
          downlinkTotal: Int64((1.18 * 1024 * 1024 * 1024).round()),
        ),
      ),
      museSpeedHistoryProvider.overrideWith(_History.new),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
      museConnectedSinceProvider.overrideWith((ref) async => connected ? since : null),
      museExitProvider.overrideWith(
        (ref) => _Exit(
          const MuseExitResult(
            info: MuseExitInfo(ip: '45.76.112.9', country: 'JP'),
            google: MuseServiceState.ok,
            chatGpt: MuseServiceState.ok,
            netflix: MuseServiceState.partial,
          ),
        ),
      ),
      museReachProvider.overrideWith((ref) => _Reach()),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));

  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final fontFamily = _shotsDir == null ? '' : _font;
  final theme = AppTheme(brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light, fontFamily);
  ThemeData withFallback(ThemeData t) =>
      _shotsDir == null ? t : t.copyWith(textTheme: t.textTheme.apply(fontFamily: _font, fontFamilyFallback: const ['Emoji']));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: withFallback(theme.lightTheme(null)),
          darkTheme: withFallback(theme.darkTheme(null)),
          themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          home: MuseShellFrame(isMobile: !desktop, currentIndex: tab, onTap: (_) {}, child: page),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = _shotsDir;
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _done(WidgetTester tester) async {
  // dispose the page so its timers (clock, clipboard check) stop
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}


void main() {
  setUpAll(_loadFonts);
  const phone = Size(412, 915);
  const narrow = Size(900, 720);
  const wide = Size(1280, 800);

  final pages = <String, (Widget, int, Map<String, Object>)>{
    'presets': (const MusePresetsPage(), 3, {'muse_rule_presets': '{"youtube":"direct","streaming":"proxy","privacy":"block"}'}),
    'routing': (const MuseRoutingPage(), 3, {'muse_rule_presets': '{"ai":"proxy"}', 'muse_node_rules': '[{"domain_suffix":["netflix.com"],"outbound":"🇭🇰 香港 01"}]'}),
    'node-rules': (
      const MuseNodeRulesPage(),
      3,
      {
        'muse_node_rules':
            '[{"domain_suffix":["netflix.com","disneyplus.com"],"outbound":"🇭🇰 香港 01"},{"process_name":["chrome.exe"],"package_name":["com.android.chrome"],"outbound":"gone"}]',
      },
    ),
    'remote-sets': (const MuseRemoteRuleSetsPage(), 3, {'muse_remote_rule_sets': '[{"url":"https://example.com/rules/geosite-custom.srs","outbound":"direct"}]'}),
    'sync': (const MuseSyncPage(), 3, {'muse_sync_last_at': DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch}),
    'webdav': (const MuseWebdavPage(), 3, {'muse_webdav_user': 'me@example.com'}),
    'network': (const MuseNetworkPage(), 3, {'muse_schedule': '480,1410', 'muse_quality_alert': true}),
    'node-settings': (const MuseNodeSettingsPage(), 3, {'muse_sub_user_agent': 'clash'}),
  };

  for (final b in [Brightness.light, Brightness.dark]) {
    final label = b == Brightness.light ? 'light' : 'dark';
    for (final e in pages.entries) {
      testWidgets('phone $label: ${e.key}', (tester) async {
        await _pump(tester, page: e.value.$1, brightness: b, size: phone, tab: e.value.$2, initialPrefs: e.value.$3);
        expect(tester.takeException(), isNull);
        await _shot(tester, 'phone-$label-${e.key}');
        await _done(tester);
      });
    }
    for (final s in [(narrow, 'narrow'), (wide, 'wide')]) {
      for (final key in ['presets', 'sync', 'node-rules']) {
        testWidgets('Windows ${s.$2} $label: $key', (tester) async {
          final p = pages[key]!;
          await _pump(tester, page: p.$1, brightness: b, size: s.$1, desktop: true, tab: p.$2, initialPrefs: p.$3);
          expect(tester.takeException(), isNull);
          await _shot(tester, 'windows-${s.$2}-$label-$key');
          await _done(tester);
        });
      }
    }
  }

  testWidgets('presets: sections, search, a choice is saved', (tester) async {
    await _pump(tester, page: const MusePresetsPage(), brightness: Brightness.light, size: phone, tab: 3);
    expect(find.byKey(const ValueKey('preset_group_ai')), findsOneWidget);
    expect(find.byKey(const ValueKey('preset_group_streaming')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('preset_search')), 'youtube');
    await tester.pump();
    expect(find.byKey(const ValueKey('preset_youtube')), findsOneWidget);
    expect(find.byKey(const ValueKey('preset_banks')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('preset_youtube')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick_直连')));
    await tester.pumpAndSettle();
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getString('muse_rule_presets'), contains('"youtube":"direct"'));
    await tester.enterText(find.byKey(const ValueKey('preset_search')), 'zzzz');
    await tester.pump();
    expect(find.text('没有匹配的预设'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('sync: 局域网 first, WebDAV under 更多, not branded', (tester) async {
    await _pump(tester, page: const MuseSyncPage(), brightness: Brightness.light, size: phone, tab: 3);
    expect(find.byKey(const ValueKey('lan_host')), findsOneWidget);
    expect(find.byKey(const ValueKey('lan_type')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_webdav')), findsOneWidget);
    expect(find.textContaining('坚果云'), findsNothing);
    final dy = (Key k) => tester.getTopLeft(find.byKey(k)).dy;
    expect(dy(const ValueKey('lan_host')), lessThan(dy(const ValueKey('sync_webdav'))));
    await _done(tester);
  });

  testWidgets('pairing sheet shows the QR code and the typed code, stops when closed', (tester) async {
    final ip = await tester.runAsync(MuseLanHost.lanAddress);
    if (ip == null) {
      markTestSkipped('no LAN address');
      return;
    }
    await _pump(tester, page: Scaffold(body: MuseLanHostSheet(address: ip)), brightness: Brightness.light, size: phone, tab: 3);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('lan_qr')), findsOneWidget);
    expect(find.textContaining(ip), findsOneWidget);
    await _shot(tester, 'phone-light-lan-pairing');
    await _done(tester);
  });

  testWidgets('节点 多选: pick rows, the action bar counts them', (tester) async {
    await _pump(tester, page: const MuseNodesPage(), brightness: Brightness.light, size: phone, tab: 1);
    await tester.tap(find.byKey(const ValueKey('node_select_button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('node_batch_bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('node_check_🇭🇰 香港 01')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('node_check_🇸🇬 新加坡 03')));
    await tester.pump();
    expect(find.text('已选 2 个'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shot(tester, 'phone-light-nodes-select');
    await tester.tap(find.byKey(const ValueKey('node_batch_hide')));
    await tester.pump();
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getString('muse_node_meta'), contains('香港 01'));
    expect(find.byKey(const ValueKey('node_batch_bar')), findsNothing);
    await _done(tester);
  });

  for (final w in [const Size(760, 720), narrow]) {
    testWidgets('Windows 流量 tile at large text, ${w.width.toInt()} wide', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: w, desktop: true);
      expect(tester.takeException(), isNull);
      await _shot(tester, 'windows-${w.width.toInt()}-large-text-home');
      await _done(tester);
    });
  }

  // regression: the tile grid with 网速 + 本次流量 merged into 「流量」 must not overflow at large
  // text in a narrow window (title trailing, 剩余流量 caption, tile height).
  for (final w in [const Size(320, 800), const Size(360, 800), const Size(600, 720), const Size(760, 720)]) {
    for (final scale in [1.5, 1.75, 2.0]) {
      testWidgets('MuseTileGrid(mergeFlow) no overflow at text ${scale}x, ${w.width.toInt()} wide', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          page: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(MuseSpace.s16),
              child: MuseTileGrid(mergeFlow: true),
            ),
          ),
          brightness: Brightness.light,
          size: w,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('tile_flow')), findsOneWidget);
        expect(find.byKey(const ValueKey('tile_speed')), findsNothing);
        expect(find.byKey(const ValueKey('tile_traffic')), findsNothing);
        await _shot(tester, 'tiles-merge-${w.width.toInt()}-x$scale');
        await _done(tester);
      });
    }
  }
}
