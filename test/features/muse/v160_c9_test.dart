// 穿云 1.6.0 C9 Android: 分应用代理 (sort, 只看联网应用, 全选 / 反选, clipboard import / export with
// invalid names counted), 自动运行 (once per launch), 按需运行 on Android (Wi‑Fi name over the
// platform channel, permission refused → explanation, no crash), automation intents
// START / STOP / TOGGLE, 通知栏断开按钮, settings search, minimal new permissions.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app_based_routing/data/app_proxy_data_source.dart';
import 'package:hiddify/features/app_based_routing/data/selected_data_provider.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';
import 'package:hiddify/features/app_based_routing/overview/app_list_page.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/home/auto_run.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/per_app_tools.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/android_settings.dart';
import 'package:hiddify/features/muse/settings/windows_extras.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(Map<String, Object> prefs, {List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp), ...overrides]);
  await c.read(sharedPreferencesProvider.future);
  return c;
}

Future<ProviderContainer> _pump(
  WidgetTester t,
  Widget home, {
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
  bool translations = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp), ...overrides]);
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  if (translations) await t.runAsync(() => c.read(translationsProvider.future));
  t.view.physicalSize = const Size(400, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)),
        home: home,
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return c;
}

const _apps = [
  MuseAppRow(packageName: 'com.tencent.mm', name: '微信', installed: 300),
  MuseAppRow(packageName: 'com.android.settings', name: 'Settings', installed: 100, system: true),
  MuseAppRow(packageName: 'org.example.offline', name: 'Abacus', installed: 500),
  MuseAppRow(packageName: 'com.google.android.youtube', name: 'YouTube', installed: 200),
];

final _user = PkgFlag.userSelection.add(0);
final _auto = PkgFlag.autoSelection.add(0);
final _autoRemoved = PkgFlag.forceDeselection.add(PkgFlag.autoSelection.add(0));

List<String> _pkgs(List<MuseAppRow> l) => [for (final a in l) a.packageName];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('分应用代理 list tools', () {
    test('sort: 已选优先 (yours, auto, removed, rest; then by name) / 名称 / 安装时间 newest first', () {
      final flags = {'com.google.android.youtube': _auto, 'org.example.offline': _user, 'com.tencent.mm': _autoRemoved};
      expect(_pkgs(museAppView(_apps, flags: flags)), [
        'org.example.offline',
        'com.google.android.youtube',
        'com.tencent.mm',
        'com.android.settings',
      ]);
      expect(_pkgs(museAppView(_apps, flags: flags, sort: MuseAppSort.name)), [
        'org.example.offline',
        'com.android.settings',
        'com.google.android.youtube',
        'com.tencent.mm',
      ]);
      expect(_pkgs(museAppView(_apps, flags: flags, sort: MuseAppSort.installed)), [
        'org.example.offline',
        'com.tencent.mm',
        'com.google.android.youtube',
        'com.android.settings',
      ]);
      expect(MuseAppSort.fromKey('installed'), MuseAppSort.installed);
      expect(MuseAppSort.fromKey('???'), MuseAppSort.selected);
    });

    test('filters: system apps, 只看联网应用 (unknown list shows all), search by name or package', () {
      expect(museAppView(_apps, flags: const {}, hideSystem: true).length, 3);
      final net = {'com.tencent.mm', 'com.google.android.youtube', 'com.android.settings'};
      expect(_pkgs(museAppView(_apps, flags: const {}, internetOnly: true, internet: net, sort: MuseAppSort.name)), [
        'com.android.settings',
        'com.google.android.youtube',
        'com.tencent.mm',
      ]);
      expect(museAppView(_apps, flags: const {}, internetOnly: true).length, 4);
      expect(_pkgs(museAppView(_apps, flags: const {}, query: 'YOUTU')), ['com.google.android.youtube']);
      expect(_pkgs(museAppView(_apps, flags: const {}, query: 'tencent')), ['com.tencent.mm']);
      expect(
        museAppView(
          _apps,
          flags: const {},
          query: '微信',
          hideSystem: true,
          internetOnly: true,
          internet: net,
        ).single.name,
        '微信',
      );
    });

    test('全选 picks the shown apps not chosen yet; 反选 flips each shown app', () {
      final shown = museAppView(_apps, flags: const {}, hideSystem: true);
      final flags = {'com.tencent.mm': _user, 'com.google.android.youtube': _autoRemoved};
      expect(museSelectAllTargets(shown, flags)..sort(), ['com.google.android.youtube', 'org.example.offline']);
      final inv = museInvertTargets(shown, flags);
      expect(inv.deselect, ['com.tencent.mm']);
      expect(inv.select..sort(), ['com.google.android.youtube', 'org.example.offline']);
      // the hidden system app is left alone
      expect([...inv.select, ...inv.deselect], isNot(contains('com.android.settings')));
    });

    test('clipboard: one package per line, invalid names counted, duplicates dropped; export sorted', () {
      final r = museParsePackageList(
        'com.tencent.mm\r\n  com.tencent.mm\n微信\nhttp://x.com\n\ncom.a.b, org.c_d.e1；bad name\n1com.x.y\nsingle',
      );
      expect(r.packages, ['com.tencent.mm', 'com.a.b', 'org.c_d.e1']);
      // 微信, http://x.com, bad, name, 1com.x.y, single
      expect(r.skipped, 6);
      expect(museParsePackageList('').packages, isEmpty);
      expect(museIsPackageName('a.b'), isTrue);
      expect(museIsPackageName('a'), isFalse);
      expect(museIsPackageName('a..b'), isFalse);
      expect(museExportPackageList({'z.app': _user, 'a.app': _auto, 'm.app': _autoRemoved}), 'a.app\nz.app');
      expect(museImportSummary(added: 3, already: 1, skipped: 2), '已导入 3 个，1 个已在列表，忽略 2 个无效包名');
      expect(museImportSummary(added: 2, already: 0, skipped: 0), '已导入 2 个');
    });

    test('database: setSelected chooses / un-chooses without touching other apps', () async {
      final db = Db(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = AppProxyDao(db);
      const mode = AppProxyMode.exclude;
      await dao.applyAutoSelection(autoList: {'auto.one', 'auto.two'}, mode: mode);
      await dao.updatePkg(pkg: 'mine.one', mode: mode);
      await dao.updatePkg(pkg: 'other.mode', mode: AppProxyMode.include);
      Future<Map<String, int>> flags() async => {
        for (final e in await dao.watchAll(mode: mode).first) e.pkgName: e.flags,
      };

      await dao.setSelected(pkgs: ['mine.one', 'auto.one', 'new.one'], selected: false, mode: mode);
      var f = await flags();
      expect(f.containsKey('mine.one'), isFalse, reason: 'your own pick is deleted');
      expect(PkgFlag.forceDeselection.check(f['auto.one']!), isTrue, reason: 'automatic pick stays out');
      expect(f.containsKey('new.one'), isFalse);
      expect(museAppActive(f['auto.two']), isTrue);

      await dao.setSelected(pkgs: ['auto.one', 'new.one', 'auto.two'], selected: true, mode: mode);
      f = await flags();
      expect(PkgFlag.checkboxValue(f['auto.one']!), isTrue);
      expect(PkgFlag.checkboxValue(f['new.one']!), isTrue);
      expect(PkgFlag.checkboxValue(f['auto.two']!), isTrue);
      expect(PkgFlag.autoSelection.check(f['auto.one']!), isTrue, reason: 'still known as automatic');
      final other = await dao.watchAll(mode: AppProxyMode.include).first;
      expect(other.single.pkgName, 'other.mode');
      await dao.setSelected(pkgs: const [], selected: true, mode: mode);
    });
  });

  group('分应用代理 page', () {
    testWidgets('sort menu, 只看联网应用, 全选 / 反选, clipboard import (invalid counted) and export', (t) async {
      final db = Db(NativeDatabase.memory());
      final dao = AppProxyDao(db);
      final messenger = t.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('installed_apps'), (call) async {
        return [
          for (final a in _apps) {'name': a.name, 'package_name': a.packageName, 'installed_timestamp': a.installed},
        ];
      });
      String? clip;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
        if (call.method == 'Clipboard.getData')
          return {'text': 'com.tencent.mm\norg.example.offline\nnot a package\nfoo'};
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(const MethodChannel('installed_apps'), null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      final c = await _pump(
        t,
        const AppListPage(),
        prefs: {'per_app_proxy_enabled': true, 'per_app_proxy_mode': 'exclude'},
        translations: true,
        overrides: [
          appProxyDataSourceProvider.overrideWithValue(dao),
          museInstalledAppsProvider.overrideWith((ref) async => _apps),
          museInternetAppsProvider.overrideWith((ref) async => {'com.tencent.mm', 'com.google.android.youtube'}),
        ],
      );
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      await settle();
      expect(find.byKey(const ValueKey('app_com.android.settings')), findsOneWidget);
      Future<void> menu(String label) async {
        await t.tap(find.byKey(const ValueKey('app_list_menu')));
        await t.pumpAndSettle();
        await t.tap(find.text(label));
        await settle();
      }

      double y(String pkg) => t.getTopLeft(find.byKey(ValueKey('app_$pkg'))).dy;

      await menu('排序：名称');
      expect(c.read(MusePrefs.appSort), 'name');
      expect(y('org.example.offline'), lessThan(y('com.tencent.mm')));
      await menu('排序：安装时间');
      expect(y('org.example.offline'), lessThan(y('com.google.android.youtube')));

      await t.tap(find.byKey(const ValueKey('app_list_internet_only')));
      await settle();
      expect(c.read(MusePrefs.appInternetOnly), isTrue);
      expect(find.byKey(const ValueKey('app_org.example.offline')), findsNothing);
      expect(find.byKey(const ValueKey('app_com.android.settings')), findsNothing);

      // 全选 only acts on the two shown apps
      await menu('全选');
      var flags = {
        for (final e in await t.runAsync(() => dao.watchAll(mode: AppProxyMode.exclude).first) ?? [])
          e.pkgName: e.flags,
      };
      expect(flags.keys.toSet(), {'com.tencent.mm', 'com.google.android.youtube'});

      await t.tap(find.byKey(const ValueKey('app_list_internet_only')));
      await settle();
      await menu('反选');
      flags = {
        for (final e in await t.runAsync(() => dao.watchAll(mode: AppProxyMode.exclude).first) ?? [])
          e.pkgName: e.flags,
      };
      expect(flags.keys.toSet(), {'org.example.offline', 'com.android.settings'});

      await menu('从剪贴板导入');
      flags = {
        for (final e in await t.runAsync(() => dao.watchAll(mode: AppProxyMode.exclude).first) ?? [])
          e.pkgName: e.flags,
      };
      expect(flags.keys.toSet(), {'org.example.offline', 'com.android.settings', 'com.tencent.mm'});

      await menu('复制到剪贴板');
      expect(clip, 'com.android.settings\ncom.tencent.mm\norg.example.offline');
      await t.pumpWidget(const SizedBox());
      await t.runAsync(db.close);
    });
  });

  group('自动运行', () {
    test('decision', () {
      expect(museShouldAutoRun(isAndroid: true, on: true, alreadyRan: false, hasActiveProfile: true), isTrue);
      expect(museShouldAutoRun(isAndroid: false, on: true, alreadyRan: false, hasActiveProfile: true), isFalse);
      expect(museShouldAutoRun(isAndroid: true, on: false, alreadyRan: false, hasActiveProfile: true), isFalse);
      expect(museShouldAutoRun(isAndroid: true, on: true, alreadyRan: true, hasActiveProfile: true), isFalse);
      expect(museShouldAutoRun(isAndroid: true, on: true, alreadyRan: false, hasActiveProfile: false), isFalse);
      expect(
        museShouldAutoRun(
          isAndroid: true,
          on: true,
          alreadyRan: false,
          hasActiveProfile: true,
          launchedForControl: true,
        ),
        isFalse,
      );
    });

    test('connects once per launch only; turning it on later waits for the next launch', () async {
      var connects = 0;
      Future<ProviderContainer> launch(bool on) => _container(
        {'muse_auto_run': on},
        overrides: [
          museAutoRunForceProvider.overrideWithValue(true),
          museActiveProfileIdProvider.overrideWithValue('p1'),
          museAutoRunActionProvider.overrideWithValue(() async => connects++),
        ],
      );

      museAutoRunResetForTest();
      var c = await launch(true);
      c.listen(museAutoRunProvider, (_, _) {});
      expect(connects, 0, reason: 'not before the first frame');
      await Future<void>.delayed(museAutoRunDelay + const Duration(milliseconds: 200));
      expect(connects, 1);
      // the app UI is rebuilt in the same launch (activity re-created): no second connect
      c.dispose();
      c = await launch(true);
      c.listen(museAutoRunProvider, (_, _) {});
      await Future<void>.delayed(museAutoRunDelay + const Duration(milliseconds: 200));
      expect(connects, 1);
      c.dispose();

      // a launch with the switch off, switched on afterwards: nothing until the next launch
      museAutoRunResetForTest();
      c = await launch(false);
      c.listen(museAutoRunProvider, (_, _) {});
      await c.read(MusePrefs.autoRun.notifier).update(true);
      await Future<void>.delayed(museAutoRunDelay + const Duration(milliseconds: 200));
      expect(connects, 1);
      c.dispose();
      museAutoRunResetForTest();
    });

    test('no subscription: nothing to connect', () async {
      var connects = 0;
      museAutoRunResetForTest();
      final c = await _container(
        {'muse_auto_run': true},
        overrides: [
          museAutoRunForceProvider.overrideWithValue(true),
          museActiveProfileIdProvider.overrideWithValue(null),
          museAutoRunActionProvider.overrideWithValue(() async => connects++),
        ],
      );
      c.listen(museAutoRunProvider, (_, _) {});
      await Future<void>.delayed(museAutoRunDelay + const Duration(seconds: 4));
      expect(connects, 0);
      c.dispose();
      museAutoRunResetForTest();
    });
  });

  group('按需运行 (Android)', () {
    test('Wi‑Fi answers of the platform channel', () {
      expect(museParseAndroidWifi({'ok': true, 'ssid': 'Home'}).ssid, 'Home');
      final none = museParseAndroidWifi({'ok': true, 'ssid': null});
      expect(none.ok, isTrue);
      expect(none.ssid, isNull);
      expect(museParseAndroidWifi({'ok': false, 'reason': 'permission'}).hint, museWifiPermissionHint);
      expect(museParseAndroidWifi({'ok': false, 'reason': 'location_off'}).hint, museWifiLocationOffHint);
      expect(museParseAndroidWifi({'ok': false, 'reason': 'unknown'}).ok, isFalse);
      expect(museParseAndroidWifi(null).ok, isFalse);
      for (final h in [museWifiPermissionHint, museWifiLocationOffHint, museWifiUnknownHint]) {
        expect(h, isNot(contains('null')));
      }
    });

    test('an unreadable name (background, no permission) never counts as leaving the Wi‑Fi', () {
      final m = MuseOnDemand()..paused(3);
      expect(
        m.tick(ssids: ['Home'], read: const MuseSsidRead.failed(museWifiUnknownHint), running: false, generation: 3),
        MuseOnDemandStep.none,
      );
      expect(m.pausedByUs, isTrue);
      expect(
        m.tick(ssids: ['Home'], read: const MuseSsidRead.ok('Cafe'), running: false, generation: 3),
        MuseOnDemandStep.resume,
      );
      // the user's own 连接 / 断开 still wins (shared C8 logic)
      final u = MuseOnDemand()..paused(3);
      expect(
        u.tick(ssids: ['Home'], read: const MuseSsidRead.ok(null), running: false, generation: 4),
        MuseOnDemandStep.none,
      );
    });

    testWidgets('permission refused: explanation, switch stays off, no crash; 不再询问 offers the settings page', (
      t,
    ) async {
      var answer = 'denied';
      var asked = 0;
      final c = await _pump(
        t,
        const MuseOnDemandPage(),
        overrides: [
          museOnDemandAndroidProvider.overrideWithValue(true),
          museWifiPermissionRequestProvider.overrideWithValue(() async {
            asked++;
            return answer;
          }),
          museSsidReaderProvider.overrideWithValue(() async => const MuseSsidRead.ok('Home')),
        ],
      );
      await t.tap(find.byKey(const ValueKey('on_demand_switch')));
      await t.pumpAndSettle();
      expect(asked, 1);
      expect(c.read(MusePrefs.onDemand), isFalse);
      expect(find.byKey(const ValueKey('on_demand_hint')), findsOneWidget);
      expect(find.text(museWifiPermissionHint), findsOneWidget);
      expect(find.byKey(const ValueKey('on_demand_open_permission')), findsNothing);
      expect(t.takeException(), isNull);

      answer = 'blocked';
      await t.tap(find.byKey(const ValueKey('on_demand_add_current')));
      await t.pumpAndSettle();
      expect(museOnDemandSsids(c.read(MusePrefs.wifiRules)), isEmpty);
      expect(find.byKey(const ValueKey('on_demand_open_permission')), findsOneWidget);

      answer = 'granted';
      await t.tap(find.byKey(const ValueKey('on_demand_add_current')));
      await t.pumpAndSettle();
      expect(museOnDemandSsids(c.read(MusePrefs.wifiRules)), ['Home']);
      expect(find.byKey(const ValueKey('on_demand_hint')), findsNothing);
      await t.tap(find.byKey(const ValueKey('on_demand_switch')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.onDemand), isTrue);
    });

    testWidgets('Windows page is unchanged: no permission asked', (t) async {
      var asked = 0;
      final c = await _pump(
        t,
        const MuseOnDemandPage(),
        overrides: [
          museOnDemandAndroidProvider.overrideWithValue(false),
          museWifiPermissionRequestProvider.overrideWithValue(() async {
            asked++;
            return 'denied';
          }),
        ],
      );
      await t.tap(find.byKey(const ValueKey('on_demand_switch')));
      await t.pumpAndSettle();
      expect(asked, 0);
      expect(c.read(MusePrefs.onDemand), isTrue);
    });
  });

  group('设置 › 通用 (Android)', () {
    testWidgets('自动运行 and 通知栏断开按钮 switches; 按需运行 row', (t) async {
      final c = await _pump(t, const Scaffold(body: SingleChildScrollView(child: MuseAndroidGeneralSection())));
      expect(c.read(MusePrefs.autoRun), isFalse);
      expect(c.read(MusePrefs.notifyStopButton), isTrue);
      await t.tap(find.byKey(const ValueKey('settings_auto_run')));
      await t.tap(find.byKey(const ValueKey('settings_notify_stop')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.autoRun), isTrue);
      expect(c.read(MusePrefs.notifyStopButton), isFalse);
      expect(find.byKey(const ValueKey('settings_on_demand')), findsOneWidget);
      expect(find.text('关'), findsOneWidget);
    });

    test('search entries', () {
      for (final title in ['自动运行', '通知栏断开按钮']) {
        expect(museSettingEntries.where((x) => x.title == title).single.androidOnly, isTrue, reason: title);
      }
      final onDemand = museSettingEntries.where((x) => x.title == '按需运行').single;
      expect(onDemand.androidOnly || onDemand.windowsOnly, isFalse);
    });
  });

  group('Android side', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    const kt = 'android/app/src/main/kotlin/com/hiddify/hiddify';

    String permLine(String p) => manifest.split('\n').firstWhere((l) => l.contains('permission.$p"'), orElse: () => '');

    test('automation activity: exported, three actions + DEFAULT, no screen, not in recents', () {
      final i = manifest.indexOf('android:name=".QuickActionActivity"');
      expect(i, greaterThan(0));
      final block = manifest.substring(i, manifest.indexOf('</activity>', i));
      for (final a in ['START', 'STOP', 'TOGGLE']) {
        expect(block, contains('<action android:name="com.chuanyun.app.action.$a" />'));
      }
      expect(block, contains('android.intent.category.DEFAULT'));
      expect(block, contains('android:exported="true"'));
      expect(block, contains('android:excludeFromRecents="true"'));
      expect(block, contains('Theme.Translucent.NoTitleBar'));
    });

    test('START / STOP / TOGGLE go through the tile\'s start / stop; VPN permission → the app\'s connect link', () {
      final src = File('$kt/QuickActionActivity.kt').readAsStringSync();
      expect(src, contains('ACTION_START -> if (status == Status.Stopped) QuickStep.START else QuickStep.NONE'));
      expect(src, contains('ACTION_STOP -> if (status == Status.Started) QuickStep.STOP else QuickStep.NONE'));
      expect(src, contains('Status.Stopped -> QuickStep.START'));
      expect(src, contains('Status.Started -> QuickStep.STOP'));
      expect(src, contains('BoxService.start()'));
      expect(src, contains('BoxService.stop('));
      expect(src, contains('VpnService.prepare(this) != null'));
      expect(src, contains('chuanyun://connect'));
      expect(src, contains('finish()'));
      // the VPN service is not touched by this block
      for (final f in ['BoxService.kt', 'VPNService.kt']) {
        expect(File('$kt/bg/$f').readAsStringSync(), isNot(contains('1.6.0 C9')), reason: f);
      }
    });

    test('notification 断开 button follows the setting (same key on both sides)', () {
      final notification = File('$kt/bg/ServiceNotification.kt').readAsStringSync();
      expect(notification, contains('if (Settings.notifyStopButton) addAction('));
      expect(
        File('$kt/constant/SettingsKey.kt').readAsStringSync(),
        contains(r'"${KEY_PREFIX}muse_notify_stop_button"'),
      );
      expect(File('$kt/Settings.kt').readAsStringSync(), contains('getBoolean(SettingsKey.NOTIFY_STOP_BUTTON, true)'));
    });

    test('permissions: only what 按需运行 needs; background location and nearby devices stay removed', () {
      for (final p in ['ACCESS_WIFI_STATE', 'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION']) {
        expect(permLine(p), isNotEmpty, reason: p);
        expect(permLine(p), isNot(contains('remove')), reason: p);
      }
      for (final p in ['ACCESS_BACKGROUND_LOCATION', 'NEARBY_WIFI_DEVICES']) {
        expect(permLine(p), contains('tools:node="remove"'), reason: p);
      }
      // asked at run time only from the 按需运行 page (never at start-up)
      final handler = File('$kt/ChuanyunHandler.kt').readAsStringSync();
      expect(RegExp('requestPermissions\\(').allMatches(handler).length, 1);
      expect(handler, contains('"request_wifi_permission"'));
      expect(File('$kt/MainActivity.kt').readAsStringSync(), isNot(contains('ACCESS_FINE_LOCATION')));
    });

    test('applicationId, signing and icons unchanged', () {
      final gradle = File('android/app/build.gradle').readAsStringSync();
      expect(gradle, contains('applicationId "com.chuanyun.app"'));
      expect(gradle, contains('chuanyun-release.p12'));
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    });

    test('new code and text never name the upstream projects', () {
      for (final p in [
        'lib/features/muse/logic/per_app_tools.dart',
        'lib/features/muse/home/auto_run.dart',
        'lib/features/muse/settings/android_settings.dart',
        '$kt/QuickActionActivity.kt',
      ]) {
        final s = File(p)
            .readAsLinesSync()
            .where((l) => !l.startsWith('import ') && !l.startsWith('package '))
            .join('\n')
            .toLowerCase();
        for (final w in ['flclash', 'clash', 'hiddify', 'sing-box']) {
          expect(s.contains(w), isFalse, reason: '$p mentions $w');
        }
      }
    });
  });
}
