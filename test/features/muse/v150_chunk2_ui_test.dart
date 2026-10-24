// 穿云 1.5.0 (batch 1, chunk 2) screens: 高级 (IPv6 / Fake-IP), lazily built node list with a
// thousand nodes, 测速 progress, node detail (transport / TLS / port hopping / 下载测速),
// light / dark, phone / Windows 900 / 1280, 320 px at 2× text.
// MUSE_SHOTS=<dir> writes PNG screenshots for review.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/nodes/muse_nodes_page.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
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
  ConnectionStatus? status,
  bool? hasProfile = true,
  String? appVersion,
  bool preparing = false,
  Map<String, Object> initialPrefs = const {},
  OutboundGroup? group,
  List<Override> extra = const [],
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final since = DateTime.now().subtract(const Duration(minutes: 12, seconds: 34));
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => prefs),
      museConnectionProvider.overrideWithValue(AsyncData(status ?? (connected ? const Connected() : const Disconnected()))),
      museConnectPreparingProvider.overrideWith((ref) => preparing),
      museRunningProvider.overrideWithValue(connected),
      museHasProfileProvider.overrideWithValue(hasProfile),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('机场订阅'),
      museAppVersionProvider.overrideWithValue(appVersion),
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
      museNodeGroupProvider.overrideWithValue(AsyncData(group ?? _group)),
      museActiveConfigProvider.overrideWith((ref) async => _config),
      ...extra,
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


final _config = jsonEncode({
  'outbounds': [
    {
      'type': 'vless',
      'tag': '🇯🇵 东京 02',
      'server': 'jp.example.com',
      'server_port': 443,
      'flow': 'xtls-rprx-vision',
      'tls': {
        'enabled': true,
        'server_name': 'www.apple.com',
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
        'reality': {'enabled': true},
      },
    },
    {
      'type': 'hysteria2',
      'tag': '🇭🇰 香港 01',
      'server': 'hk.example.com',
      'server_port': 443,
      'server_ports': ['20000:30000'],
      'up_mbps': 50,
      'down_mbps': 200,
      'tls': {'enabled': true, 'server_name': 'hk.example.com', 'alpn': ['h3']},
    },
  ],
});

/// A subscription with [n] nodes (most tested before the current 测速 started).
OutboundGroup _big(int n, {DateTime? testedAt}) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: 'node 0',
  selectable: true,
  items: [
    for (var i = 0; i < n; i++)
      OutboundInfo(
        tag: 'node $i',
        tagDisplay: '🇯🇵 东京 ${i.toString().padLeft(4, '0')}',
        type: i.isEven ? 'vless' : 'hysteria2',
        urlTestDelay: 80 + i % 400,
        urlTestTime: Timestamp.fromDateTime(i < n ~/ 4 ? (testedAt ?? DateTime.now()) : DateTime(2026)),
      ),
  ],
);

void main() {
  setUpAll(_loadFonts);
  const phone = Size(412, 915);
  const small = Size(320, 640);
  const narrow = Size(900, 720);
  const wide = Size(1280, 800);

  for (final b in [Brightness.light, Brightness.dark]) {
    final label = b == Brightness.light ? 'light' : 'dark';
    for (final s in [(phone, 'phone', false), (narrow, 'windows-narrow', true), (wide, 'windows-wide', true)]) {
      testWidgets('${s.$2} $label: 设置 › 高级 shows IPv6 and Fake-IP, both off', (tester) async {
        await _pump(tester, page: const SettingsPage(), brightness: b, size: s.$1, desktop: s.$3, tab: 3);
        await tester.ensureVisible(find.byKey(const ValueKey('advanced_toggle')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('advanced_toggle')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(find.byKey(const ValueKey('fake_ip')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('ipv6_policy')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('ipv6_policy')), matching: find.text('关闭')), findsOneWidget);
        final fake = tester.widget<Switch>(find.descendant(of: find.byKey(const ValueKey('fake_ip')), matching: find.byType(Switch)));
        expect(fake.value, isFalse);
        // switch rows line up with the other rows
        final ipv6Title = tester.getTopLeft(find.text('IPv6'));
        final fakeTitle = tester.getTopLeft(find.text('Fake-IP'));
        expect(fakeTitle.dx, ipv6Title.dx);
        expect(tester.takeException(), isNull);
        await _shot(tester, '${s.$2}-$label-settings-advanced');
        await _done(tester);
      });
      testWidgets('${s.$2} $label: 1000 nodes build lazily, 测速 progress', (tester) async {
        final started = DateTime.now().subtract(const Duration(seconds: 1));
        await _pump(
          tester,
          page: const MuseNodesPage(),
          brightness: b,
          size: s.$1,
          desktop: s.$3,
          tab: 1,
          group: _big(1000, testedAt: DateTime.now()),
          initialPrefs: {'muse_node_sort': 'original'},
          extra: [museNodeTestStartedProvider.overrideWith((ref) => started)],
        );
        expect(tester.takeException(), isNull);
        final built = find.byType(MuseNodeRow).evaluate().length;
        expect(built, greaterThan(3));
        expect(built, lessThan(120), reason: 'only the rows on screen (plus the cache) are built');
        expect(find.text('已测 250 / 1000'), findsOneWidget);
        expect(find.text('停止'), findsOneWidget);
        await _shot(tester, '${s.$2}-$label-nodes-1000-testing');
        // scrolling far down builds the rows there
        await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -20000));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('东京 0000'), findsNothing);
        await _done(tester);
      });
    }
    testWidgets('phone $label: node detail shows transport / TLS / port hopping and 下载测速 for the node in use', (tester) async {
      await _pump(tester, page: const MuseNodesPage(), brightness: b, size: phone, tab: 1, initialPrefs: {'muse_node_sort': 'original'});
      await tester.longPress(find.byKey(const ValueKey('🇭🇰 香港 01')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('node_detail_sheet')), findsOneWidget);
      expect(find.text('端口跳跃'), findsOneWidget);
      expect(find.text('20000-30000'), findsOneWidget);
      expect(find.text('↑ 50 · ↓ 200 Mbps'), findsOneWidget);
      expect(find.text('h3'), findsOneWidget);
      // not the node in use: no 下载测速
      expect(find.byKey(const ValueKey('node_download_test')), findsNothing);
      expect(tester.takeException(), isNull);
      await _shot(tester, 'phone-$label-node-detail-hy2');
      Navigator.of(tester.element(find.byKey(const ValueKey('node_detail_sheet')))).pop();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.longPress(find.byKey(const ValueKey('🇯🇵 东京 02')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('REALITY'), findsOneWidget);
      expect(find.text('chrome'), findsOneWidget);
      expect(find.text('xtls-rprx-vision'), findsOneWidget);
      expect(find.byKey(const ValueKey('node_download_test')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shot(tester, 'phone-$label-node-detail-reality');
      await _done(tester);
    });
    testWidgets('320 px + 2× $label: node detail scrolls instead of overflowing', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, page: const MuseNodesPage(), brightness: b, size: small, tab: 1, initialPrefs: {'muse_node_sort': 'original'});
      expect(tester.takeException(), isNull);
      await tester.longPress(find.byKey(const ValueKey('🇯🇵 东京 02')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      await _shot(tester, 'small-2x-$label-node-detail');
      await _done(tester);
    });
    testWidgets('320 px + 2× $label: 测速 progress label fits', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        page: const MuseNodesPage(),
        brightness: b,
        size: small,
        tab: 1,
        group: _big(1000, testedAt: DateTime.now()),
        extra: [museNodeTestStartedProvider.overrideWith((ref) => DateTime.now().subtract(const Duration(seconds: 1)))],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('已测 250 / 1000'), findsOneWidget);
      await _shot(tester, 'small-2x-$label-nodes-testing');
      await _done(tester);
    });
  }
}
