// 穿云 1.4.0: every tab and the new settings pages render (phone light / dark, Windows ~900 and
// 1280 wide, light / dark) with fixed data, without overflow. With MUSE_SHOTS=<dir> set the frames
// are written as PNG screenshots (real CJK / emoji / icon fonts loaded) for review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
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


Map<String, Object> _statsPrefs() {
  var log = MuseTrafficLog.empty;
  final now = DateTime.now();
  for (var i = 0; i < 14; i++) {
    log = log.add(DateTime(now.year, now.month, now.day - i), (40 + i * 7) * 1024 * 1024, (300 + (i * 97) % 900) * 1024 * 1024);
  }
  for (var m = 1; m < 5; m++) {
    log = log.add(DateTime(now.year, now.month - m, 10), 2 * 1024 * 1024 * 1024, (12 + m * 3) * 1024 * 1024 * 1024);
  }
  return {'muse_traffic_log': log.toRaw()};
}

void main() {
  setUpAll(_loadFonts);
  const phone = Size(412, 915);
  const narrow = Size(900, 720);
  const wide = Size(1280, 800);

  final pages = <String, (Widget, int)>{
    'home': (const MuseHomePage(), 0),
    'nodes': (const MuseNodesPage(), 1),
    'settings': (const SettingsPage(), 3),
    'stats': (const MuseStatsPage(), 3),
    'routing': (const MuseRoutingPage(), 3),
    'sync': (const MuseSyncPage(), 3),
    'appearance': (const MuseAppearancePage(), 3),
    'node-settings': (const MuseNodeSettingsPage(), 3),
    'network': (const MuseNetworkPage(), 3),
  };

  for (final b in [Brightness.light, Brightness.dark]) {
    final label = b == Brightness.light ? 'light' : 'dark';
    for (final e in pages.entries) {
      testWidgets('phone $label: ${e.key}', (tester) async {
        await _pump(tester, page: e.value.$1, brightness: b, size: phone, tab: e.value.$2, initialPrefs: _statsPrefs());
        expect(tester.takeException(), isNull);
        await _shot(tester, 'phone-$label-${e.key}');
        await _done(tester);
      });
    }
    for (final s in [(narrow, 'narrow'), (wide, 'wide')]) {
      for (final key in ['home', 'nodes', 'settings', 'stats']) {
        testWidgets('Windows ${s.$2} $label: $key', (tester) async {
          final p = pages[key]!;
          await _pump(tester, page: p.$1, brightness: b, size: s.$1, desktop: true, tab: p.$2, initialPrefs: _statsPrefs());
          expect(tester.takeException(), isNull);
          await _shot(tester, 'windows-${s.$2}-$label-$key');
          await _done(tester);
        });
      }
    }
  }

  testWidgets('settings has the 1.4 entries', (tester) async {
    await _pump(tester, page: const SettingsPage(), brightness: Brightness.light, size: phone, tab: 3);
    for (final k in ['settings_nodes', 'settings_routing', 'settings_network', 'settings_sync', 'settings_stats']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    await _done(tester);
  });

  testWidgets('隐私模式 blurs the 首页 numbers', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: phone, initialPrefs: {'muse_privacy_mask': true});
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('privacy_mask')), findsWidgets);
    await _shot(tester, 'phone-light-home-privacy');
    await _done(tester);
  });

  testWidgets('renamed / noted / hidden nodes on 节点', (tester) async {
    await _pump(
      tester,
      page: const MuseNodesPage(),
      brightness: Brightness.light,
      size: phone,
      tab: 1,
      initialPrefs: {
        'muse_node_meta': '{"🇭🇰 香港 01":{"n":"🇭🇰 家宽香港","r":"看奈飞"},"🇹🇼 台北 01":{"h":1}}',
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('家宽香港'), findsOneWidget);
    expect(find.textContaining('看奈飞'), findsOneWidget);
    expect(find.textContaining('台北'), findsNothing);
    expect(find.byKey(const ValueKey('user_hidden_nodes_toggle')), findsOneWidget);
    await _shot(tester, 'phone-light-nodes-meta');
    await _done(tester);
  });

  testWidgets('region groups fold and show the best delay', (tester) async {
    await _pump(
      tester,
      page: const MuseNodesPage(),
      brightness: Brightness.light,
      size: phone,
      tab: 1,
      initialPrefs: {'muse_node_sort': 'region', 'muse_collapsed_regions': 'HK'},
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('· 86 ms'), findsWidgets);
    expect(find.textContaining('香港 01'), findsNothing);
    await _shot(tester, 'phone-light-nodes-regions');
    await _done(tester);
  });

  testWidgets('rule tester names the preset that matches', (tester) async {
    await _pump(
      tester,
      page: const MuseRuleTesterPage(),
      brightness: Brightness.light,
      size: phone,
      tab: 3,
      initialPrefs: {'muse_rule_presets': '{"ai":"proxy"}'},
    );
    await tester.enterText(find.byKey(const ValueKey('rule_test_field')), 'https://chatgpt.com/c/1');
    await tester.tap(find.byKey(const ValueKey('rule_test_go')));
    await tester.pump();
    expect(find.byKey(const ValueKey('rule_test_result')), findsOneWidget);
    expect(find.textContaining('预设：AI'), findsOneWidget);
    await _shot(tester, 'phone-light-rule-tester');
    await _done(tester);
  });
}
