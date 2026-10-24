// 穿云 1.5.1: the pill segmented control (首页 去广告 关 / 温和 / 强力, 统计 日 / 周 / 月) has equal
// segments with labels centred both ways at phone / Windows 900 / 1280, light / dark, 320 px + 2×;
// the Beta 通道 is gone (stable releases only).
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
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';
import 'package:hiddify/features/muse/widget/muse_segmented.dart';
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


/// Every segment of the control under [control]: equal width, the selected pill inset evenly, the
/// label centred in its segment within 1 px both ways, nothing clipped.
void _expectCentred(WidgetTester tester, Finder control, int count) {
  final box = tester.getRect(control);
  expect(box.height, greaterThanOrEqualTo(MuseSize.segmented - 0.01), reason: 'control at least 32 px tall');
  final segs = [for (var i = 0; i < count; i++) tester.getRect(find.descendant(of: control, matching: find.byKey(museSegmentKey(i))))];
  for (var i = 0; i < count; i++) {
    final seg = segs[i];
    expect(seg.width, moreOrLessEquals(segs.first.width, epsilon: 1), reason: 'segment $i same width');
    expect(seg.top - box.top, moreOrLessEquals(MuseSpace.s4, epsilon: 0.5), reason: 'top inset');
    expect(box.bottom - seg.bottom, moreOrLessEquals(MuseSpace.s4, epsilon: 0.5), reason: 'bottom inset');
    final text = tester.getRect(find.descendant(of: find.descendant(of: control, matching: find.byKey(museSegmentKey(i))), matching: find.byType(Text)));
    expect(text.center.dx, moreOrLessEquals(seg.center.dx, epsilon: 1), reason: 'segment $i label centred horizontally');
    expect(text.center.dy, moreOrLessEquals(seg.center.dy, epsilon: 1), reason: 'segment $i label centred vertically');
    expect(text.left, greaterThanOrEqualTo(seg.left - 0.5));
    expect(text.right, lessThanOrEqualTo(seg.right + 0.5));
    expect(text.top, greaterThanOrEqualTo(seg.top - 0.5));
    expect(text.bottom, lessThanOrEqualTo(seg.bottom + 0.5));
  }
  expect(segs.first.left - box.left, moreOrLessEquals(MuseSpace.s4, epsilon: 0.5), reason: 'left inset');
  expect(box.right - segs.last.right, moreOrLessEquals(MuseSpace.s4, epsilon: 0.5), reason: 'right inset');
}

void main() {
  setUpAll(_loadFonts);
  const phone = Size(412, 915);
  const small = Size(320, 640);
  const narrow = Size(900, 720);
  const wide = Size(1280, 800);
  const showAdBlock = {'muse_home_tiles_hidden': ''};
  const adblock = ValueKey('adblock_segmented');

  for (final b in [Brightness.light, Brightness.dark]) {
    final label = b == Brightness.light ? 'light' : 'dark';
    for (final s in [(phone, 'phone', false), (narrow, 'windows-900', true), (wide, 'windows-1280', true)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${s.$2} $label ${scale}x: 去广告 segments equal, labels centred', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pump(tester, page: const MuseHomePage(), brightness: b, size: s.$1, desktop: s.$3, initialPrefs: showAdBlock);
          await tester.scrollUntilVisible(find.byKey(adblock), 200, scrollable: find.byType(Scrollable).first);
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          _expectCentred(tester, find.byKey(adblock), 3);
          expect(tester.getSize(find.byKey(adblock)).height, moreOrLessEquals(MuseSize.segmented * scale, epsilon: 0.5));
          await _shot(tester, '${s.$2}-$label-${scale.toInt()}x-adblock');
          await _done(tester);
        });
      }
    }
    testWidgets('320 px + 2× $label: 去广告 control fits, no overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, page: const MuseHomePage(), brightness: b, size: small, initialPrefs: showAdBlock);
      await tester.scrollUntilVisible(find.byKey(adblock), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      _expectCentred(tester, find.byKey(adblock), 3);
      final tile = tester.getRect(find.byKey(const ValueKey('tile_adblock')));
      expect(tester.getRect(find.byKey(adblock)).bottom, lessThanOrEqualTo(tile.bottom - MuseSpace.s16 + 0.5));
      await _shot(tester, 'small-2x-$label-adblock');
      await _done(tester);
    });
    testWidgets('phone $label: 统计 日 / 周 / 月 uses the same control', (tester) async {
      await _pump(tester, page: const MuseStatsPage(), brightness: b, size: phone, tab: 3);
      expect(tester.takeException(), isNull);
      const range = ValueKey('stats_range');
      expect(find.byType(SegmentedButton<int>), findsNothing);
      _expectCentred(tester, find.byKey(range), 3);
      await tester.tap(find.descendant(of: find.byKey(range), matching: find.text('周')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      _expectCentred(tester, find.byKey(range), 3);
      expect(find.text('近 8 周流量'), findsOneWidget);
      await _shot(tester, 'phone-$label-stats');
      await _done(tester);
    });
  }

  testWidgets('tapping a segment switches 去广告', (tester) async {
    await _pump(tester, page: const MuseHomePage(), brightness: Brightness.light, size: phone, initialPrefs: showAdBlock);
    await tester.scrollUntilVisible(find.byKey(adblock), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.descendant(of: find.byKey(adblock), matching: find.text('强力')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: find.byKey(const ValueKey('tile_adblock')), matching: find.text('强力')), findsNWidgets(2));
    await _done(tester);
  });

  group('Beta 通道 removed', () {
    test('关于 has no Beta switch and 设置搜索 has no Beta keyword', () {
      final about = File('lib/features/about/widget/about_page.dart').readAsStringSync();
      expect(about.contains('about_beta'), isFalse);
      expect(about.contains('Beta 通道'), isFalse);
      expect(museSearchSettings('Beta', android: true, windows: true), isEmpty);
      expect(museSearchSettings('更新', android: true, windows: true), isNotEmpty);
    });
    test('the updater only ever offers a stable release', () {
      expect(museLatestReleaseApi, endsWith('/releases/latest'));
      expect(File('lib/features/muse/update/muse_updater.dart').readAsStringSync().contains('betaChannel'), isFalse);
      final list = [
        {'tag_name': 'v1.6.0-beta1', 'prerelease': true},
        {'tag_name': 'v1.5.1'},
      ];
      expect(musePickRelease(list)!['tag_name'], 'v1.5.1');
      expect(musePickRelease([list.first]), isNull);
    });
  });
}
