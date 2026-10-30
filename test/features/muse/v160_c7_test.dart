// 穿云 1.6.0 C7 设置 › 外观 / 通用: presets + custom 主题色, 纯黑 under 深色, 文字缩放 (and the
// 字体大小 migration), 静默启动 on screen, settings search entries.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/muse_prefs_migration.dart';
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, Map<String, Object> initial, {Size size = const Size(412, 915), double textScale = 1}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => prefs)]);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final mode = container.read(themePreferencesProvider);
  final theme = AppTheme(mode, '');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme.lightTheme(null),
        darkTheme: theme.darkTheme(null),
        themeMode: mode.flutterThemeMode,
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
          child: const MuseAppearancePage(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  tearDown(() {
    museApplyAccent(museDefaultAccent);
    museApplyPureBlack(false);
  });

  group('C7 主题色', () {
    test('hex parsing', () {
      expect(museParseHexColor('#2f6bff'), const Color(0xFF2F6BFF));
      expect(museParseHexColor(' 2F6BFF '), const Color(0xFF2F6BFF));
      expect(museParseHexColor('#0f0'), const Color(0xFF00FF00));
      for (final bad in ['', '#12345', 'zzzzzz', '#1234567', 'blue']) {
        expect(museParseHexColor(bad), isNull, reason: bad);
      }
      expect(museHexOf(const Color(0xFF0a0b0c)), '#0A0B0C');
    });
    test('presets keep their colours; unknown falls back to 景泰蓝', () {
      expect(MuseAccent.values.length, greaterThanOrEqualTo(6));
      expect(MuseAccent.jingtailan.brand, const Color(0xFF2775B6));
      expect(museAccentColors('zhuqing').brand, MuseAccent.zhuqing.brand);
      expect(museAccentColors('nope').brand, MuseAccent.jingtailan.brand);
      expect(MuseAccent.values.map((e) => e.key).toSet().length, MuseAccent.values.length);
    });
    test('every preset and any custom colour keeps white text readable', () {
      double contrast(Color c) => 1.05 / (c.computeLuminance() + 0.05);
      for (final a in MuseAccent.values) {
        expect(contrast(a.brand), greaterThanOrEqualTo(museAccentMinContrast), reason: a.key);
      }
      for (final hex in ['#FFEB3B', '#FFFFFF', '#00FFFF', '#2F6BFF', '#000000']) {
        expect(contrast(museAccentColors(hex).brand), greaterThanOrEqualTo(museAccentMinContrast), reason: hex);
      }
      // a dark custom colour is used as is
      expect(museAccentColors('#123456').brand, const Color(0xFF123456));
    });
    test('museApplyAccent sets the palette from a preset or a custom value', () {
      museApplyAccent('dingxiang');
      expect(MusePalette.brand, MuseAccent.dingxiang.brand);
      expect(MusePalette.seed, const Color(0xFFCCA4E3));
      museApplyAccent('#123456');
      expect(MusePalette.brand, const Color(0xFF123456));
      expect(MusePalette.brandLight, isNot(MusePalette.brand));
      expect(MusePalette.brandDeep, isNot(MusePalette.brand));
    });
    test('saved custom colours: newest first, no duplicates, capped, invalid dropped', () {
      var raw = '';
      raw = museAddCustomAccent(raw, '#111111');
      raw = museAddCustomAccent(raw, '222222');
      raw = museAddCustomAccent(raw, '#111111');
      expect(museParseCustomAccents(raw), ['#111111', '#222222']);
      expect(museParseCustomAccents('#111111,junk,,#333'), ['#111111', '#333333']);
      for (var i = 0; i < 20; i++) {
        raw = museAddCustomAccent(raw, '#0000${i.toRadixString(16).padLeft(2, '0')}');
      }
      expect(museParseCustomAccents(raw).length, museMaxCustomAccents);
      expect(museRemoveCustomAccent('#111111,#222222', '#111111'), '#222222');
    });
  });

  group('C7 纯黑', () {
    test('stored as the black theme mode, dark only', () {
      expect(AppThemeMode.black.flutterThemeMode, ThemeMode.dark);
      expect(AppThemeMode.black.trueBlack, isTrue);
      expect(AppThemeMode.choices, isNot(contains(AppThemeMode.black)));
      // 1.6.1: the page colour comes from the seeded scheme; 纯黑 makes the dark page #000
      final black = AppTheme(AppThemeMode.black, '').darkTheme(null);
      final dark = AppTheme(AppThemeMode.dark, '').darkTheme(null);
      expect(black.scaffoldBackgroundColor.toARGB32(), 0xFF000000);
      expect(dark.scaffoldBackgroundColor, MuseSurface.page.color(dark.colorScheme));
      expect(dark.scaffoldBackgroundColor.toARGB32(), isNot(0xFF000000));
      final light = AppTheme(AppThemeMode.black, '').lightTheme(null);
      expect(light.scaffoldBackgroundColor, AppTheme(AppThemeMode.light, '').lightTheme(null).scaffoldBackgroundColor);
    });
    test('a saved 纯黑 stays 纯黑 (no longer turned into 深色)', () {
      final src = File('lib/core/theme/theme_preferences.dart').readAsStringSync();
      expect(src, isNot(contains('changeThemeMode(AppThemeMode.dark)')));
    });
    testWidgets('switch shows only under 深色 and toggles the mode', (tester) async {
      var c = await _pump(tester, {'theme_mode': 'light'});
      expect(find.byKey(const ValueKey('appearance_pure_black')), findsNothing);
      c = await _pump(tester, {'theme_mode': 'system'});
      expect(find.byKey(const ValueKey('appearance_pure_black')), findsNothing);
      c = await _pump(tester, {'theme_mode': 'dark'});
      expect(find.byKey(const ValueKey('appearance_pure_black')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('appearance_pure_black')), matching: find.byType(Switch)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(themePreferencesProvider), AppThemeMode.black);
      // 深浅色 still reads 深色 (the switch stays on screen)
      final t = c.read(translationsProvider).requireValue;
      expect(find.descendant(of: find.byKey(const ValueKey('appearance_theme')), matching: find.text(AppThemeMode.dark.present(t))), findsOneWidget);
      expect(find.byKey(const ValueKey('appearance_pure_black')), findsOneWidget);
      // the theme the app builds for 纯黑 paints the page true black
      expect(AppTheme(c.read(themePreferencesProvider), '').darkTheme(null).scaffoldBackgroundColor.toARGB32(), 0xFF000000);
    });
  });

  group('C7 文字缩放', () {
    test('range 0.8–1.4 in steps of 0.05; off = 1.0', () {
      expect(museTextScale(false, 140), 1.0);
      expect(museTextScale(true, 120), 1.2);
      expect(museTextScale(true, 10), 0.8);
      expect(museTextScale(true, 999), 1.4);
      expect(museClampTextScalePct(103), 105);
      expect(museTextScaleLabel(110), '1.10×');
    });
    test('migration 1→2: 字体大小 becomes 文字缩放', () {
      for (final e in {'small': 90, 'large': 110, 'huge': 120}.entries) {
        final m = <String, Object?>{'muse_text_size': e.key};
        expect(musePrefsMigrate(m), musePrefsVersionCurrent);
        expect(m['muse_text_scale_on'], isTrue);
        expect(m['muse_text_scale_pct'], e.value);
      }
      final normal = <String, Object?>{'muse_text_size': 'normal'};
      musePrefsMigrate(normal);
      expect(normal.containsKey('muse_text_scale_on'), isFalse);
      // an existing 文字缩放 is never overwritten; already at 2 = nothing runs
      final kept = <String, Object?>{'muse_text_size': 'huge', 'muse_text_scale_pct': 85};
      musePrefsMigrate(kept);
      expect(kept['muse_text_scale_pct'], 85);
      expect(kept.containsKey('muse_text_scale_on'), isFalse);
      final done = <String, Object?>{'muse_text_size': 'huge', musePrefsVersionKey: 2};
      musePrefsMigrate(done);
      expect(done.containsKey('muse_text_scale_on'), isFalse);
    });
    test('migration on the store writes bool + int', () async {
      SharedPreferences.setMockInitialValues({'muse_text_size': 'large'});
      final sp = await SharedPreferences.getInstance();
      expect(await musePrefsMigrateStore(sp), musePrefsVersionCurrent);
      expect(sp.getBool('muse_text_scale_on'), isTrue);
      expect(sp.getInt('muse_text_scale_pct'), 110);
    });
    test('synced and wired into the app', () {
      expect(museSyncedPrefs.keys, containsAll(['muse_text_scale_on', 'muse_text_scale_pct', 'muse_custom_accents', 'muse_accent']));
      expect(museSyncedPrefKeys, containsAll(['muse_text_scale_on', 'muse_text_scale_pct', 'muse_custom_accents']));
      final app = File('lib/features/app/widget/app.dart').readAsStringSync();
      expect(app, contains('museTextScale(ref.watch(MusePrefs.textScaleOn), ref.watch(MusePrefs.textScalePct))'));
      expect(app, contains('museApplyPureBlack(themeMode.trueBlack)'));
      expect(app, isNot(contains('MusePrefs.textSize')));
    });
    testWidgets('switch reveals the slider; release saves', (tester) async {
      final c = await _pump(tester, {});
      expect(find.byKey(const ValueKey('appearance_text_scale_slider')), findsNothing);
      expect(find.text('字体大小'), findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('appearance_text_scale')), matching: find.byType(Switch)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(MusePrefs.textScaleOn), isTrue);
      final slider = find.byKey(const ValueKey('appearance_text_scale_slider'));
      expect(slider, findsOneWidget);
      await tester.drag(slider, const Offset(400, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(MusePrefs.textScalePct), museTextScaleMax);
      expect(find.text('1.40×'), findsWidgets);
    });
  });

  group('C7 page', () {
    testWidgets('custom colour: add, select, remove', (tester) async {
      final c = await _pump(tester, {});
      await tester.tap(find.byKey(const ValueKey('accent_qingbi')));
      await tester.pump();
      expect(c.read(MusePrefs.accent), 'qingbi');
      await tester.tap(find.byKey(const ValueKey('accent_add_custom')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).last, '#123456');
      await tester.tap(find.text('确定').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.read(MusePrefs.accent), '#123456');
      expect(c.read(MusePrefs.customAccents), '#123456');
      expect(find.byKey(const ValueKey('accent_custom_#123456')), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('accent_custom_#123456')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(MusePrefs.customAccents), '');
      expect(c.read(MusePrefs.accent), museDefaultAccent);
    });
    for (final s in [(const Size(320, 640), 2.0), (const Size(412, 915), 1.0), (const Size(1280, 800), 1.4)]) {
      testWidgets('no overflow ${s.$1.width.toInt()} @${s.$2}×, dark + 纯黑 + 文字缩放 on', (tester) async {
        await _pump(tester, {'theme_mode': 'black', 'muse_text_scale_on': true, 'muse_custom_accents': '#123456,#FFEB3B'}, size: s.$1, textScale: s.$2);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('appearance_pure_black')), findsOneWidget);
      });
    }
  });

  group('C7 通用 and search', () {
    test('静默启动 on the Windows rows, using the existing preference', () {
      final src = File('lib/features/muse/settings/windows_settings.dart').readAsStringSync();
      expect(src, contains("title: '静默启动'"));
      expect(src, contains('Preferences.silentStart'));
    });
    test('search finds the new entries', () {
      String first(String q, {bool windows = false}) => museSearchSettings(q, android: !windows, windows: windows).first.title;
      expect(first('纯黑'), '纯黑');
      expect(first('OLED'), '纯黑');
      expect(first('文字缩放'), '文字缩放');
      expect(first('字体大小'), '文字缩放');
      expect(first('hex'), '自定义主题色');
      expect(first('静默', windows: true), '静默启动');
      expect(museSearchSettings('静默', android: true, windows: false), isEmpty);
      expect(museSettingEntries.where((e) => e.title == '字体大小'), isEmpty);
    });
  });
}
