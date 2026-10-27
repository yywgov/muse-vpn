// 穿云 1.6.0 C10 资源 / 备份增强 / 关于 / 开发者选项 (+ 主题预览, C7 顺延): the restore plan
// (恢复范围 × 恢复策略, subscriptions only added), the preview dialog and 覆盖 second
// confirmation, 资源 page (bundled rule-set files, remote sets, placeholders), 关于 (版本与构建号,
// 内核版本, GPL credits, version ×7 → 开发者选项), hidden 开发者选项 in 设置 and search,
// 清除缓存 only touching the app's own temp files.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/muse/data/bundled_rule_sets.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/logic/restore_plan.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/settings/resources_page.dart';
import 'package:hiddify/features/muse/settings/restore_preview.dart';
import 'package:hiddify/features/muse/settings/theme_preview_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Info extends AppInfo {
  @override
  Future<AppInfoEntity> build() async => const AppInfoEntity(
    name: '穿云',
    version: '1.6.0',
    buildNumber: '160',
    release: Release.general,
    operatingSystem: 'android',
    operatingSystemVersion: '14',
    environment: Environment.prod,
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget page, {
  Map<String, Object> prefs = const {},
  Size size = const Size(412, 915),
  double textScale = 1,
  String? engine,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      museRunningProvider.overrideWithValue(false),
      appInfoProvider.overrideWith(_Info.new),
      museEngineVersionProvider.overrideWith((ref) async => engine),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  await tester.runAsync(() => container.read(appInfoProvider.future));
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
          child: page,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

const _keys = {'muse_accent', 'muse_hosts', 'muse_dns_preset', 'muse_text_scale_pct'};

void main() {
  group('C10 恢复预览 plan', () {
    final current = <String, Object?>{
      'muse_accent': 'blue',
      'muse_hosts': 'a 1.1.1.1',
      'muse_dns_preset': 'cf',
      'sub:https://a.example/sub': '机场 A',
      'sub:https://keep.example/sub': '只在本机',
    };
    final backup = <String, Object?>{
      'muse_accent': 'green',
      'muse_hosts': 'a 1.1.1.1',
      'muse_text_scale_pct': 110,
      'unknown_key': 'x',
      'sub:https://a.example/sub': '机场 A',
      'sub:https://b.example/sub': '机场 B',
      'sub:https://c.example/sub': '',
    };

    test('合并 (default): only the backup\'s settings that differ; new subscriptions added', () {
      final p = museRestorePlan(current: current, backup: backup, settingKeys: _keys);
      expect(p.settings, {'muse_accent': 'green', 'muse_text_scale_pct': 110});
      expect(p.settingsReset, 0);
      expect(p.subsToAdd.map((s) => s.url), ['https://b.example/sub', 'https://c.example/sub']);
      expect(p.subsAlreadyHere, 1);
      expect(p.summary, '2 项设置更新，新增 2 个订阅');
      expect(p.changes.keys, containsAll(['sub:https://b.example/sub', 'muse_accent']));
      expect(p.changes.containsKey('unknown_key'), isFalse);
    });

    test('覆盖: settings missing from the backup are reset; subscriptions are never removed', () {
      final p = museRestorePlan(current: current, backup: backup, settingKeys: _keys, strategy: MuseRestoreStrategy.overwrite);
      expect(p.settings['muse_dns_preset'], isNull);
      expect(p.settings.containsKey('muse_dns_preset'), isTrue);
      expect(p.settingsReset, 1);
      expect(p.summary, contains('1 项恢复默认'));
      // the subscription only on this device is not in the plan at all
      expect(p.changes.keys.where((k) => k.startsWith('sub:')), isNot(contains('sub:https://keep.example/sub')));
      expect(p.changes.entries.where((e) => e.key.startsWith('sub:')).every((e) => e.value != null), isTrue);
    });

    test('恢复范围 仅订阅 / 仅设置', () {
      final subs = museRestorePlan(current: current, backup: backup, settingKeys: _keys, scope: MuseRestoreScope.subscriptions, strategy: MuseRestoreStrategy.overwrite);
      expect(subs.settings, isEmpty);
      expect(subs.subsToAdd, hasLength(2));
      final settings = museRestorePlan(current: current, backup: backup, settingKeys: _keys, scope: MuseRestoreScope.settings);
      expect(settings.subsToAdd, isEmpty);
      expect(settings.subsAlreadyHere, 0);
      expect(settings.settings, hasLength(2));
    });

    test('identical backup → nothing to do; a redacted backup under 覆盖 never touches subscriptions', () {
      final same = museRestorePlan(current: current, backup: current, settingKeys: _keys);
      expect(same.isEmpty, isTrue);
      expect(same.summary, '与当前一致，无需恢复');
      final redacted = museRestorePlan(current: current, backup: {'muse_accent': 'blue'}, settingKeys: _keys, strategy: MuseRestoreStrategy.overwrite);
      expect(redacted.subsToAdd, isEmpty);
      expect(redacted.changes.keys.any((k) => k.startsWith('sub:')), isFalse);
    });

    test('preview titles fall back to the host', () {
      expect(museRestoreSubTitle((url: 'https://c.example/sub', name: '')), 'c.example');
      expect(museRestoreSubTitle((url: 'https://c.example/sub', name: '机场 C')), '机场 C');
    });

    test('the sync service restores through the plan (auto backup first, subscriptions only added)', () {
      final src = File('lib/features/muse/data/sync_service.dart').readAsStringSync();
      expect(src, contains('Future<MuseRestorePlan> planRestore('));
      final apply = src.substring(src.indexOf('Future<MuseSyncResult> applyRestore('));
      expect(apply.indexOf("autoBackup('restore')"), lessThan(apply.indexOf('apply(plan.changes)')));
      expect(src, contains('if (v == null || have.contains(url)) continue;'));
    });
  });

  group('C10 恢复预览 dialog', () {
    Future<void> openPreview(WidgetTester tester, List<(MuseRestoreScope, MuseRestoreStrategy)> calls, ValueSetter<MuseRestorePlan?> out) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () async => out(
                  await showMuseRestorePreview(context, (scope, strategy) async {
                    calls.add((scope, strategy));
                    return museRestorePlan(
                      current: const {'muse_accent': 'blue', 'muse_dns_preset': 'cf'},
                      backup: const {'muse_accent': 'green', 'sub:https://b.example/s': '机场 B'},
                      settingKeys: _keys,
                      scope: scope,
                      strategy: strategy,
                    );
                  }, source: '自动备份 · 恢复前 · 10-27 09:00'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the summary, re-plans on 仅订阅, restores the chosen plan', (tester) async {
      final calls = <(MuseRestoreScope, MuseRestoreStrategy)>[];
      MuseRestorePlan? result;
      await openPreview(tester, calls, (p) => result = p);
      expect(find.text('1 项设置更新，新增 1 个订阅'), findsOneWidget);
      expect(find.text('＋ 机场 B'), findsOneWidget);
      expect(find.textContaining('订阅只增不删'), findsOneWidget);
      expect(find.text('自动备份 · 恢复前 · 10-27 09:00'), findsOneWidget);
      await tester.tap(find.text('仅订阅'));
      await tester.pumpAndSettle();
      expect(calls.last, (MuseRestoreScope.subscriptions, MuseRestoreStrategy.merge));
      expect(find.text('新增 1 个订阅'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restore_ok')));
      await tester.pumpAndSettle();
      expect(result?.scope, MuseRestoreScope.subscriptions);
      expect(result?.settings, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('覆盖 asks again; cancelling the second question restores nothing', (tester) async {
      final calls = <(MuseRestoreScope, MuseRestoreStrategy)>[];
      var result = const MuseRestorePlan(scope: MuseRestoreScope.all, strategy: MuseRestoreStrategy.merge) as MuseRestorePlan?;
      await openPreview(tester, calls, (p) => result = p);
      await tester.tap(find.text('覆盖'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 项恢复默认'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restore_ok')));
      await tester.pumpAndSettle();
      expect(find.text('覆盖恢复'), findsOneWidget);
      expect(find.textContaining('订阅不会被删除'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restore_overwrite_cancel')));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('nothing to restore → 恢复 disabled', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open'),
            onPressed: () => showMuseRestorePreview(
              context,
              (s, t) async => museRestorePlan(current: const {'muse_accent': 'blue'}, backup: const {'muse_accent': 'blue'}, settingKeys: _keys, scope: s, strategy: t),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.text('与当前一致，无需恢复'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('restore_ok'))).onPressed, isNull);
    });

    testWidgets('同步与备份: 从备份恢复 says it previews first', (tester) async {
      await _pump(tester, const MuseSyncPage());
      expect(find.text('先预览，可选 仅订阅 / 仅设置、合并 / 覆盖'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('C10 资源', () {
    test('rule-set names, kinds and the bundled core release', () {
      expect(museRuleSetTitle('geosite-cn'), '国内网站');
      expect(museRuleSetTitle('geoip-cn'), '国内 IP');
      expect(museRuleSetTitle('geosite-openai'), 'openai');
      expect(museRuleSetKind('geoip-malware'), 'IP');
      expect(museRuleSetKind('geosite-cn'), '域名');
      final props = File('dependencies.properties').readAsStringSync();
      expect(RegExp(r'muse\.core\.version=(\S+)').firstMatch(props)?.group(1), museCoreRelease, reason: 'keep resources.dart in step with dependencies.properties');
    });

    test('engine version parsing and the 内核版本 label', () {
      expect(museEngineVersion('engine 1.12.3'), '1.12.3');
      expect(museEngineVersion('1.11.0-beta.2 something'), '1.11.0-beta.2');
      expect(museEngineVersion('none'), isNull);
      expect(museEngineVersion(null), isNull);
      expect(museCoreVersionLabel(), museCoreRelease);
      expect(museCoreVersionLabel(engine: '1.12.3'), '$museCoreRelease · 引擎 1.12.3');
      expect(museRemoteRuleSetSource('https://r.example/lists/ads.srs'), 'r.example · ads.srs');
      expect(museRemoteRuleSetSource('https://r.example'), 'r.example');
    });

    test('reads the files on this device; missing ones marked', () {
      final dir = Directory.systemTemp.createTempSync('c10-rs');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/rule-sets').createSync();
      File('${dir.path}/rule-sets/geosite-cn.srs').writeAsBytesSync(List.filled(2048, 1));
      final files = museReadRuleSetFiles(dir.path, ['geosite-cn', 'geoip-cn']);
      expect(files.first.present, isTrue);
      expect(files.first.size, 2048);
      expect(files.first.modified, isNotNull);
      expect(files.last.present, isFalse);
      expect(museRuleSetTotal(files), 2048);
      expect(museReadRuleSetFiles('/nonexistent-c10', ['geosite-cn']).single.present, isFalse);
    });

    testWidgets('page: built-in list, remote sets, 管理 opens 远程规则集, placeholders', (tester) async {
      final dir = Directory.systemTemp.createTempSync('c10-page');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/rule-sets').createSync();
      File('${dir.path}/rule-sets/geosite-cn.srs').writeAsBytesSync(List.filled(4096, 1));
      await _pump(
        tester,
        MuseResourcesPage(baseDir: dir.path),
        prefs: {'muse_remote_rule_sets': '[{"url":"https://r.example/lists/ads.srs","outbound":"block"}]'},
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text('资源'), findsOneWidget);
      expect(find.textContaining('1 / ${museBundledRuleSets.length} 个'), findsOneWidget);
      expect(find.byKey(const ValueKey('res_builtin_geosite-cn')), findsOneWidget);
      expect(find.textContaining('本机缺少'), findsWidgets);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('res_remote_0')), 300);
      expect(find.text('ads.srs'), findsOneWidget);
      expect(find.textContaining('r.example · ads.srs'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('res_script_placeholder')), 300);
      expect(find.text('Geo 数据库'), findsOneWidget);
      expect(find.text('数据库与脚本 · 双内核版本提供'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('res_remote_manage')), -300);
      await tester.tap(find.byKey(const ValueKey('res_remote_manage')));
      await tester.pumpAndSettle();
      expect(find.text('远程规则集'), findsWidgets);
      expect(find.byKey(const ValueKey('remote_set_0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('page at 320 px and 2× text does not overflow', (tester) async {
      await _pump(tester, MuseResourcesPage(baseDir: Directory.systemTemp.path), size: const Size(320, 640), textScale: 2);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('C10 关于', () {
    testWidgets('版本与构建号, 内核版本, GPL credits', (tester) async {
      await _pump(tester, const AboutPage(), engine: '1.12.3');
      await tester.pump();
      expect(find.text('1.6.0（构建 160）'), findsOneWidget);
      expect(find.text('$museCoreRelease · 引擎 1.12.3'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('about_credit_base')), 300);
      expect(find.text('界面设计参考 FlClash'), findsOneWidget);
      expect(find.text('chen08209 · GPL-3.0'), findsOneWidget);
      expect(find.text('基于 Hiddify 开发'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 px and 2× text: nothing overflows', (tester) async {
      await _pump(tester, const AboutPage(), engine: '1.12.3-beta.1', size: const Size(320, 640), textScale: 2);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('disconnected: only the bundled release', (tester) async {
      await _pump(tester, const AboutPage());
      await tester.pump();
      expect(find.text(museCoreRelease), findsOneWidget);
    });

    testWidgets('tapping the version 7 times turns 开发者选项 on', (tester) async {
      final c = await _pump(tester, const AboutPage());
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const ValueKey('about_version')));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.read(MusePrefs.devMode), isFalse);
      await tester.tap(find.byKey(const ValueKey('about_version')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.read(MusePrefs.devMode), isTrue);
      await tester.pump(const Duration(seconds: 5));
    });

    test('tap counter: 7 in a row, a pause starts over', () {
      final t = MuseDevTaps();
      final t0 = DateTime(2026, 10, 27, 12);
      for (var i = 1; i < museDevTapsNeeded; i++) {
        expect(t.tap(t0.add(Duration(milliseconds: 300 * i))), museDevTapsNeeded - i);
      }
      expect(t.tap(t0.add(const Duration(seconds: 5))), museDevTapsNeeded - 1, reason: 'a pause over 2 s starts over');
      final u = MuseDevTaps();
      var left = -1;
      for (var i = 0; i < museDevTapsNeeded; i++) {
        left = u.tap(t0.add(Duration(milliseconds: 200 * i)));
      }
      expect(left, 0);
      expect(u.tap(t0.add(const Duration(seconds: 2))), museDevTapsNeeded - 1, reason: 'counts again from scratch');
    });

    test('the GPL credits name the upstream projects only on 关于', () {
      for (final p in [
        'lib/features/muse/logic/restore_plan.dart',
        'lib/features/muse/logic/resources.dart',
        'lib/features/muse/settings/resources_page.dart',
        'lib/features/muse/settings/restore_preview.dart',
        'lib/features/muse/settings/theme_preview_page.dart',
      ]) {
        final s = File(p).readAsLinesSync().where((l) => !l.startsWith('import ')).join('\n').toLowerCase();
        for (final w in ['flclash', 'clash', 'hiddify', 'sing-box']) {
          expect(s.contains(w), isFalse, reason: '$p: $w');
        }
      }
      final about = File('lib/features/about/widget/about_page.dart').readAsStringSync();
      expect(about, contains("'界面设计参考 FlClash'"));
    });
  });

  group('C10 开发者选项', () {
    testWidgets('设置: hidden by default, shown after it was turned on', (tester) async {
      await _pump(tester, const SettingsPage());
      await tester.scrollUntilVisible(find.byKey(const ValueKey('advanced_toggle')), 300);
      expect(find.byKey(const ValueKey('settings_developer')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('advanced_toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings_developer')), findsNothing, reason: 'no longer under 高级');
      expect(find.byKey(const ValueKey('settings_resources')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, const SettingsPage(), prefs: {'muse_dev_mode': true});
      await tester.scrollUntilVisible(find.byKey(const ValueKey('settings_developer')), 300);
      expect(find.byKey(const ValueKey('settings_developer')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('search: developer entries only once it is on; new entries found', () {
      expect(museSearchSettings('调试日志', android: true, windows: false), isEmpty);
      expect(museSearchSettings('测速并发', android: true, windows: false), isEmpty);
      expect(museSearchSettings('调试日志', android: true, windows: false, developer: true).single.page, MuseSettingPage.developer);
      expect(museSearchSettings('清除缓存', android: false, windows: true, developer: true), isNotEmpty);
      expect(museSearchSettings('资源', android: true, windows: false).first.page, MuseSettingPage.resources);
      expect(museSearchSettings('geosite', android: true, windows: false).first.title, '资源');
      expect(museSearchSettings('主题预览', android: true, windows: false).single.page, MuseSettingPage.themePreview);
      expect(museSearchSettings('内核版本', android: true, windows: true).single.page, MuseSettingPage.about);
      expect(museSearchSettings('仅订阅', android: true, windows: true).single.page, MuseSettingPage.sync);
    });

    testWidgets('page: 调试日志, 清除缓存, 消息样式, 崩溃记录测试, 重置引导, 隐藏', (tester) async {
      final c = await _pump(
        tester,
        const MuseDeveloperPage(),
        prefs: {'muse_dev_mode': true, 'keep_alive_guide_shown': true, 'muse_changelog_seen': '1.6.0'},
      );
      for (final k in ['node_test_workers', 'dev_debug_log', 'dev_clear_cache', 'dev_toast_test', 'dev_crash_test']) {
        await tester.scrollUntilVisible(find.byKey(ValueKey(k)), 200);
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await tester.scrollUntilVisible(find.byKey(const ValueKey('dev_debug_log')), -200);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('dev_debug_log')), matching: find.byType(Switch)));
      await tester.pump();
      expect(c.read(MusePrefs.devMode), isTrue);
      expect((await SharedPreferences.getInstance()).getString('log-level'), 'debug');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('dev_reset_guides')), 200);
      await tester.tap(find.byKey(const ValueKey('dev_reset_guides')));
      await tester.pump();
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('keep_alive_guide_shown'), isFalse);
      expect(sp.getString('muse_changelog_seen'), '');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('dev_turn_off')), 200);
      await tester.tap(find.byKey(const ValueKey('dev_turn_off')));
      await tester.pump();
      expect(c.read(MusePrefs.devMode), isFalse);
      expect(tester.takeException(), isNull);
    });

    test('清除缓存 only removes what the app put there (Windows %TEMP% is shared)', () async {
      final dir = Directory.systemTemp.createTempSync('c10-tmp');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/chuanyun-diagnostics-1.txt').writeAsBytesSync(List.filled(100, 1));
      Directory('${dir.path}/chuanyun-update').createSync();
      File('${dir.path}/chuanyun-update/setup.exe').writeAsBytesSync(List.filled(50, 1));
      Directory('${dir.path}/updates').createSync();
      File('${dir.path}/updates/a.apk').writeAsBytesSync(List.filled(30, 1));
      File('${dir.path}/someone-else.tmp').writeAsBytesSync(List.filled(10, 1));
      expect(await museClearTempFiles(dir: dir, android: false), 150);
      expect(File('${dir.path}/someone-else.tmp').existsSync(), isTrue);
      expect(Directory('${dir.path}/updates').existsSync(), isTrue, reason: 'not ours on Windows');
      expect(await museClearTempFiles(dir: dir, android: true), 30);
      expect(File('${dir.path}/someone-else.tmp').existsSync(), isTrue);
      expect(museIsOwnTempEntry('updates', android: false), isFalse);
      expect(await museClearTempFiles(dir: Directory('/nonexistent-c10')), 0);
    });

    test('开发者选项 switch is per device (not synced or backed up)', () {
      expect(museSyncedPrefs.containsKey('muse_dev_mode'), isFalse);
      expect(museSyncedPrefKeys.contains('muse_dev_mode'), isFalse);
    });
  });

  group('C10 主题预览', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      testWidgets('renders every sample (${b.name}), 320 px 2× without overflow', (tester) async {
        await _pump(
          tester,
          Theme(data: ThemeData(brightness: b), child: const MuseThemePreviewPage()),
          size: const Size(320, 640),
          textScale: 2,
        );
        expect(find.byKey(const ValueKey('preview_home_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('preview_nodes')), findsOneWidget);
        await tester.scrollUntilVisible(find.byKey(const ValueKey('preview_dialog')), 300);
        expect(find.text('弹窗标题'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('外观 has the 主题预览 entry', (tester) async {
      await _pump(tester, const MuseAppearancePage());
      await tester.scrollUntilVisible(find.byKey(const ValueKey('appearance_preview')), 300);
      await tester.tap(find.byKey(const ValueKey('appearance_preview')));
      await tester.pumpAndSettle();
      expect(find.text('主题预览'), findsWidgets);
      expect(find.byKey(const ValueKey('preview_home_card')), findsOneWidget);
    });
  });
}
