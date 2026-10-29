// 穿云 1.6.2 中国传统色主题: ten presets (景泰蓝 by default), old keys mapped to the new presets,
// custom "#RRGGBB" kept, readable text on light colours, traditional status lights, caching.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return la > lb ? la / lb : lb / la;
}

Future<ProviderContainer> _pump(WidgetTester tester, Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => Future.value(prefs))]);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  tester.view.physicalSize = const Size(412, 915) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  museApplyAccent(container.read(MusePrefs.accent));
  final mode = container.read(themePreferencesProvider);
  final theme = AppTheme(mode, '');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme.lightTheme(null), darkTheme: theme.darkTheme(null), themeMode: mode.flutterThemeMode, home: const MuseAppearancePage()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

const _expected = [
  ('jingtailan', '景泰蓝', 0xFF2775B6),
  ('pielan', '苤蓝', 0xFF6B798E),
  ('zhuqing', '竹青', 0xFF789262),
  ('yuebai', '月白', 0xFFD6ECF0),
  ('cangyinghui', '苍蝇灰', 0xFF36282B),
  ('zhujin', '朱瑾', 0xFFC41E3A),
  ('tenghuang', '藤黄', 0xFFFFB61E),
  ('qingbi', '青碧', 0xFF48C0A3),
  ('dingxiang', '丁香', 0xFFCCA4E3),
  ('zheshi', '赭石', 0xFF845A33),
];

void main() {
  tearDown(() => museApplyAccent(museDefaultAccent));

  group('1.6.2 presets', () {
    test('ten traditional colours in order, 景泰蓝 first and default', () {
      expect(MuseAccent.values.map((e) => (e.key, e.title, e.color.toARGB32())).toList(), _expected);
      expect(museSeedPresets.map((c) => c.toARGB32()).toList(), _expected.map((e) => e.$3).toList());
      expect(museBrandSeed, MuseAccent.jingtailan.color);
      expect(MuseAccent.fallback, MuseAccent.jingtailan);
      expect(museDefaultAccent, MuseAccent.jingtailan.key);
      expect(MuseAccent.fromKey('nope'), MuseAccent.jingtailan);
      expect(museAccentColors('').seed, MuseAccent.jingtailan.color);
    });
    test('old keys read as the new presets', () {
      const map = {
        'blue': MuseAccent.jingtailan,
        'green': MuseAccent.zhuqing,
        'teal': MuseAccent.qingbi,
        'purple': MuseAccent.dingxiang,
        'indigo': MuseAccent.pielan,
        'pink': MuseAccent.zhujin,
        'orange': MuseAccent.tenghuang,
      };
      map.forEach((old, now) {
        expect(MuseAccent.presetOrNull(old), now, reason: old);
        expect(museAccentColors(old), museAccentColors(now.key), reason: old);
      });
      // every new key and every old key resolves; no key collides
      expect({...MuseAccent.values.map((e) => e.key), ...MuseAccent.legacy.keys}.length, 17);
    });
    test('custom "#RRGGBB" still works and seeds the scheme with the colour itself', () {
      final c = museAccentColors('#3A5F0B');
      expect(c.seed, const Color(0xFF3A5F0B));
      expect(c.brand, const Color(0xFF3A5F0B));
      museApplyAccent('#FFEB3B');
      expect(MusePalette.seed, const Color(0xFFFFEB3B));
      expect(_contrast(MusePalette.brand, MusePalette.white), greaterThanOrEqualTo(museAccentMinContrast));
      expect(AppTheme.seed, const Color(0xFFFFEB3B));
    });
    testWidgets('a fresh install starts on 景泰蓝; an old saved "blue" stays the same preset', (tester) async {
      var c = await _pump(tester, {});
      expect(c.read(MusePrefs.accent), 'jingtailan');
      expect(MusePalette.seed, const Color(0xFF2775B6));
      c = await _pump(tester, {'muse_accent': 'blue'});
      expect(c.read(MusePrefs.accent), 'blue');
      expect(MusePalette.seed, const Color(0xFF2775B6));
      expect(find.descendant(of: find.byKey(const ValueKey('accent_jingtailan')), matching: find.byIcon(Icons.check_outlined)), findsOneWidget);
    });
  });

  group('1.6.2 readable', () {
    test('brand keeps white text ≥ 3:1; the swatch tick is ink on light colours', () {
      for (final a in MuseAccent.values) {
        expect(_contrast(a.brand, MusePalette.white), greaterThanOrEqualTo(museAccentMinContrast), reason: a.title);
        expect(_contrast(museOnColor(a.color), a.color), greaterThanOrEqualTo(museAccentMinContrast), reason: a.title);
      }
      for (final a in [MuseAccent.yuebai, MuseAccent.tenghuang, MuseAccent.dingxiang, MuseAccent.qingbi]) {
        expect(museOnColor(a.color), MusePalette.ink, reason: a.title);
      }
      for (final a in [MuseAccent.jingtailan, MuseAccent.zhujin, MuseAccent.cangyinghui, MuseAccent.zheshi]) {
        expect(museOnColor(a.color), MusePalette.white, reason: a.title);
      }
    });
    test('every preset × style × brightness: buttons and selected state stay readable', () {
      for (final a in MuseAccent.values) {
        for (final style in MuseColorStyle.values) {
          for (final b in Brightness.values) {
            for (final black in [false, true]) {
              final s = museSeededScheme(seed: a.color, brightness: b, style: style, pureBlack: black);
              final why = '${a.title} ${style.title} $b black=$black';
              expect(_contrast(s.primary, s.onPrimary), greaterThanOrEqualTo(3.0), reason: '$why primary');
              expect(_contrast(s.secondaryContainer, s.onSecondaryContainer), greaterThanOrEqualTo(4.5), reason: '$why selected');
              expect(_contrast(s.primaryContainer, s.onPrimaryContainer), greaterThanOrEqualTo(4.5), reason: '$why container');
              expect(_contrast(s.primary, MuseSurface.page.color(s)), greaterThanOrEqualTo(2.0), reason: '$why primary on page');
            }
          }
        }
      }
    });
  });

  group('1.6.2 status lights', () {
    test('葱青 / 杏黄 / 朱砂 / 墨灰, fixed whatever the 主题色', () {
      expect(MusePalette.green, const Color(0xFF0EB83A));
      expect(MusePalette.orange, const Color(0xFFFFA631));
      expect(MusePalette.red, const Color(0xFFFF461F));
      expect(MusePalette.grey, const Color(0xFF758A99));
      expect(MuseToast.success, MusePalette.green);
      expect(MuseToast.error, MusePalette.red);
      for (final b in Brightness.values) {
        final ref = museSeededScheme(brightness: b);
        for (final seed in museSeedPresets) {
          final s = museSeededScheme(seed: seed, brightness: b);
          expect(s.success, ref.success);
          expect(s.warning, ref.warning);
          expect(s.destructive, const Color(0xFFFF461F));
          expect(s.idle, ref.idle);
        }
        expect(_contrast(ref.destructive, MusePalette.white), greaterThanOrEqualTo(3.0));
      }
      expect(museSeededScheme(brightness: Brightness.light).idle, MusePalette.grey);
    });
    testWidgets('an untested delay is 墨灰', (tester) async {
      late Color c;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)),
        home: Builder(builder: (context) {
          c = MuseColors.delay(context, 0);
          return const SizedBox();
        }),
      ));
      expect(c, MusePalette.grey);
    });
  });

  group('1.6.2 page and cost', () {
    testWidgets('ten swatches; tapping 月白 saves it and shows an ink tick', (tester) async {
      final c = await _pump(tester, {});
      for (final e in _expected) {
        expect(find.byKey(ValueKey('accent_${e.$1}')), findsOneWidget, reason: e.$2);
        expect(find.byTooltip(e.$2), findsOneWidget, reason: e.$2);
      }
      await tester.tap(find.byKey(const ValueKey('accent_yuebai')));
      await tester.pump();
      expect(c.read(MusePrefs.accent), 'yuebai');
      final tick = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('accent_yuebai')), matching: find.byIcon(Icons.check_outlined)));
      expect(tick.color, MusePalette.ink);
      expect(tester.takeException(), isNull);
    });
    test('accent colours and schemes are computed once per value', () {
      expect(identical(museAccentColors('zheshi'), museAccentColors('zheshi')), isTrue);
      museSeededScheme(seed: MuseAccent.zheshi.color, brightness: Brightness.dark);
      final n = museSchemeComputations;
      for (var i = 0; i < 5; i++) {
        museApplyAccent('zheshi');
        museSeededScheme(seed: MusePalette.seed, brightness: Brightness.dark);
      }
      expect(museSchemeComputations, n);
    });
    test('settings search finds 主题色 by a traditional colour name', () {
      for (final q in ['景泰蓝', '月白', '中国传统色', '赭石']) {
        expect(museSearchSettings(q, android: true, windows: false).first.title, '主题色', reason: q);
      }
    });
  });
}
