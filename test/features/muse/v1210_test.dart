// 穿云 1.21.0：M12 扫光骨架、V3 / V5 字色、V14 迷你图、I6 托盘图标、I8 资源清理、M13 启动页深浅色。
// （M3 连接按钮见 v1180_test「P2」，地图方向 B 见 v1191_test「6 / 7 / 8」。）
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/shimmer_skeleton.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart' show museSparkMinSamples;
import 'package:hiddify/features/muse/widget/muse_motion.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';

Widget _app(Widget child, MuseMotionLevel level) => MaterialApp(
  home: MuseMotionScope(
    level: level,
    child: Scaffold(body: Center(child: child)),
  ),
);

double _opacityOf(WidgetTester t) => t
    .widgetList<Opacity>(find.descendant(of: find.byType(ShimmerSkeleton), matching: find.byType(Opacity)))
    .map((o) => o.opacity)
    .fold(1.0, (a, b) => a * b);

void main() {
  group('M12 扫光骨架', () {
    testWidgets('300ms 内不出现（占位同大小），标准档最多扫 2 趟后静止', (t) async {
      await t.pumpWidget(_app(const ShimmerSkeleton(width: 40, height: 40), MuseMotionLevel.standard));
      expect(t.getSize(find.byType(ShimmerSkeleton)), const Size(40, 40));
      expect(_opacityOf(t), 0);
      await t.pump(const Duration(milliseconds: 200));
      expect(_opacityOf(t), 0);
      await t.pump(const Duration(milliseconds: 150));
      await t.pump();
      expect(_opacityOf(t), 1);
      // the shimmer starts on the next tick (flutter_animate plays after a zero delay)
      await t.pump(const Duration(milliseconds: 16));
      expect(t.binding.hasScheduledFrame, isTrue);
      // 2 passes of 1s, then no more frames
      var ms = 0;
      while (t.binding.hasScheduledFrame && ms < 5000) {
        await t.pump(const Duration(milliseconds: 100));
        ms += 100;
      }
      expect(ms, inInclusiveRange(1900, 2300));
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    for (final level in [MuseMotionLevel.reduced, MuseMotionLevel.off]) {
      testWidgets('${level.name}：出现后是静态骨架，不出帧', (t) async {
        await t.pumpWidget(_app(const ShimmerSkeleton(width: 40, height: 40), level));
        await t.pump(const Duration(milliseconds: 350));
        await t.pump();
        expect(_opacityOf(t), 1);
        expect(t.binding.hasScheduledFrame, isFalse);
      });
    }

    testWidgets('加载在 300ms 内结束：骨架从未显示，定时器随之取消', (t) async {
      await t.pumpWidget(_app(const ShimmerSkeleton(width: 40, height: 40), MuseMotionLevel.standard));
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(_app(const SizedBox(), MuseMotionLevel.standard));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    test('源码：不再无限循环', () {
      final s = File('lib/core/widget/shimmer_skeleton.dart').readAsStringSync();
      expect(s, isNot(contains('controller.loop()')));
      expect(s, contains('repeat(count: maxPasses)'));
      expect(ShimmerSkeleton.maxPasses, 2);
      expect(ShimmerSkeleton.showDelay, const Duration(milliseconds: 300));
    });
  });

  group('V3 / V5 字色 ≥ 4.5:1', () {
    for (final dark in [false, true]) {
      test('状态字色（${dark ? '深' : '浅'}）对页面与卡片都 ≥ 4.5，灯色不变', () {
        final s = ColorScheme.fromSeed(seedColor: const Color(0xFF2775B6), brightness: dark ? Brightness.dark : Brightness.light);
        final backs = dark ? museDarkTextBacks : museLightTextBacks;
        for (final c in [s.successText, s.warningText, s.errorText, s.idleText]) {
          for (final b in backs) {
            expect(museContrast(c, b), greaterThanOrEqualTo(4.5), reason: '$c on $b');
          }
        }
        expect(museStatusGreen, const Color(0xFF0EB83A));
        expect(museStatusYellow, const Color(0xFFFFA631));
      });
    }

    // 青碧 / 丁香 / 藤黄 / 松花 / 竹青 / 景泰蓝 这类浅色主题色作文字
    const seeds = [
      Color(0xFF48C0A3),
      Color(0xFFBBA1CB),
      Color(0xFFFFA631),
      Color(0xFFBCE672),
      Color(0xFF789262),
      Color(0xFF2775B6),
    ];
    for (final seed in seeds) {
      test('accentText ${seed.toARGB32().toRadixString(16)}：浅色 / 深色都 ≥ 4.5，色相不变', () {
        for (final dark in [false, true]) {
          final s = ColorScheme.fromSeed(seedColor: seed, brightness: dark ? Brightness.dark : Brightness.light).copyWith(primary: seed);
          final text = s.accentText;
          for (final b in dark ? museDarkTextBacks : museLightTextBacks) {
            expect(museContrast(text, b), greaterThanOrEqualTo(4.5), reason: '${dark ? 'dark' : 'light'} $text on $b');
          }
        }
      });
    }

    test('已经够深的主题色原样返回', () {
      const deep = Color(0xFF1F64A0);
      expect(museReadableText(deep, museLightTextBacks), deep);
    });

    test('节点延迟数字用字色、分组标题与文字按钮用 accentText', () {
      final rows = File('lib/features/muse/nodes/node_rows.dart').readAsStringSync();
      expect(rows, contains('MuseColors.delayText(context, view.delay)'));
      expect(rows, isNot(contains('MuseDelayKind.timeout => MusePalette.red')));
      final list = File('lib/features/muse/widget/grouped_list.dart').readAsStringSync();
      expect(list, contains('colorScheme.accentText, weight: FontWeight.w600'));
      final theme = File('lib/core/theme/app_theme.dart').readAsStringSync();
      expect(theme, contains('foregroundColor: s.accentText'));
    });
  });

  test('V14 网速迷你图：不足 3 个采样只画基线', () {
    expect(museSparkMinSamples, 3);
    final s = File('lib/features/muse/home/muse_home_page.dart').readAsStringSync();
    expect(s, contains('values.length < museSparkMinSamples'));
  });

  group('I6 / I8 / M13 资源', () {
    String md5ish(String p) => File(p).readAsBytesSync().fold<int>(0, (h, b) => (h * 31 + b) & 0x7fffffff).toString();

    test('托盘：未连接 / 深色 / 已连接 / 连接中 四张各不相同，pubspec 都列出', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final seen = <String>{};
      for (final n in ['tray_icon', 'tray_icon_dark', 'tray_icon_connected', 'tray_icon_connecting']) {
        for (final ext in ['png', 'ico']) {
          final p = 'assets/images/$n.$ext';
          expect(File(p).existsSync(), isTrue, reason: p);
          expect(pubspec, contains('- $p'));
          expect(seen.add(md5ish(p)), isTrue, reason: '$p 与其他托盘图标相同');
        }
      }
      expect(File('tool/gen_tray_icons.py').existsSync(), isTrue);
      final tray = File('lib/features/system_tray/notifier/system_tray_notifier.dart').readAsStringSync();
      expect(tray, contains('museTrayConnectingIco'));
    });

    test('assets/images/source 没有上游图标；splash 配置指向存在的图片且有深色底', () {
      for (final f in ['hiddify.ico', 'ic_launcher_border.png', 'ic_notify.png']) {
        expect(File('assets/images/source/$f').existsSync(), isFalse, reason: f);
      }
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final splash = pubspec.substring(pubspec.indexOf('\nflutter_native_splash:'));
      final image = RegExp(r'image: (\S+)').firstMatch(splash)!.group(1)!;
      expect(File(image).existsSync(), isTrue, reason: image);
      expect(splash, contains('color_dark: "#0B1222"'));
      for (final f in ['appimage', 'deb', 'rpm']) {
        final cfg = File('linux/packaging/$f/make_config.yaml').readAsStringSync();
        expect(cfg, isNot(contains('ic_launcher_border')), reason: f);
      }
    });

    test('原生启动页：Android 浅 / 深底色、iOS 深色背景已生成', () {
      final light = File('android/app/src/main/res/values-v31/styles.xml').readAsStringSync();
      final night = File('android/app/src/main/res/values-night-v31/styles.xml').readAsStringSync();
      expect(light, contains('windowSplashScreenBackground">#F6F8FC<'));
      expect(night, contains('windowSplashScreenBackground">#0B1222<'));
      expect(night, contains('@drawable/android12splash'));
      expect(File('android/app/src/main/res/drawable-night/background.png').existsSync(), isTrue);
      expect(File('android/app/src/main/res/drawable-night-v21/background.png').existsSync(), isTrue);
      expect(File('ios/Runner/Assets.xcassets/LaunchBackground.imageset/darkbackground.png').existsSync(), isTrue);
    });
  });

  test('版本 1.21.0：pubspec、更新说明 4 条、CHANGELOG.md', () {
    // 1.22.0 起不再是最新一条：版本号放宽到 1.2x
    expect(File('pubspec.yaml').readAsStringSync(), contains(RegExp(r'version: 1\.2\d\.\d+\+2\d\d')));
    expect(museChangelog.keys.toList().indexOf('1.21.0'), museChangelog.keys.toList().indexOf('1.20.5') - 1);
    final lines = museChangelog['1.21.0']!;
    expect(lines, hasLength(4));
    final all = lines.join();
    for (final w in ['涟漪', '定位环', '1.4 秒', '淡出', '同一城市', '圆角方形', '托盘', '启动页']) {
      expect(all, contains(w), reason: w);
    }
    for (final w in ['mihomo', 'Clash', 'sing-box', 'Hiddify', 'hiddify']) {
      expect(all.contains(w), isFalse, reason: w);
    }
    final md = File('CHANGELOG.md').readAsStringSync();
    expect(md, contains('### 1.21.0 - 2026-11-12'));
    expect(md.indexOf('### 1.21.0'), lessThan(md.indexOf('### 1.20.5')));
  });
}
