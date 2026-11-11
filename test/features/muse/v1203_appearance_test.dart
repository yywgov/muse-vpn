// 穿云 1.20.3 外观页整理：首页风格四张（含经典）、配色六张（取代深浅色 + 纯黑开关 + 主题，旧设置双向映射）、
// 主题色在终端绿 / 暖纸时隐藏、外观页没有 ⓘ、隐私三项搬到 设置 › 隐私（搜索仍能找到）、底部留白含底栏；
// 关于 › 开源许可（致谢分组删除，上游项目仍注明并链接）；关于页版本行去掉内核小字。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/color_choice.dart';
import 'package:hiddify/features/muse/logic/resources.dart' show museAboutVersionLine;
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/color_choice_picker.dart';
import 'package:hiddify/features/muse/settings/home_look_picker.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_theme.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart' show museSettingsHomeRows;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, Widget page, Map<String, Object> initial, {Size size = const Size(412, 915)}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => prefs)]);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final theme = AppTheme(container.read(themePreferencesProvider), '');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme.lightTheme(null), darkTheme: theme.darkTheme(null), home: page),
    ),
  );
  await tester.pump();
  return container;
}

MuseSettingPage? _first(String q, {bool android = true}) => museSearchSettings(q, android: android, windows: false).firstOrNull?.page;

void main() {
  group('配色映射', () {
    test('旧设置读进来不丢：主题优先，主题为默认时看深浅色（纯黑 = 深色 + 纯黑开关）', () {
      MuseColorChoice read(AppThemeMode m, MuseThemeStyle s) => MuseColorChoice.read(mode: m, style: s);
      for (final m in AppThemeMode.values) {
        expect(read(m, MuseThemeStyle.terminal), MuseColorChoice.terminal);
        expect(read(m, MuseThemeStyle.paper), MuseColorChoice.paper);
        expect(read(m, MuseThemeStyle.black), MuseColorChoice.black); // 主题 = 纯黑
        expect(read(m, MuseThemeStyle.light), MuseColorChoice.light);
      }
      expect(read(AppThemeMode.system, MuseThemeStyle.auto), MuseColorChoice.system);
      expect(read(AppThemeMode.light, MuseThemeStyle.auto), MuseColorChoice.light);
      expect(read(AppThemeMode.dark, MuseThemeStyle.auto), MuseColorChoice.dark);
      expect(read(AppThemeMode.black, MuseThemeStyle.auto), MuseColorChoice.black); // 深色 + 纯黑开关
    });

    test('写回后再读是同一个；终端绿 / 暖纸不动深浅色；显示与 1.20.2 同名组合一致', () {
      for (final c in MuseColorChoice.values) {
        final (style, mode) = c.target;
        for (final before in AppThemeMode.values) {
          expect(MuseColorChoice.read(mode: mode ?? before, style: style), c, reason: '$c from $before');
        }
        expect(mode == null, c.ownPalette, reason: '$c');
      }
      // 同一套颜色和深浅：主题=纯黑 ≡ 深色+纯黑，主题=浅色 ≡ 浅色
      AppTheme theme(MuseColorChoice c) {
        final (style, mode) = c.target;
        return AppTheme(mode ?? AppThemeMode.light, '', style: style);
      }
      expect(theme(MuseColorChoice.black).scheme(Brightness.dark), AppTheme(AppThemeMode.light, '', style: MuseThemeStyle.black).scheme(Brightness.dark));
      expect(theme(MuseColorChoice.black).themeMode, ThemeMode.dark);
      expect(theme(MuseColorChoice.light).themeMode, AppTheme(AppThemeMode.dark, '', style: MuseThemeStyle.light).themeMode);
      expect(theme(MuseColorChoice.terminal).themeMode, ThemeMode.dark);
      expect(theme(MuseColorChoice.paper).themeMode, ThemeMode.light);
      expect([for (final c in MuseColorChoice.values) c.title], ['跟随系统', '浅色', '深色', '纯黑', '终端绿', '暖纸']);
    });

    testWidgets('点卡片写原来的键；换别的配色时关掉「跟随系统时纯黑」', (tester) async {
      final c = await _pump(tester, const MuseAppearancePage(android: false, windows: false), {
        'theme_mode': 'system',
        'muse_pure_black_follow': true,
        'muse_theme_style': 'auto',
      }, size: const Size(412, 1400));
      expect(c.read(museColorChoiceProvider), MuseColorChoice.system); // 旧组合读作跟随系统，开关照旧生效
      expect(c.read(MusePrefs.pureBlackFollowSystem), isTrue);
      await tester.tap(find.byKey(const ValueKey('color_choice_terminal')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.read(MusePrefs.themeStyle), 'terminal');
      expect(c.read(themePreferencesProvider), AppThemeMode.system); // 深浅色不动
      expect(c.read(MusePrefs.pureBlackFollowSystem), isFalse);
      await tester.tap(find.byKey(const ValueKey('color_choice_black')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.read(MusePrefs.themeStyle), 'auto');
      expect(c.read(themePreferencesProvider), AppThemeMode.black);
      final sem = tester.widget<Semantics>(find.ancestor(of: find.byKey(const ValueKey('color_choice_black')), matching: find.byType(Semantics)).first);
      expect(sem.properties.label, '配色 纯黑');
      expect(sem.properties.selected, isTrue);
    });
  });

  group('外观页', () {
    testWidgets('终端绿 / 暖纸时主题色整块隐藏，其余配色时紧跟配色', (tester) async {
      for (final (style, mode, shown) in [
        ('terminal', 'light', false),
        ('paper', 'dark', false),
        ('auto', 'dark', true),
        ('black', 'light', true),
      ]) {
        await _pump(tester, const MuseAppearancePage(android: false, windows: false), {'muse_theme_style': style, 'theme_mode': mode}, size: const Size(412, 1600));
        expect(find.byType(MuseAccentPicker), shown ? findsOneWidget : findsNothing, reason: style);
        if (shown) {
          final colors = tester.getRect(find.byKey(const ValueKey('appearance_color_choice')));
          final accent = tester.getRect(find.byKey(const ValueKey('appearance_accent')));
          expect(accent.top, greaterThan(colors.bottom));
          expect(accent.top - colors.bottom, lessThan(80)); // 紧跟，中间只有组标题
        }
      }
    });

    testWidgets('六张配色、四张首页风格；没有勾、没有说明句、没有 ⓘ、没有原来的几行', (tester) async {
      await _pump(tester, const MuseAppearancePage(android: true, windows: false), {}, size: const Size(412, 2000));
      expect(find.byType(MuseColorChoicePreview), findsNWidgets(6));
      expect(find.byType(MuseHomeLookPreview), findsNWidgets(4));
      expect(find.byIcon(Icons.check_circle_outlined), findsNothing);
      expect(find.byKey(const ValueKey('home_look_describe')), findsNothing);
      expect(find.byKey(const ValueKey('row_info')), findsNothing);
      expect(find.byKey(const ValueKey('section_info')), findsNothing);
      for (final gone in ['appearance_theme', 'appearance_pure_black', 'appearance_pure_black_follow', 'appearance_theme_style', 'appearance_home_style', 'appearance_privacy', 'appearance_secure_sensitive', 'clear_clipboard_switch']) {
        expect(find.byKey(ValueKey(gone)), findsNothing, reason: gone);
      }
      expect(find.byKey(const ValueKey('appearance_motion')), findsOneWidget);
      // 1.20.3：Android 通知一组搬到 隐私与通知，外观页不再有
      expect(find.text('从下次连接起生效'), findsNothing);
      expect(find.byKey(const ValueKey('appearance_android')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('首页风格：经典写 classic，前三个写 new + 对应风格', (tester) async {
      final c = await _pump(tester, const MuseAppearancePage(android: false, windows: false), {'muse_home_style': 'new', 'muse_home_look': 'line'}, size: const Size(412, 1400));
      await tester.tap(find.byKey(const ValueKey('home_look_classic')));
      await tester.pump();
      expect(c.read(MusePrefs.homeStyle), 'classic');
      expect(c.read(MusePrefs.homeLook), 'airy');
      await tester.tap(find.byKey(const ValueKey('home_look_number')));
      await tester.pump();
      expect(c.read(MusePrefs.homeStyle), 'new');
      expect(c.read(MusePrefs.homeLook), 'number');
      expect(MuseHomeChoice.read(homeStyle: 'classic', homeLook: 'line'), MuseHomeChoice.classic);
      expect(MuseHomeChoice.read(homeStyle: 'new', homeLook: 'nope'), MuseHomeChoice.airy);
    });

    for (final size in [const Size(320, 640), const Size(1280, 800)]) {
      testWidgets('${size.width.toInt()} 宽 × 深浅色不溢出', (tester) async {
        for (final mode in ['light', 'dark']) {
          await _pump(tester, const MuseAppearancePage(android: true, windows: true), {'theme_mode': mode}, size: size);
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('底部留白含底栏高度与系统导航条 inset', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 96);
      tester.view.viewPadding = const FakeViewPadding(bottom: 96);
      late EdgeInsets padding;
      await _pump(
        tester,
        Builder(
          builder: (context) {
            // inside the shell the bottom padding is removed from MediaQuery
            return MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: Builder(
                builder: (inner) {
                  padding = museSettingsPagePadding(inner);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
        {},
      );
      expect(padding.bottom, MuseSpace.s32 + MuseSize.dockHeight + 48);
    });

    test('无循环动画', () {
      for (final f in ['lib/features/muse/settings/color_choice_picker.dart', 'lib/features/muse/settings/home_look_picker.dart', 'lib/features/muse/settings/appearance_page.dart']) {
        final s = File(f).readAsStringSync();
        expect(s, isNot(contains('.repeat(')), reason: f);
        expect(s, isNot(contains('Timer.periodic')), reason: f);
      }
    });
  });

  group('设置 › 隐私', () {
    test('设置首页第二行是隐私', () {
      // 1.20.3：改名「隐私与通知」，排在 网络 后面
      expect(museSettingsHomeRows(android: true, developer: false), contains('隐私与通知'));
    });

    testWidgets('三项都在，敏感页禁止截屏只在安卓', (tester) async {
      await _pump(tester, const MusePrivacyPage(android: true), {});
      for (final k in ['appearance_privacy', 'appearance_secure_sensitive', 'clear_clipboard_switch']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await _pump(tester, const MusePrivacyPage(android: false), {});
      expect(find.byKey(const ValueKey('appearance_secure_sensitive')), findsNothing);
      expect(find.byKey(const ValueKey('appearance_privacy')), findsOneWidget);
    });

    testWidgets('开关写原来的键', (tester) async {
      final c = await _pump(tester, const MusePrivacyPage(android: true), {});
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('appearance_privacy')), matching: find.byType(Switch)));
      await tester.pump();
      expect(c.read(MusePrefs.privacyMask), isTrue);
    });

    test('搜索：移走的项打开隐私页；旧名（深浅色、纯黑、主题、首页样式）仍打开外观', () {
      expect(MuseSettingPage.privacy.path, '设置 › 隐私与通知'); // 1.20.3
      expect(_first('隐私模式'), MuseSettingPage.privacy);
      expect(_first('敏感页禁止截屏'), MuseSettingPage.privacy);
      expect(_first('截屏'), MuseSettingPage.privacy);
      expect(_first('敏感页禁止截屏', android: false), isNot(MuseSettingPage.privacy));
      expect(_first('导入后清空剪贴板'), MuseSettingPage.privacy);
      expect(_first('剪贴板'), MuseSettingPage.privacy);
      for (final q in ['配色', '深浅色', '纯黑', '主题', '终端绿', '暖纸', '首页样式', '经典首页', '首页风格']) {
        expect(_first(q), MuseSettingPage.appearance, reason: q);
      }
    });
  });

  group('关于 › 开源许可', () {
    test('搜索条目改名，去掉致谢关键词', () {
      final e = museSettingEntries.where((e) => e.page == MuseSettingPage.openSource).single;
      expect(e.title, '开源许可');
      expect(e.keywords, ['开源许可', '源代码', 'GPL', '许可证']);
      expect(MuseSettingPage.openSource.path, '设置 › 关于 › 开源许可');
      expect(museSearchSettings('致谢', android: true, windows: false), isEmpty);
      expect(_first('GPL'), MuseSettingPage.openSource);
    });

    test('关于页版本行只有版本号；内核版本仍在 设置 › 内核与资源', () {
      expect(museAboutVersionLine(version: '1.20.2', build: '215'), '1.20.2（215）');
      expect(File('lib/features/muse/settings/core_kind_section.dart').readAsStringSync(), contains("title: '内核版本'"));
    });

    test('字体许可文件保持打包', () {
      for (final f in ['assets/fonts/OFL-Inter.txt', 'assets/fonts/OFL-NotoSansSC.txt']) {
        expect(File(f).existsSync(), isTrue, reason: f);
      }
    });
  });
}
