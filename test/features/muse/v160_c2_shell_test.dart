// 穿云 1.6.0 C2: adaptive shell (dock / rail / sidebar), tab transitions, smoke routes, window.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/desktop/smoke_control.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(
  WidgetTester t, {
  required Size size,
  int index = 0,
  Map<String, Object> prefs = const {},
  String location = '',
  List<int>? taps,
  List<String>? extras,
  bool reduceMotion = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)),
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: reduceMotion), child: child!),
        home: MuseShellFrame(
          isMobile: size.width <= 600,
          currentIndex: index,
          location: location,
          onTap: (i) => taps?.add(i),
          onExtra: (r) => extras?.add(r),
          child: Text('page$index'),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return c;
}

void main() {
  test('nav form by width', () {
    expect(museNavForm(390), MuseNavForm.dock);
    expect(museNavForm(600), MuseNavForm.dock);
    expect(museNavForm(700), MuseNavForm.rail);
    expect(museNavForm(840), MuseNavForm.rail);
    expect(museNavForm(1000), MuseNavForm.sidebar);
  });

  test('extras: 连接 always, 日志 only with 日志记录 on', () {
    expect(museShellExtras(logCapture: false, logsAvailable: true).map((e) => e.title), ['连接']);
    expect(museShellExtras(logCapture: true, logsAvailable: true).map((e) => e.title), ['连接', '日志']);
  });

  testWidgets('phone: floating dock by default, docked when chosen', (t) async {
    final taps = <int>[];
    await _pump(t, size: const Size(390, 800), taps: taps);
    expect(find.byKey(const ValueKey('muse_dock_floating')), findsOneWidget);
    for (final l in ['首页', '节点', '订阅', '设置']) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('连接'), findsNothing);
    await t.tap(find.text('订阅'));
    expect(taps, [2]);
    await _pump(t, size: const Size(390, 800), prefs: {'muse_dock_style': 'docked'});
    expect(find.byKey(const ValueKey('muse_dock_docked')), findsOneWidget);
  });

  testWidgets('700 wide: collapsed rail without labels, no expand toggle', (t) async {
    await _pump(t, size: const Size(700, 800));
    expect(find.byKey(const ValueKey('muse_sidebar_collapsed')), findsOneWidget);
    expect(find.byKey(const ValueKey('muse_sidebar_toggle')), findsNothing);
    expect(find.text('订阅'), findsNothing); // tooltip only
    expect(find.byKey(const ValueKey('muse_nav_connections')), findsOneWidget);
  });

  testWidgets('1000 wide: expanded sidebar with 连接, collapse is remembered', (t) async {
    final extras = <String>[];
    final c = await _pump(t, size: const Size(1000, 800), extras: extras);
    expect(find.byKey(const ValueKey('muse_sidebar_expanded')), findsOneWidget);
    expect(find.text('订阅'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('日志'), findsNothing);
    await t.tap(find.text('连接'));
    expect(extras, ['connections']);
    await t.tap(find.byKey(const ValueKey('muse_sidebar_toggle')));
    await t.pumpAndSettle();
    expect(c.read(MusePrefs.sidebarExpanded), isFalse);
    expect(find.byKey(const ValueKey('muse_sidebar_collapsed')), findsOneWidget);
  });

  testWidgets('sidebar marks 连接 selected on its page and shows 日志 when capturing', (t) async {
    await _pump(t, size: const Size(1000, 800), index: 3, location: '/settings/connections', prefs: {'muse_log_capture': true});
    expect(find.text('日志'), findsOneWidget);
    final sem = t.getSemantics(find.byKey(const ValueKey('muse_nav_connections')));
    expect(sem, containsSemantics(isSelected: true));
  });

  testWidgets('tab switch fades in (220 ms) and is instant with reduced motion', (t) async {
    Future<double> opacityAfterSwitch({required bool reduce}) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(sharedPreferencesProvider.future));
      Widget app(int i) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: reduce), child: child!),
          home: MuseShellFrame(isMobile: true, currentIndex: i, onTap: (_) {}, child: Text('p$i')),
        ),
      );
      await t.pumpWidget(app(0));
      await t.pumpWidget(app(1));
      await t.pump(const Duration(milliseconds: 50));
      final o = t.widget<FadeTransition>(find.byKey(const ValueKey('muse_tab_fade'))).opacity.value;
      await t.pumpAndSettle();
      return o;
    }

    expect(await opacityAfterSwitch(reduce: false), lessThan(1));
    expect(await opacityAfterSwitch(reduce: true), 1);
  });

  testWidgets('2x text in the dock on a narrow phone does not overflow', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
    addTearDown(c.dispose);
    await t.runAsync(() => c.read(sharedPreferencesProvider.future));
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
        home: MuseShellFrame(isMobile: true, currentIndex: 0, onTap: (_) {}, child: const SizedBox()),
      ),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  test('breakpoints follow the width on every platform', () {
    final src = File('lib/core/router/go_router/helper/active_breakpoint_notifier.dart').readAsStringSync();
    expect(src.contains('PlatformUtils.isAndroid'), isFalse);
    expect(Breakpoint.eMobile, 600);
  });

  test('smoke control can open every page the smoke test shoots', () {
    expect(museSmokeRoutes, containsAll(['config', 'settings', 'about', 'connections', 'home']));
    final ps = File('tool/smoke/app_smoke.ps1').readAsStringSync();
    expect(ps.contains('CHUANYUN_SMOKE_CONTROL'), isTrue);
    expect(ps.contains('/sheet?name=add-profile'), isTrue);
    for (final shot in ['1-home', '2-config', '3-settings', '3b-about', '2b-add-profile']) {
      expect(ps.contains(shot), isTrue, reason: shot);
    }
  });

  test('window minimum size 360 x 560 (#152) and predictive back on Android', () {
    expect(minimumWindowSize, const Size(360, 560));
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('android:enableOnBackInvokedCallback="true"'), isTrue);
    expect(manifest.contains('com.chuanyun.app') || File('android/app/build.gradle').existsSync() || File('android/app/build.gradle.kts').existsSync(), isTrue);
  });
}
