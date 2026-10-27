// 穿云 1.5.0 (batch 1) screens: 首页 stages / cancel / skeleton / one column at 320 px + 2×,
// ⓘ explanations, 更新内容 dot, 开发者选项, light / dark, phone / Windows 900 / 1280.
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
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
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
  const small = Size(320, 640);
  const narrow = Size(900, 720);
  const wide = Size(1280, 800);

  for (final b in [Brightness.light, Brightness.dark]) {
    final label = b == Brightness.light ? 'light' : 'dark';
    for (final s in [(phone, 'phone', false), (narrow, 'windows-narrow', true), (wide, 'windows-wide', true)]) {
      testWidgets('${s.$2} $label: 首页 connecting stage + cancel', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, page: const MuseHomePage(), brightness: b, size: s.$1, desktop: s.$3, status: const Connecting());
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home_stage_starting')), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('取消连接')), findsOneWidget);
        expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Shimmer'), findsOneWidget);
        semantics.dispose();
        await _shot(tester, '${s.$2}-$label-home-connecting');
        await _done(tester);
      });
      testWidgets('${s.$2} $label: 设置 (ⓘ, 开发者选项 entry)', (tester) async {
        await _pump(tester, page: const SettingsPage(), brightness: b, size: s.$1, desktop: s.$3, tab: 3);
        expect(tester.takeException(), isNull);
        await _shot(tester, '${s.$2}-$label-settings');
        await _done(tester);
      });
    }
    testWidgets('phone $label: 首页 skeleton while loading', (tester) async {
      await _pump(tester, page: const MuseHomePage(), brightness: b, size: phone, hasProfile: null);
      expect(find.byKey(const ValueKey('home_skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await _shot(tester, 'phone-$label-home-skeleton');
      await _done(tester);
    });
    testWidgets('phone $label: 开发者选项', (tester) async {
      await _pump(tester, page: const MuseDeveloperPage(), brightness: b, size: phone, tab: 3);
      expect(find.byKey(const ValueKey('node_test_workers')), findsOneWidget);
      expect(find.byKey(const ValueKey('node_test_timeout')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shot(tester, 'phone-$label-developer');
      await _done(tester);
    });
    testWidgets('320 px + 2× $label: tiles in one column, nothing overflows', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, page: const MuseHomePage(), brightness: b, size: small);
      expect(tester.takeException(), isNull);
      final speed = tester.getRect(find.byKey(const ValueKey('tile_speed')));
      final traffic = tester.getRect(find.byKey(const ValueKey('tile_traffic')));
      expect(traffic.top, greaterThan(speed.bottom - 1), reason: 'second tile goes below the first');
      expect(speed.width, greaterThan(small.width * 0.8));
      await _shot(tester, 'small-2x-$label-home');
      await _done(tester);
    });
  }

  testWidgets('#81 no subscription: 首页 shows the 添加订阅 card (already in place)', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.dark, size: phone, hasProfile: false, connected: false);
    expect(find.byKey(const ValueKey('home_empty_guide')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty_add_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('准备配置 shows while the config is prepared (status still 未连接)', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: phone, connected: false, preparing: true);
    expect(find.byKey(const ValueKey('home_stage_preparing')), findsOneWidget);
    expect(find.text('连接中'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('断开中: the switch is disabled', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: phone, status: const Disconnecting());
    final gesture = tester.widget<GestureDetector>(
      find.descendant(of: find.byKey(const ValueKey('home_connect_switch')), matching: find.byType(GestureDetector)).first,
    );
    expect(gesture.onTap, isNull);
    await _done(tester);
  });

  testWidgets('去广告 tile hidden by default, shown when the user turned it on', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: phone);
    expect(find.byKey(const ValueKey('tile_adblock')), findsNothing);
    await _done(tester);
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: phone, initialPrefs: {'muse_home_tiles_hidden': 'services,groups,connections,lanip,memory,takeover'});
    expect(find.byKey(const ValueKey('tile_adblock')), findsOneWidget);
    await _done(tester);
  });

  testWidgets('ⓘ: a section explanation is folded until tapped', (tester) async {
    await _pump(tester, page: const MuseNodeSettingsPage(), brightness: Brightness.light, size: phone, tab: 3);
    expect(find.textContaining('「自动」适合大多数订阅'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('section_info')).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('「自动」适合大多数订阅'), findsOneWidget);
    // 测速 并发数 / 超时 moved to 开发者选项
    expect(find.byKey(const ValueKey('node_test_workers')), findsNothing);
    await _done(tester);
  });

  testWidgets('ⓘ on a row: 隐私模式 explanation folded', (tester) async {
    await _pump(tester, page: const MuseAppearancePage(), brightness: Brightness.light, size: phone, tab: 3);
    expect(find.text('首页的流量、IP 等数字打码'), findsNothing);
    // 1.6.0 C7: 文字缩放 has an ⓘ too; tap the 隐私模式 one
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('appearance_privacy')), matching: find.byKey(const ValueKey('row_info'))));
    await tester.pump();
    expect(find.text('首页的流量、IP 等数字打码'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('更新内容: dot on 设置 and 关于 after a small update, gone once read', (tester) async {
    await _pump(
      tester,
      page: const SettingsPage(),
      brightness: Brightness.light,
      size: phone,
      tab: 3,
      appVersion: '1.4.1',
      initialPrefs: {'muse_changelog_seen': '1.4.0'},
    );
    expect(find.byKey(const ValueKey('muse_dot')), findsOneWidget); // 设置 tab
    expect(find.byType(MuseStatusDot), findsWidgets); // 关于 row
    await _shot(tester, 'phone-light-settings-dot');
    await _done(tester);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getString('muse_changelog_seen'), '1.4.0');
  });

  testWidgets('a small update does not pop the dialog', (tester) async {
    await _pump(
      tester,
      page: const MuseHomePage(),
      brightness: Brightness.light,
      size: phone,
      appVersion: '1.4.1',
      initialPrefs: {'muse_changelog_shown': '1.4.0', 'muse_changelog_seen': '1.4.0'},
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('changelog_dialog')), findsNothing);
    await _done(tester);
  });

  testWidgets('reduced motion: no shimmer while connecting', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: phone, status: const Connecting());
    expect(find.byKey(const ValueKey('home_stage_starting')), findsOneWidget);
    expect(museReduceMotion(tester.element(find.byType(MuseHomePage))), isTrue);
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Shimmer'), findsNothing);
    await _done(tester);
  });
}
