// 穿云 1.3.0: the dashboard 首页 and the 节点 tab render (phone light / dark, Windows 1280×800)
// with fixed data, without overflow. With MUSE_SHOTS=<dir> set the frames are also written as
// PNG screenshots (real CJK / emoji / icon fonts loaded) for review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
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
}) async {
  SharedPreferences.setMockInitialValues({});
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
  const windows = Size(1280, 800);

  for (final b in [Brightness.light, Brightness.dark]) {
    final label = b == Brightness.light ? 'light' : 'dark';
    testWidgets('phone $label: 首页 dashboard', (tester) async {
      await _pump(tester, page: const MuseHomePage(), brightness: b, size: phone);
      expect(tester.takeException(), isNull);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('规则模式'), findsOneWidget);
      expect(find.byKey(const ValueKey('home_connect_switch')), findsOneWidget);
      for (final t in ['网速', '本次流量', '剩余流量', '到期', '出口 IP']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      // 1.5.0: 去广告 is hidden by default
      expect(find.text('去广告'), findsNothing);
      expect(find.text('45.76.*.*'), findsOneWidget);
      expect(find.text('29 天'), findsOneWidget);
      // the node list is not on 首页 any more
      expect(find.byKey(const ValueKey('home_node_list')), findsNothing);
      await _shot(tester, 'phone-$label-home');
      await _done(tester);
    });
    testWidgets('phone $label: 节点 tab', (tester) async {
      await _pump(tester, page: const MuseNodesPage(), brightness: b, size: phone, tab: 1);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('home_node_list')), findsOneWidget);
      expect(find.byKey(const ValueKey('node_selected_bar')), findsOneWidget);
      expect(find.text('86 ms'), findsWidgets);
      expect(find.text('超时'), findsOneWidget);
      await _shot(tester, 'phone-$label-nodes');
      await _done(tester);
    });
  }

  testWidgets('phone light: 首页 while disconnected (node still pickable)', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: phone, connected: false);
    expect(tester.takeException(), isNull);
    expect(find.text('未连接'), findsWidgets);
    expect(find.byKey(const ValueKey('home_current_node')), findsOneWidget);
    await _shot(tester, 'phone-light-home-disconnected');
    await _done(tester);
  });

  testWidgets('Windows 1280×800: 首页 with tiles in 2 columns (1.6.0: 4 from 860 px) and the node column', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: windows, desktop: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('home_side_nodes')), findsOneWidget);
    // 1.6.0: the dashboard beside the node column is under 860 px: 2 tiles a row (网速 / 本次流量)
    final y1 = tester.getTopLeft(find.byKey(const ValueKey('tile_speed'))).dy;
    expect(tester.getTopLeft(find.byKey(const ValueKey('tile_traffic'))).dy, y1);
    expect(tester.getTopLeft(find.byKey(const ValueKey('tile_remaining'))).dy, greaterThan(y1));
    expect(tester.getSize(find.byKey(const ValueKey('tile_speed'))).height, tester.getSize(find.byKey(const ValueKey('tile_exit'))).height);
    await _shot(tester, 'windows-light-home');
    await _done(tester);
  });

  testWidgets('Windows 1280×800 dark: 首页', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.dark, size: windows, desktop: true);
    expect(tester.takeException(), isNull);
    await _shot(tester, 'windows-dark-home');
    await _done(tester);
  });

  testWidgets('Windows 1280×800: 节点 tab', (tester) async {
    await _pump(tester, page: const MuseNodesPage(), brightness: Brightness.light, size: windows, desktop: true, tab: 1);
    expect(tester.takeException(), isNull);
    await _shot(tester, 'windows-light-nodes');
    await _done(tester);
  });
}
