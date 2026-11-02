// 穿云 1.9.0 设置整理：#5 自动连接页、#6 后台保活、#7 导出备份合一、#8 备份与同步 / 内核与资源、#9 测试页仅调试版、#10 搜索索引与旧入口（后续项继续追加在本文件）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/auto_connect_page.dart';
import 'package:hiddify/features/muse/home/keep_alive_guide.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/settings/resources_page.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
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

  group('#6 后台保活 (1.10.0: page removed, one battery hint on the first connection)', () {
    Future<ProviderContainer> host(WidgetTester t, {Map<String, Object> prefs = const {}, bool android = true, bool? ignored = false}) => _pump(
      t,
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            key: const ValueKey('connected'),
            onPressed: () => museMaybeShowKeepAliveGuide(context, ref, android: android, batteryIgnored: () async => ignored),
            child: const Text('connected'),
          ),
        ),
      ),
      prefs: prefs,
      overrides: [batteryOptimizationNotifierProvider.overrideWith(_FakeBattery.new)],
    );

    testWidgets('shown once: the second connection opens nothing', (t) async {
      final c = await host(t);
      _FakeBattery.requests = 0;
      await t.tap(find.byKey(const ValueKey('connected')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('keep_alive_hint')), findsOneWidget);
      expect(c.read(Preferences.keepAliveGuideShown), isTrue);
      await t.tap(find.byKey(const ValueKey('keep_alive_hint_later')));
      await t.pumpAndSettle();
      expect(_FakeBattery.requests, 0);
      await t.tap(find.byKey(const ValueKey('connected')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('keep_alive_hint')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('「去设置」 asks the system once for the battery exemption', (t) async {
      await host(t);
      _FakeBattery.requests = 0;
      await t.tap(find.byKey(const ValueKey('connected')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('keep_alive_hint_go')));
      await t.pumpAndSettle();
      expect(_FakeBattery.requests, 1);
    });

    testWidgets('never when already exempt, already shown (same key as before), or not Android', (t) async {
      for (final (prefs, android, ignored) in [
        (const <String, Object>{}, true, true),
        (const <String, Object>{'keep_alive_guide_shown': true}, true, false),
        (const <String, Object>{}, false, false),
      ]) {
        final c = await host(t, prefs: prefs, android: android, ignored: ignored);
        await t.tap(find.byKey(const ValueKey('connected')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('keep_alive_hint')), findsNothing, reason: '$prefs $android $ignored');
        // not marked as shown when it did not open (a later first connection on an un-exempted phone still gets it)
        if (!prefs.containsKey('keep_alive_guide_shown')) expect(c.read(Preferences.keepAliveGuideShown), isFalse);
        await t.pumpWidget(const SizedBox.shrink());
      }
    });

    test('the page, its route, the per-brand dialog and the 自启动 row are gone', () {
      expect(File('lib/features/muse/settings/keep_alive_page.dart').existsSync(), isFalse);
      expect(MuseSettingPage.values.map((e) => e.name), isNot(contains('keepAlive')));
      for (final p in ['lib/features/muse/home/keep_alive_guide.dart', 'lib/features/muse/home/background_guard.dart']) {
        final s = _src(p);
        expect(s, isNot(contains('keep_alive_page')), reason: p);
        expect(s, isNot(contains('openAutostartSettings')), reason: p);
        expect(s, isNot(contains('showMuseBackgroundGuide')), reason: p);
      }
      // no background work for the hint: no timers, no periodic checks
      final guide = _src('lib/features/muse/home/keep_alive_guide.dart');
      expect(guide, isNot(contains('Timer')));
      expect(guide, isNot(contains('periodic')));
    });

    test('search: the removed rows lead nowhere dead', () {
      for (final q in ['后台保活', '自启动', '最近任务', '后台保活指南']) {
        for (final h in museSearchSettings(q, android: true, windows: false)) {
          expect(h.page.path, isNot(contains('后台保活')), reason: q);
        }
      }
    });
  });

  group('#7 导出备份合一', () {
    Future<List<MuseExportBackupChoice?>> open(WidgetTester t) async {
      final got = <MuseExportBackupChoice?>[];
      await _pump(
        t,
        Builder(builder: (c) => Scaffold(body: TextButton(key: const ValueKey('open'), onPressed: () async => got.add(await showMuseExportBackupDialog(c)), child: const Text('open')))),
      );
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      return got;
    }

    testWidgets('plain with password', (t) async {
      final got = await open(t);
      await t.enterText(find.byKey(const ValueKey('backup_export_password')), 'pw1');
      await t.tap(find.byKey(const ValueKey('backup_export_ok')));
      await t.pumpAndSettle();
      expect(got.single, (redact: false, password: 'pw1'));
    });

    testWidgets('脱敏 ticked: password field off and ignored', (t) async {
      final got = await open(t);
      await t.enterText(find.byKey(const ValueKey('backup_export_password')), 'pw1');
      await t.tap(find.byKey(const ValueKey('backup_export_redact')));
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const ValueKey('backup_export_password'))).enabled, isFalse);
      await t.tap(find.byKey(const ValueKey('backup_export_ok')));
      await t.pumpAndSettle();
      expect(got.single, (redact: true, password: ''));
    });

    testWidgets('cancel = null', (t) async {
      final got = await open(t);
      await t.tap(find.byKey(const ValueKey('backup_export_cancel')));
      await t.pumpAndSettle();
      expect(got.single, isNull);
    });

    test('one button on the page, file name follows the choice', () {
      final page = _src('lib/features/muse/settings/sync_pages.dart');
      expect(page, contains("ValueKey('backup_export')"));
      expect(page, isNot(contains('backup_export_redacted')));
      expect(page, isNot(contains("'导出脱敏备份'")));
      expect(museBackupFileName(redact: true), 'chuanyun-backup-redacted.json');
      expect(museBackupFileName(redact: false), 'chuanyun-backup.json');
    });
  });

  group('#8 备份与同步 / 内核与资源', () {
    testWidgets('备份与同步: 备份 → WebDAV → 局域网 on one page', (t) async {
      await _pump(t, const MuseSyncPage(), prefs: {'muse_webdav_user': 'u'});
      expect(find.text('备份与同步'), findsOneWidget);
      double y(String k) => t.getTopLeft(find.byKey(ValueKey(k), skipOffstage: false)).dy;
      for (final k in ['backup_export', 'backup_import', 'backup_auto', 'sync_webdav', 'backup_sync_webdav_now', 'lan_host']) {
        await t.scrollUntilVisible(find.byKey(ValueKey(k)), 200);
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(y('backup_auto') < y('sync_webdav'), isTrue);
      expect(y('sync_webdav') < y('lan_host'), isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('立即同步 only once WebDAV is set', (t) async {
      await _pump(t, const MuseSyncPage());
      await t.scrollUntilVisible(find.byKey(const ValueKey('sync_webdav')), 200);
      expect(find.byKey(const ValueKey('backup_sync_webdav_now')), findsNothing);
    });

    testWidgets('内核与资源: 内核 + 内核版本 + Geo 数据库 + 规则集', (t) async {
      final dir = Directory.systemTemp.createTempSync('v190-res');
      addTearDown(() => dir.deleteSync(recursive: true));
      await _pump(t, MuseResourcesPage(baseDir: dir.path, showCore: true, desktop: false));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      expect(find.text('内核与资源'), findsOneWidget);
      expect(find.byKey(const ValueKey('core_kind')), findsOneWidget);
      expect(find.byKey(const ValueKey('core_kind_version')), findsOneWidget);
      expect(find.text('Geo 数据库'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('res_remote_manage')), 300);
      expect(find.text('规则集'), findsOneWidget);
      expect(find.textContaining('双内核版本提供'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('内核与资源 without 内核 where there is no choice', (t) async {
      await _pump(t, MuseResourcesPage(baseDir: Directory.systemTemp.path, showCore: false));
      expect(find.byKey(const ValueKey('core_kind')), findsNothing);
    });

    test('设置: one 内核与资源 row, no separate 内核 section; 备份与同步 row', () {
      final s = _src('lib/features/settings/overview/settings_page.dart');
      expect(s, isNot(contains('const MuseCoreKindSection()')));
      expect(s, contains("title: '内核与资源'"));
      expect(s, contains("title: '备份与同步'"));
      expect(s, isNot(contains("title: '同步与备份'")));
      expect(MuseSettingPage.sync.path, '设置 › 备份与同步');
      expect(MuseSettingPage.resources.path, '设置 › 内核与资源');
    });
  });

  group('#9 测试页仅调试版', () {
    const testRows = ['dev_theme_preview', 'dev_toast_test', 'dev_crash_test'];

    testWidgets('release build: no 测试页 on 开发者选项', (t) async {
      await _pump(t, const MuseDeveloperPage(debugTools: false), prefs: {'muse_dev_mode': true});
      for (final k in testRows) {
        expect(find.byKey(ValueKey(k), skipOffstage: false), findsNothing, reason: k);
      }
      expect(find.text('测试页 · 仅调试版', skipOffstage: false), findsNothing);
      await t.scrollUntilVisible(find.byKey(const ValueKey('dev_turn_off')), 300);
      expect(find.byKey(const ValueKey('dev_debug_log'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('debug build: 主题预览 / 消息样式测试 / 崩溃记录测试 together', (t) async {
      await _pump(t, const MuseDeveloperPage() /* tests run as a debug build */, prefs: {'muse_dev_mode': true});
      for (final k in testRows) {
        await t.scrollUntilVisible(find.byKey(ValueKey(k)), 200);
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
    });

    test('default follows kDebugMode; 外观 has no 主题预览', () {
      expect(_src('lib/features/muse/settings/developer_page.dart'), contains('this.debugTools = kDebugMode'));
      expect(_src('lib/features/muse/settings/appearance_page.dart'), isNot(contains('MuseThemePreviewPage')));
    });

    test('search: 测试页 only in a debug build with 开发者选项 on', () {
      for (final q in ['主题预览', '单选示例', '开关示例', '消息样式测试', '崩溃记录测试']) {
        expect(museSearchSettings(q, android: true, windows: true, developer: true, debugBuild: false), isEmpty, reason: q);
        expect(museSearchSettings(q, android: true, windows: true), isEmpty, reason: q);
        expect(museSearchSettings(q, android: true, windows: true, developer: true), isNotEmpty, reason: q);
      }
      // the rest of 开发者选项 stays searchable in release
      expect(museSearchSettings('调试日志', android: true, windows: true, developer: true, debugBuild: false), isNotEmpty);
    });
  });

  group('#10 搜索索引：旧名仍能搜到并跳到新位置', () {
    test('old names → the new page, first hit', () {
      const moved = <String, MuseSettingPage>{
        '同步与备份': MuseSettingPage.sync,
        '导出脱敏备份': MuseSettingPage.sync,
        '脱敏': MuseSettingPage.sync,
        '资源': MuseSettingPage.resources,
        '内核': MuseSettingPage.resources,
        '兼容内核': MuseSettingPage.resources,
        '内核版本': MuseSettingPage.resources,
        'geoip': MuseSettingPage.resources,
        'Geo 数据库': MuseSettingPage.resources,
        '内置规则集': MuseSettingPage.resources,
        '自动运行': MuseSettingPage.autoConnect,
        '按需运行': MuseSettingPage.autoConnect,
        '定时连接': MuseSettingPage.autoConnect,
      };
      moved.forEach((q, page) {
        final hits = museSearchSettings(q, android: true, windows: true);
        expect(hits, isNotEmpty, reason: q);
        expect(hits.first.page, page, reason: q);
      });
    });

    test('nothing still points at a page that moved', () {
      for (final e in museSettingEntries) {
        expect(e.page.path, isNot(contains('同步与备份')), reason: e.title);
        expect(e.page.path, isNot(endsWith('› 资源')), reason: e.title);
        expect(e.page.path, isNot(contains('外观 › 主题预览')), reason: e.title);
        if (e.title == '内核' || e.title == '内核版本') expect(e.page, MuseSettingPage.resources);
      }
      // each title once
      final titles = museSettingEntries.map((e) => '${e.title}|${e.androidOnly}|${e.windowsOnly}').toList();
      expect(titles.toSet().length, titles.length);
    });

    test('old entry points open the new pages', () {
      final s = _src('lib/features/settings/overview/settings_page.dart');
      expect(s, contains('case MuseSettingPage.sync:\n          musePushPage(context, const MuseSyncPage());'));
      expect(s, contains('case MuseSettingPage.resources:\n          musePushPage(context, const MuseResourcesPage());'));
      // the 资源 row (same key) now opens 内核与资源
      expect(s, contains("key: const ValueKey('settings_resources')"));
      expect(_src('lib/features/muse/activity/dns_view.dart'), contains('设置 › 内核与资源'));
      expect(_src('lib/features/muse/settings/sync_pages.dart'), contains('设置 › 备份与同步 › 扫码或输入配对码'));
    });
  });
}

class _FakeBattery extends BatteryOptimizationNotifier {
  static int requests = 0;

  @override
  Future<bool> build() async => false;

  @override
  Future<void> requestToIgnore() async => requests++;
}
