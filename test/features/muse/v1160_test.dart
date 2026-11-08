// 穿云 1.16.0 批4 界面/统计/隐私: B7 按天/按应用流量图, B8 敏感页禁截屏与后台模糊, B9 纯黑深色,
// B10 新用户一步引导, B11 读屏标签, R25 小组件常用节点, R17 国内应用识别.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/muse/home/first_guide.dart';
import 'package:hiddify/features/muse/data/secure_screen.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiddify/features/muse/logic/domestic_apps.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart' show museNodeSemanticsLabel;
import 'package:hiddify/features/muse/widget/grouped_list.dart' show MuseSwitchTile;
import 'package:hiddify/features/profile/add/add_profile_modal.dart' show MuseAddAction;
import 'package:hiddify/features/muse/logic/per_app_tools.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('R17 国内应用识别', () {
    MuseAppRow app(String p) => MuseAppRow(packageName: p, name: p);

    test('only installed, listed and not yet selected packages', () {
      final installed = [app('com.tencent.mm'), app('org.example.foo'), app('com.eg.android.AlipayGphone'), app('tv.danmaku.bili')];
      final flags = {'com.eg.android.AlipayGphone': 1};
      expect(museDomesticTargets(installed, flags), ['com.tencent.mm', 'tv.danmaku.bili']);
      expect(museDomesticTargets(const [], const {}), isEmpty);
    });

    test('the list is local, exact package names, no foreign apps', () {
      expect(museDomesticPackages.length, greaterThan(80));
      final pkg = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$');
      for (final p in museDomesticPackages) {
        expect(pkg.hasMatch(p), isTrue, reason: p);
      }
      for (final p in ['com.google.android.youtube', 'org.telegram.messenger', 'com.twitter.android', 'com.whatsapp']) {
        expect(museDomesticPackages, isNot(contains(p)));
      }
      final src = _src('lib/features/muse/logic/domestic_apps.dart');
      expect(src, isNot(contains('http')));
      expect(src, isNot(contains('Timer')));
    });

    test('summary', () {
      expect(museDomesticSummary(added: 0, already: 0), '没有找到常见国内应用');
      expect(museDomesticSummary(added: 3, already: 0), '已选中 3 个常见国内应用');
      expect(museDomesticSummary(added: 0, already: 2), '常见国内应用已全部选中（2 个）');
      expect(museDomesticSummary(added: 1, already: 2), contains('另有 2 个'));
    });

    test('menu entry only in 以下 App 不走代理 mode', () {
      final src = _src('lib/features/app_based_routing/overview/app_list_page.dart');
      expect(src, contains("if (mode == AppProxyMode.exclude)\n                      MuseMenuItem(label: '选中常见国内应用'"));
      expect(src, contains('museDomesticTargets(installed, flags)'));
    });
  });

  group('B9 纯黑深色', () {
    test('跟随系统 + 纯黑 is black only while the system is dark', () {
      bool b(AppThemeMode m, bool f, Brightness br) => museUsePureBlack(m, blackWhenSystemDark: f, brightness: br);
      expect(b(AppThemeMode.system, true, Brightness.dark), isTrue);
      expect(b(AppThemeMode.system, true, Brightness.light), isFalse);
      expect(b(AppThemeMode.system, false, Brightness.dark), isFalse);
      expect(b(AppThemeMode.black, false, Brightness.dark), isTrue);
      expect(b(AppThemeMode.dark, true, Brightness.dark), isFalse); // 深色 keeps its own 纯黑 switch
      expect(b(AppThemeMode.light, true, Brightness.dark), isFalse);
    });

    test('the dark scheme surface is #000000, the light one is not', () {
      final t = AppTheme(AppThemeMode.system, '', blackWhenSystemDark: true);
      expect(t.scheme(Brightness.dark).surface, const Color(0xFF000000));
      expect(t.scheme(Brightness.light).surface, isNot(const Color(0xFF000000)));
      expect(AppTheme(AppThemeMode.system, '').scheme(Brightness.dark).surface, isNot(const Color(0xFF000000)));
    });

    test('外观 shows 纯黑 under 跟随系统; app applies the saved switch', () {
      final page = _src('lib/features/muse/settings/appearance_page.dart');
      expect(page, contains("ValueKey('appearance_pure_black_follow')"));
      expect(page, contains('if (shownTheme == AppThemeMode.system)'));
      final app = _src('lib/features/app/widget/app.dart');
      expect(app, contains('blackWhenSystemDark: blackFollow'));
      expect(_src('lib/features/muse/data/muse_prefs.dart'), contains('"muse_pure_black_follow", false'));
    });
  });

  group('B10 新用户一步引导', () {
    test('new install shows it once; upgrades and existing users never see it', () {
      expect(museFirstGuideFor(done: false, hasProfile: false, changelogShown: ''), MuseFirstGuide.show);
      expect(museFirstGuideFor(done: true, hasProfile: false, changelogShown: ''), MuseFirstGuide.none);
      expect(museFirstGuideFor(done: false, hasProfile: null, changelogShown: ''), MuseFirstGuide.none); // still reading
      expect(museFirstGuideFor(done: false, hasProfile: true, changelogShown: ''), MuseFirstGuide.markDone);
      expect(museFirstGuideFor(done: false, hasProfile: false, changelogShown: '1.15.0'), MuseFirstGuide.markDone);
    });

    test('actions: paste always, 扫码 only with a camera scanner', () {
      expect([for (final a in museGuideActions(qr: true)) a.$4], [MuseAddAction.paste, MuseAddAction.qr]);
      expect([for (final a in museGuideActions(qr: false)) a.$4], [MuseAddAction.paste]);
    });

    testWidgets('sheet: 粘贴 / 扫码 return the action, 跳过 returns nothing', (tester) async {
      MuseAddAction? got;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                got = await showModalBottomSheet<MuseAddAction>(context: context, builder: (_) => const MuseFirstGuideSheet(qr: true));
                closed = true;
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('欢迎使用穿云'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide_qr')));
      await tester.pumpAndSettle();
      expect(got, MuseAddAction.qr);
      closed = false;
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide_skip')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(got, isNull);
    });

    test('home decides before the 更新说明 effect records the version, and records the guide as done first', () {
      final home = _src('lib/features/muse/home/muse_home_page.dart');
      expect(home, contains('final shownBefore = ref.read(Preferences.museChangelogShown);'));
      expect(home, contains('museGuideAskConnect(context, ref)'));
      final g = _src('lib/features/muse/home/first_guide.dart');
      final i = g.indexOf('await ref.read(MusePrefs.onboardingDone.notifier).update(true)');
      expect(i, greaterThan(0));
      expect(i, lessThan(g.indexOf('showModalBottomSheet')));
      expect(g, isNot(contains('Timer')));
      expect(g, isNot(contains('Clipboard')));
    });
  });

  group('B11 读屏标签', () {
    testWidgets('a switch row is one item: title + switch state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(child: MuseSwitchTile(title: '开机自动连接', value: true, onChanged: (_) {})),
        ),
      );
      final node = tester.getSemantics(find.byType(ListTile));
      final data = node.getSemanticsData();
      expect(data.label, contains('开机自动连接'));
      expect(data.hasFlag(SemanticsFlag.hasToggledState), isTrue);
      expect(data.hasFlag(SemanticsFlag.isToggled), isTrue);
      handle.dispose();
    });

    test('node card label (Chinese)', () {
      expect(museNodeSemanticsLabel('香港 01', '85 ms', selected: false), '节点 香港 01，延迟 85 ms');
      expect(museNodeSemanticsLabel('日本', '', selected: true), '当前节点，节点 日本');
      final src = _src('lib/features/muse/nodes/node_rows.dart');
      expect(src, contains("hint: selected ? null : '点按切换到这个节点'"));
    });

    test('the big connect switch speaks 连接 / 断开 / 取消连接', () {
      final home = _src('lib/features/muse/home/muse_home_page.dart');
      expect(home, contains("MuseConnectAction.cancel => '取消连接'"));
      expect(home, contains("MuseConnectAction.disconnect => '断开'"));
    });

    test('every icon-only button on the 穿云 pages has a Chinese tooltip (read aloud)', () {
      final bad = <String>[];
      final start = RegExp(r'IconButton(?:\.filled|\.outlined|\.filledTonal)?\(');
      for (final f in Directory('lib/features/muse').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync();
        for (final m in start.allMatches(s)) {
          var i = m.end;
          var depth = 1;
          while (depth > 0 && i < s.length) {
            if (s[i] == '(') depth++;
            if (s[i] == ')') depth--;
            i++;
          }
          final body = s.substring(m.start, i);
          if (!body.contains('tooltip')) bad.add('${f.path}:${'\n'.allMatches(s.substring(0, m.start)).length + 1}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  });

  group('B8 敏感页禁截屏与后台模糊', () {
    late List<bool> calls;
    setUp(() {
      calls = [];
      museSecureSetter = (on) async {
        calls.add(on);
        return true;
      };
    });

    Future<ProviderContainer> container({bool? on}) async {
      SharedPreferences.setMockInitialValues({if (on != null) 'muse_secure_sensitive': on});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
      await c.read(sharedPreferencesProvider.future);
      addTearDown(c.dispose);
      return c;
    }

    test('counter: on with the first page, off with the last', () {
      final c = MuseSecureCounter();
      expect(c.enter(), isTrue);
      expect(c.enter(), isFalse);
      expect(c.leave(), isFalse);
      expect(c.leave(), isTrue);
      expect(c.leave(), isFalse); // never below zero
    });

    test('default on: secured while open, cleared after (also on error)', () async {
      final c = await container();
      expect(c.read(MusePrefs.secureSensitive), isTrue);
      await museWithSecureScreen(c, () async {
        expect(calls, [true]);
        await museWithSecureScreen(c, () async {}); // a QR over 节点详情
        expect(calls, [true]);
      });
      expect(calls, [true, false]);
      await expectLater(museWithSecureScreen(c, () async => throw StateError('x')), throwsStateError);
      expect(calls, [true, false, true, false]);
    });

    test('turned off in 外观: nothing is called', () async {
      final c = await container(on: false);
      await museWithSecureScreen(c, () async {});
      expect(calls, isEmpty);
    });

    test('the four sensitive places are wrapped; Android sets FLAG_SECURE on the window', () {
      expect(_src('lib/features/muse/nodes/node_details.dart'), contains('museSecureFor(context, () => _showMuseNodeDetails('));
      expect(_src('lib/features/muse/widget/qr_view.dart'), contains('await museSecureFor(context, () => showDialog<void>('));
      expect(_src('lib/features/muse/settings/sync_pages.dart'), contains('museSecureFor(context, () => _museExportConfig(context, ref))'));
      expect(_src('lib/features/profile/details/profile_details_page.dart'), contains('return MuseSecureScope(child: Scaffold('));
      final kt = _src('android/app/src/main/kotlin/com/hiddify/hiddify/ChuanyunHandler.kt');
      expect(kt, contains('"set_secure_screen"'));
      expect(kt, contains('addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)'));
      expect(kt, contains('clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)'));
      expect(_src('lib/features/muse/settings/appearance_page.dart'), contains("ValueKey('appearance_secure_sensitive')"));
    });
  });
}
