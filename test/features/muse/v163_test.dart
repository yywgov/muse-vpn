// 穿云 1.6.3: 首页 has a visible way into the tile editor — an 「编辑首页」 icon in the top bar and an
// 「编辑首页」 button after the tiles, on a phone and on a wide / Windows-sized window. Both open the
// same editor as a long-press on a tile, which now explains show / hide and drag to reorder.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
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
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Exit extends MuseExitNotifier {
  _Exit() : super(() => 0) {
    state = const MuseExitResult(info: MuseExitInfo(ip: '45.76.112.9', country: 'JP'));
  }
}

class _Reach extends MuseReachNotifier {
  _Reach() : super(() => 0) {
    state = MuseReach.ok;
  }
}

class _History extends MuseSpeedHistory {
  @override
  List<int> build() => [for (var i = 0; i < 30; i++) 1000 * i];
}

final _group = OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '节点 0',
  selectable: true,
  items: [for (var i = 0; i < 5; i++) OutboundInfo(tag: '节点 $i', tagDisplay: '节点 $i', type: 'vless', urlTestDelay: 50 + i)],
);

const _phone = Size(390, 844);
const _wide = Size(1280, 800);

Future<void> _pump(WidgetTester tester, {required Size size, bool desktop = false, bool? hasProfile = true}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => prefs),
      museConnectionProvider.overrideWithValue(const AsyncData(Connected())),
      museRunningProvider.overrideWithValue(true),
      museHasProfileProvider.overrideWithValue(hasProfile),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('机场订阅'),
      museAppVersionProvider.overrideWithValue(null),
      museSubInfoProvider.overrideWithValue(
        SubscriptionInfo(upload: 1024, download: 1024 * 1024, total: 1024 * 1024 * 1024, expire: DateTime.now().add(const Duration(days: 20))),
      ),
      museStatsProvider.overrideWithValue(SystemInfo(uplink: Int64(1024), downlink: Int64(4096), uplinkTotal: Int64(1 << 20), downlinkTotal: Int64(1 << 24))),
      museSpeedHistoryProvider.overrideWith(_History.new),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
      museConnectedSinceProvider.overrideWith((ref) async => DateTime.now()),
      museExitProvider.overrideWith((ref) => _Exit()),
      museReachProvider.overrideWith((ref) => _Reach()),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));

  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final theme = AppTheme(AppThemeMode.light, '');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme.lightTheme(null),
        home: MuseShellFrame(isMobile: !desktop, currentIndex: 0, onTap: (_) {}, child: const MuseHomePage()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _expectEditorOpen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byKey(const ValueKey('tile_editor')), findsOneWidget);
  expect(find.byKey(const ValueKey('tile_editor_hint')), findsOneWidget);
  expect(find.textContaining('拖动排序'), findsOneWidget);
  expect(find.byKey(const ValueKey('tile_edit_speed')), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final (name, size, desktop) in [('手机', _phone, false), ('宽屏 / Windows', _wide, true)]) {
    testWidgets('1.6.3 $name: the top-bar 编辑首页 icon is there and opens the tile editor', (tester) async {
      await _pump(tester, size: size, desktop: desktop);
      final button = find.byKey(const ValueKey('home_edit_button'));
      expect(button, findsOneWidget);
      expect(find.byTooltip('编辑首页'), findsOneWidget);
      expect(tester.getRect(button).top, lessThan(100), reason: 'in the top bar');
      expect(find.byKey(const ValueKey('tile_editor')), findsNothing);
      await tester.tap(button);
      await _expectEditorOpen(tester);
      await _done(tester);
    });

    testWidgets('1.6.3 $name: the 编辑首页 button after the tiles opens the tile editor', (tester) async {
      await _pump(tester, size: size, desktop: desktop);
      final button = find.byKey(const ValueKey('home_edit_tiles'));
      await tester.scrollUntilVisible(button, 200, scrollable: find.descendant(of: find.byKey(const ValueKey('home_dashboard')), matching: find.byType(Scrollable)).first);
      expect(find.descendant(of: button, matching: find.text('编辑首页')), findsOneWidget);
      await tester.tap(button);
      await _expectEditorOpen(tester);
      await _done(tester);
    });
  }

  testWidgets('1.6.3: long-press on a tile still opens the editor', (tester) async {
    await _pump(tester, size: _phone);
    await tester.longPress(find.text('网速').first);
    await _expectEditorOpen(tester);
    await _done(tester);
  });

  testWidgets('1.6.3: no edit icon before there is a subscription (nothing to edit)', (tester) async {
    await _pump(tester, size: _phone, hasProfile: false);
    expect(find.byKey(const ValueKey('home_edit_button')), findsNothing);
    expect(find.byKey(const ValueKey('home_edit_tiles')), findsNothing);
    await _done(tester);
  });
}
