// 穿云 1.16.0 批4 界面/统计/隐私: B7 按天/按应用流量图, B8 敏感页禁截屏与后台模糊, B9 纯黑深色,
// B10 新用户一步引导, B11 读屏标签, R25 小组件常用节点, R17 国内应用识别.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/muse/logic/domestic_apps.dart';
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
}
