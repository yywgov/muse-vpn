// 穿云 1.19.0 P5 主题：浅色 / 纯黑 / 终端绿 / 暖纸 的对比度（正文与次要文字 ≥ 4.5:1）、主题持久化与同步、
// 设置搜索、切换时的圆形揭开（标准揭开、精简淡出、关闭直接切换，结束后不再出帧）。
// Part of 穿云 (GPLv3).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';
import 'package:hiddify/features/muse/widget/muse_theme_reveal.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

/// 主题在给定深浅下的配色
ColorScheme _scheme(MuseThemeStyle style, Brightness b) => AppTheme(AppThemeMode.system, '', style: style).scheme(b);

Brightness _brightnessOf(MuseThemeStyle s) => s.forcedMode == ThemeMode.dark ? Brightness.dark : Brightness.light;

void main() {
  group('对比度', () {
    for (final style in MuseThemeStyle.values.where((s) => s != MuseThemeStyle.auto)) {
      test('${style.title}：正文、次要文字在页面/卡片/区块/内嵌上 ≥ 4.5:1；主色按钮文字 ≥ 4.5:1', () {
        final s = _scheme(style, _brightnessOf(style));
        expect(s.brightness, _brightnessOf(style));
        for (final surface in MuseSurface.values) {
          final bg = surface.color(s);
          expect(museContrast(s.onSurface, bg), greaterThanOrEqualTo(4.5), reason: '${style.title} 正文 / ${surface.name}');
          expect(museContrast(s.onSurfaceVariant, bg), greaterThanOrEqualTo(4.5), reason: '${style.title} 次要 / ${surface.name}');
        }
        expect(museContrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5), reason: '${style.title} onPrimary');
        expect(museContrast(s.onError, s.error), greaterThanOrEqualTo(4.5), reason: '${style.title} onError');
        expect(museContrast(s.onPrimaryContainer, s.primaryContainer), greaterThanOrEqualTo(4.5));
        expect(museContrast(s.onSecondaryContainer, s.secondaryContainer), greaterThanOrEqualTo(4.5));
        expect(museContrast(s.onTertiaryContainer, s.tertiaryContainer), greaterThanOrEqualTo(4.5));
        expect(museContrast(s.onErrorContainer, s.errorContainer), greaterThanOrEqualTo(4.5));
      });
    }

    test('纯黑复用原纯黑配色（页面 #000），浅色复用原浅色配色', () {
      final black = _scheme(MuseThemeStyle.black, Brightness.dark);
      expect(black.surface, const Color(0xFF000000));
      expect(black, AppTheme(AppThemeMode.black, '').scheme(Brightness.dark));
      expect(_scheme(MuseThemeStyle.light, Brightness.light), AppTheme(AppThemeMode.light, '').scheme(Brightness.light));
      // 默认 = 1.18 行为
      expect(_scheme(MuseThemeStyle.auto, Brightness.dark), AppTheme(AppThemeMode.dark, '').scheme(Brightness.dark));
    });

    test('固定深浅：浅色/暖纸 → 浅，纯黑/终端绿 → 深，默认按深浅色', () {
      expect(AppTheme(AppThemeMode.dark, '', style: MuseThemeStyle.paper).themeMode, ThemeMode.light);
      expect(AppTheme(AppThemeMode.light, '', style: MuseThemeStyle.terminal).themeMode, ThemeMode.dark);
      expect(AppTheme(AppThemeMode.light, '', style: MuseThemeStyle.black).themeMode, ThemeMode.dark);
      expect(AppTheme(AppThemeMode.dark, '', style: MuseThemeStyle.light).themeMode, ThemeMode.light);
      expect(AppTheme(AppThemeMode.dark, '').themeMode, ThemeMode.dark);
      expect(AppTheme(AppThemeMode.system, '').themeMode, ThemeMode.system);
    });

    test('配色写在令牌文件里（tokens lint 豁免的 muse_tokens_*）', () {
      expect(File('lib/features/muse/widget/muse_tokens_theme.dart').existsSync(), isTrue);
      expect(_src('lib/features/muse/widget/muse_theme_reveal.dart'), isNot(contains('Color(0x')));
    });
  });

  group('设置', () {
    test('主题持久化：写入 muse_theme_style，默认 auto，加入同步与设置搜索', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => sp)]);
      addTearDown(c.dispose);
      await c.read(sharedPreferencesProvider.future);
      expect(c.read(MusePrefs.themeStyle), 'auto');
      await c.read(MusePrefs.themeStyle.notifier).update(MuseThemeStyle.paper.key);
      expect(sp.getString('muse_theme_style'), 'paper');
      // 重新读取（相当于重启）仍是暖纸
      final c2 = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => sp)]);
      addTearDown(c2.dispose);
      await c2.read(sharedPreferencesProvider.future);
      expect(MuseThemeStyle.fromKey(c2.read(MusePrefs.themeStyle)), MuseThemeStyle.paper);
      expect(museSyncedPrefKeys, contains('muse_theme_style'));
      final e = museSettingEntries.where((e) => e.title == '主题').single;
      expect(e.page, MuseSettingPage.appearance);
      expect(e.keywords, containsAll(['浅色', '纯黑', '终端绿', '暖纸']));
      expect(MuseThemeStyle.fromKey('nope'), MuseThemeStyle.auto);
    });

    test('外观页：主题一行在，原有深浅色、纯黑、跟随系统纯黑都保留', () {
      final page = _src('lib/features/muse/settings/appearance_page.dart');
      expect(page, contains("ValueKey('appearance_theme_style')"));
      expect(page, contains("ValueKey('appearance_theme')"));
      expect(page, contains("ValueKey('appearance_pure_black')"));
      expect(page, contains("ValueKey('appearance_pure_black_follow')"));
      expect([for (final s in MuseThemeStyle.values) s.title], ['默认', '浅色', '纯黑', '终端绿', '暖纸']);
      expect(_src('lib/features/app/widget/app.dart'), contains('MuseThemeReveal(child: child)'));
    });
  });

  group('圆形揭开', () {
    Widget app(MuseMotionLevel level, ValueNotifier<bool> dark) => ValueListenableBuilder<bool>(
      valueListenable: dark,
      builder: (context, d, _) => MaterialApp(
        theme: ThemeData(colorScheme: museWarmPaperScheme),
        darkTheme: ThemeData(colorScheme: museTerminalScheme),
        themeMode: d ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MuseThemeReveal(child: museWrapMotion(context, level, child!)),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('switch'),
                onPressed: () => MuseThemeReveal.run(context, const Offset(10, 10), () async => dark.value = !d),
                child: const Text('切换'),
              ),
            ),
          ),
        ),
      ),
    );

    MuseThemeRevealState state(WidgetTester t) => t.state<MuseThemeRevealState>(find.byType(MuseThemeReveal));

    testWidgets('标准档：从点按位置揭开，约 400ms 后结束、释放截图、不再出帧', (t) async {
      final dark = ValueNotifier(false);
      await t.pumpWidget(app(MuseMotionLevel.standard, dark));
      await t.tap(find.byKey(const ValueKey('switch')));
      await t.pump();
      expect(dark.value, isTrue);
      expect(state(t).revealing, isTrue);
      expect(find.byKey(const ValueKey('theme_reveal_overlay')), findsOneWidget);
      await t.pump(const Duration(milliseconds: 200));
      expect(state(t).revealing, isTrue);
      await t.pump(const Duration(milliseconds: 250));
      await t.pump();
      expect(state(t).revealing, isFalse);
      expect(find.byKey(const ValueKey('theme_reveal_overlay')), findsNothing);
      await t.pumpAndSettle();
      expect(SchedulerBinding.instance.hasScheduledFrame || t.binding.transientCallbackCount > 0, isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('精简档：旧画面淡出（约 200ms）', (t) async {
      final dark = ValueNotifier(false);
      await t.pumpWidget(app(MuseMotionLevel.reduced, dark));
      await t.tap(find.byKey(const ValueKey('switch')));
      await t.pump();
      expect(state(t).revealing, isTrue);
      final p = t.widget<CustomPaint>(find.byKey(const ValueKey('theme_reveal_overlay'))).painter! as MuseRevealPainter;
      expect(p.fade, isTrue);
      await t.pump(const Duration(milliseconds: museThemeFadeMs + 20));
      await t.pump();
      expect(state(t).revealing, isFalse);
      await t.pumpAndSettle();
    });

    testWidgets('关闭档：不截图、没有动画，立即切换', (t) async {
      final dark = ValueNotifier(false);
      await t.pumpWidget(app(MuseMotionLevel.off, dark));
      await t.tap(find.byKey(const ValueKey('switch')));
      await t.pump();
      expect(dark.value, isTrue);
      expect(state(t).revealing, isFalse);
      expect(find.byKey(const ValueKey('theme_reveal_overlay')), findsNothing);
      await t.pumpAndSettle();
    });

    test('揭开半径覆盖整个画面', () {
      expect(MuseRevealPainter.maxRadius(const Size(300, 400), Offset.zero), 500);
      expect(MuseRevealPainter.maxRadius(const Size(300, 400), const Offset(150, 200)), 250);
    });

    test('揭开文件里没有循环动画或计时器', () {
      final s = _src('lib/features/muse/widget/muse_theme_reveal.dart');
      expect(s, isNot(contains('repeat(')));
      expect(s, isNot(contains('Timer')));
    });
  });
}
