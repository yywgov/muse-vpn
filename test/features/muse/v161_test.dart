// 穿云 1.6.1: 订阅 card (Material 3 filled card, outlined menu icon), 外观 › 配色风格 and its
// search entry, and the power / performance budget of the new colours: a colour scheme and a
// theme are computed once per change and reused, nothing extra runs while hidden or in the
// background.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(WidgetTester t, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  await t.runAsync(() => c.read(translationsProvider.future));
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  return c;
}

Widget _app(ProviderContainer c, Widget home, {Brightness brightness = Brightness.light}) {
  final theme = AppTheme(brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light, '');
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: theme.lightTheme(null),
      darkTheme: theme.darkTheme(null),
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: home,
    ),
  );
}

/// What app.dart does for the colours: apply the accent and style, then ask for the theme.
class _ThemeProbe extends ConsumerWidget {
  const _ThemeProbe(this.onBuild);

  final void Function(ThemeData) onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    museApplyAccent(ref.watch(MusePrefs.accent));
    museApplyColorStyle(ref.watch(MusePrefs.colorStyle));
    final theme = AppTheme(AppThemeMode.light, '').lightTheme(null);
    onBuild(theme);
    return const SizedBox();
  }
}

void main() {
  tearDown(() {
    museApplyAccent('blue');
    museApplyColorStyle('tonalSpot');
  });

  group('1.6.1 订阅 card', () {
    test('menu icon is the outlined Material one (no Fluent icon left in the card)', () {
      final src = File('lib/features/profile/widget/profile_tile.dart').readAsStringSync();
      expect(src, contains('Icons.more_vert_outlined'));
      expect(src, isNot(contains('AdaptiveIcon')));
      expect(src, isNot(contains('FluentIcons')));
      expect(src, isNot(contains('VerticalDivider')));
      // #85: only *_outlined Material icons in the file
      for (final m in RegExp(r'Icons\.(\w+)').allMatches(src)) {
        expect(m.group(1), endsWith('_outlined'), reason: m.group(0));
      }
    });

    for (final b in [Brightness.light, Brightness.dark]) {
      testWidgets('filled card: active on secondary container, others on the highest container (${b.name})', (t) async {
        final c = await _container(t);
        ProfileEntity p(String id, bool active) =>
            ProfileEntity.remote(id: id, active: active, name: '订阅 $id', url: 'https://sub.example.com/$id', lastUpdate: DateTime(2026, 10));
        await t.pumpWidget(
          _app(
            c,
            Scaffold(
              body: Column(
                children: [
                  ProfileTile(key: const ValueKey('a'), profile: p('a', true)),
                  ProfileTile(key: const ValueKey('b'), profile: p('b', false)),
                ],
              ),
            ),
            brightness: b,
          ),
        );
        await t.pump(const Duration(milliseconds: 300));
        final scheme = Theme.of(t.element(find.byKey(const ValueKey('a')))).colorScheme;
        Card card(String k) => t.widget<Card>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byKey(const ValueKey('profile_tile_card'))));
        expect(card('a').color, scheme.secondaryContainer);
        expect(card('b').color, scheme.surfaceContainerHighest);
        expect(card('a').elevation, 0);
        Material leading(String k) => t.widget<Material>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byKey(const ValueKey('profile_tile_leading'))));
        expect(leading('a').color, scheme.primaryContainer);
        expect(leading('b').color, scheme.surfaceContainerLow);
        expect(find.byIcon(Icons.more_vert_outlined), findsNWidgets(2));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 61));
      });
    }
  });

  group('1.6.1 配色风格', () {
    test('seven styles offered in order; unknown keys read as 标准', () {
      expect(MuseColorStyle.offered.map((e) => e.title), ['标准', '鲜艳', '表现力', '柔和', '鲜明', '着色', '单色']);
      expect(MuseColorStyle.offered.toSet(), MuseColorStyle.values.toSet());
      expect(MuseColorStyle.fromKey('bogus'), MuseColorStyle.tonalSpot);
    });

    testWidgets('外观 shows 配色风格 (标准 by default); picking 鲜艳 saves it', (t) async {
      final c = await _container(t);
      await t.pumpWidget(_app(c, const MuseAppearancePage()));
      await t.pump(const Duration(milliseconds: 300));
      final tile = find.byKey(const ValueKey('appearance_color_style'));
      expect(tile, findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('标准')), findsOneWidget);
      await t.tap(tile);
      await t.pumpAndSettle();
      for (final s in MuseColorStyle.offered) {
        expect(find.byKey(ValueKey('pick_${s.title}')), findsOneWidget, reason: s.title);
      }
      await t.tap(find.byKey(const ValueKey('pick_鲜艳')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.colorStyle), 'vibrant');
      expect(find.descendant(of: tile, matching: find.text('鲜艳')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('外观 at 320 px and 2× text does not overflow', (t) async {
      final c = await _container(t, {'muse_color_style': 'expressive'});
      t.view.physicalSize = const Size(320, 640) * 2;
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(_app(c, const MuseAppearancePage()));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
    });

    test('设置搜索 finds 配色风格 by its name and by a style', () {
      for (final q in ['配色风格', '鲜艳', '单色', '表现力']) {
        final hits = museSearchSettings(q, android: true, windows: false);
        expect(hits.any((e) => e.title == '配色风格' && e.page == MuseSettingPage.appearance), isTrue, reason: q);
      }
    });

    test('the style is synced and backed up', () {
      final src = File('lib/features/muse/data/sync_service.dart').readAsStringSync();
      expect(src, contains("'muse_color_style'"));
    });
  });

  group('1.6.1 省电 / 性能', () {
    testWidgets('switching 配色风格 computes the scheme and theme once; rebuilds and switching back reuse them', (t) async {
      // a seed no other test uses, so the caches start cold for it
      final c = await _container(t, {'muse_accent': '#3A5F0B', 'muse_color_style': 'tonalSpot'});
      final themes = <ThemeData>[];
      final bump = ValueNotifier(0);
      addTearDown(bump.dispose);
      await t.pumpWidget(_app(c, ValueListenableBuilder<int>(valueListenable: bump, builder: (_, _, _) => _ThemeProbe(themes.add))));
      final schemes0 = museSchemeComputations;
      final builds0 = AppTheme.debugThemeBuilds;
      // unrelated rebuilds of the app: nothing is computed again, the same ThemeData comes back
      for (var i = 0; i < 10; i++) {
        bump.value++;
        await t.pump();
      }
      expect(museSchemeComputations, schemes0);
      expect(AppTheme.debugThemeBuilds, builds0);
      expect(themes.length, greaterThan(10));
      expect(themes.toSet().length, 1);

      // one switch → exactly one scheme and one theme
      await c.read(MusePrefs.colorStyle.notifier).update('vibrant');
      await t.pump();
      expect(museSchemeComputations, schemes0 + 1);
      expect(AppTheme.debugThemeBuilds, builds0 + 1);
      for (var i = 0; i < 5; i++) {
        bump.value++;
        await t.pump();
      }
      expect(museSchemeComputations, schemes0 + 1);
      expect(AppTheme.debugThemeBuilds, builds0 + 1);

      // back to 标准: already cached, nothing computed
      await c.read(MusePrefs.colorStyle.notifier).update('tonalSpot');
      await t.pump();
      expect(museSchemeComputations, schemes0 + 1);
      expect(AppTheme.debugThemeBuilds, builds0 + 1);
      expect(identical(themes.last, themes.first), isTrue);
    });

    testWidgets('首页 connected time: no timer while the app is in the background or the tab is hidden', (t) async {
      final since = DateTime.now().subtract(const Duration(minutes: 3));
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: hidden,
            builder: (_, h, _) => TickerMode(enabled: !h, child: MuseUptimeText(since: since)),
          ),
        ),
      );
      expect(MuseUptimeText.debugActiveTimers, 1);
      final builds = MuseUptimeText.debugBuilds;
      await t.pump(const Duration(seconds: 3));
      expect(MuseUptimeText.debugBuilds, greaterThan(builds));

      // background: the timer is gone and nothing ticks
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(MuseUptimeText.debugActiveTimers, 0);
      final paused = MuseUptimeText.debugBuilds;
      await t.pump(const Duration(seconds: 30));
      expect(MuseUptimeText.debugBuilds, paused);

      // foreground again: one timer, the time is right at once
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(MuseUptimeText.debugActiveTimers, 1);

      // another tab (tickers muted): no timer either
      hidden.value = true;
      await t.pump();
      expect(MuseUptimeText.debugActiveTimers, 0);
      final muted = MuseUptimeText.debugBuilds;
      await t.pump(const Duration(seconds: 10));
      expect(MuseUptimeText.debugBuilds, muted);
      hidden.value = false;
      await t.pump();
      expect(MuseUptimeText.debugActiveTimers, 1);

      await t.pumpWidget(const SizedBox());
      expect(MuseUptimeText.debugActiveTimers, 0);
    });

    test('the bottom gap reads MediaQuery only (no listener, no state)', () {
      final src = File('lib/features/muse/shell/muse_shell.dart').readAsStringSync();
      final fn = src.substring(src.indexOf('double museScrollEndGap'), src.indexOf('/// Fades (or slides)'));
      expect(fn, contains('MediaQuery.paddingOf(context)'));
      for (final bad in ['addListener', 'WidgetsBindingObserver', 'Timer', 'StatefulWidget']) {
        expect(fn, isNot(contains(bad)), reason: bad);
      }
    });

    test('new 1.6.1 code stays free of upstream names', () {
      for (final f in [
        'test/features/muse/v161_scroll_end_test.dart',
        'lib/features/profile/widget/profile_tile.dart',
      ]) {
        final src = File(f).readAsStringSync().toLowerCase();
        expect(src.contains('flclash'), isFalse, reason: f);
      }
      final shell = File('lib/features/muse/shell/muse_shell.dart').readAsStringSync();
      final gap = shell.substring(shell.indexOf('/// 1.6.1: the bottom padding'), shell.indexOf('/// Fades (or slides)'));
      expect(gap.toLowerCase().contains('flclash') || gap.toLowerCase().contains('hiddify'), isFalse);
    });
  });
}
