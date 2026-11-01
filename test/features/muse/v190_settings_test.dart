// 穿云 1.9.0 设置整理：#5 自动连接页（后续项继续追加在本文件）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/settings/auto_connect_page.dart';
import 'package:hiddify/features/muse/settings/keep_alive_page.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester t, Widget home, {Map<String, Object> prefs = const {}, List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp), ...overrides]);
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  t.view.physicalSize = const Size(400, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)), home: home),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return c;
}

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('#5 自动连接', () {
    testWidgets('Android: 自动运行 switch, 按需运行 row, 定时 rows; no Windows rows', (t) async {
      final c = await _pump(t, const MuseAutoConnectPage(android: true, windows: false), prefs: {'muse_schedule': '480,-1'});
      expect(find.text('自动连接'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_on_demand')), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('network_schedule_disconnect')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_autostart')), findsNothing);
      expect(c.read(MusePrefs.autoRun), isFalse);
      await t.tap(find.byKey(const ValueKey('settings_auto_run')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.autoRun), isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('neither platform: no 自动运行 (Android-only)', (t) async {
      await _pump(t, const MuseAutoConnectPage(android: false, windows: false));
      expect(find.byKey(const ValueKey('settings_auto_run')), findsNothing);
      expect(find.byKey(const ValueKey('settings_on_demand')), findsOneWidget);
    });

    test('Windows rows 开机自启 / 开机自启时静默 live on the page, not in 电脑 / 网络 / 通用', () {
      final page = _src('lib/features/muse/settings/auto_connect_page.dart');
      expect(page, contains("title: '开机自启'"));
      expect(page, contains("title: '开机自启时静默'"));
      expect(page, contains("if (isWindows) const _WindowsStartSection()"));
      final win = _src('lib/features/muse/settings/windows_settings.dart');
      expect(win, isNot(contains("title: '开机自启'")));
      expect(win, isNot(contains("settings_on_demand")));
      expect(_src('lib/features/muse/settings/network_page.dart'), isNot(contains('network_schedule_connect')));
      expect(_src('lib/features/muse/settings/android_settings.dart'), isNot(contains('settings_auto_run')));
      final settings = _src('lib/features/settings/overview/settings_page.dart');
      expect(settings, contains("ValueKey('settings_auto_connect')"));
      expect(settings, contains('case MuseSettingPage.autoConnect:'));
    });

    test('summary', () {
      const off = MuseSchedule();
      expect(museAutoConnectSummary(autoRun: false, onDemand: false, schedule: off, autoStart: false), '关');
      expect(
        museAutoConnectSummary(autoRun: true, onDemand: true, schedule: const MuseSchedule(connectAt: 60), autoStart: true),
        '自动运行、按需、定时、开机自启',
      );
      expect(museAutoConnectSummary(autoRun: false, onDemand: false, schedule: const MuseSchedule(disconnectAt: 60), autoStart: false), '定时');
    });

    test('search finds every moved row on 自动连接', () {
      for (final (q, android, windows) in [('自动运行', true, false), ('按需运行', true, false), ('定时', true, false), ('开机自启', false, true), ('开机自启时静默', false, true), ('自动连接', true, false)]) {
        final hits = museSearchSettings(q, android: android, windows: windows);
        expect(hits.first.page, MuseSettingPage.autoConnect, reason: q);
      }
    });
  });

  group('#6 后台保活', () {
    testWidgets('one page: 允许后台运行, 自启动, 不在最近任务显示, 本机设置步骤', (t) async {
      final c = await _pump(
        t,
        const MuseKeepAlivePage(),
        prefs: {'muse_kill_count': 2},
        overrides: [batteryOptimizationNotifierProvider.overrideWith(_FakeBattery.new)],
      );
      expect(find.byKey(const ValueKey('keep_alive_battery')), findsOneWidget);
      expect(find.byKey(const ValueKey('keep_alive_autostart')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_background_guide')), findsOneWidget);
      expect(find.text('去开启'), findsOneWidget);
      expect(find.text('去设置'), findsOneWidget);
      expect(c.read(Preferences.excludeFromRecents), isFalse);
      expect(t.takeException(), isNull);
    });

    test('needs attention while either is missing', () {
      expect(museKeepAliveNeedsAttention(batteryIgnored: true, autostartVisited: true), isFalse);
      expect(museKeepAliveNeedsAttention(batteryIgnored: null, autostartVisited: true), isFalse);
      expect(museKeepAliveNeedsAttention(batteryIgnored: false, autostartVisited: true), isTrue);
      expect(museKeepAliveNeedsAttention(batteryIgnored: true, autostartVisited: false), isTrue);
    });

    test('no duplicates: guide, kill dialog and 设置 share the actions; privacy keeps one row', () {
      final privacy = _src('lib/features/muse/settings/privacy_page.dart');
      for (final s in ["'允许后台运行'", "'自启动'", "'不在最近任务显示'", 'openAutostartSettings', 'requestToIgnore', 'showMuseBackgroundGuide']) {
        expect(privacy, isNot(contains(s)), reason: s);
      }
      expect(privacy, contains("ValueKey('settings_keep_alive')"));
      for (final p in ['lib/features/muse/home/keep_alive_guide.dart', 'lib/features/muse/home/background_guard.dart']) {
        final s = _src(p);
        expect(s, isNot(contains('openAutostartSettings')), reason: p);
        expect(s, isNot(contains('requestToIgnore')), reason: p);
        expect(s, contains('museOpenAutostart(ref)'), reason: p);
      }
      // the only callers of the platform actions outside the page itself are gone
      final page = _src('lib/features/muse/settings/keep_alive_page.dart');
      expect('openAutostartSettings'.allMatches(page).length, 1);
    });

    test('search: old names land on 后台保活', () {
      for (final q in ['允许后台运行', '自启动', '最近任务', '后台保活指南', '保活']) {
        final hits = museSearchSettings(q, android: true, windows: false);
        expect(hits.first.page, MuseSettingPage.keepAlive, reason: q);
      }
      expect(museSearchSettings('保活', android: false, windows: true), isEmpty);
    });
  });
}

class _FakeBattery extends BatteryOptimizationNotifier {
  @override
  Future<bool> build() async => false;
}
