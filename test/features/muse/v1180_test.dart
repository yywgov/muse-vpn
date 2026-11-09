// 穿云 1.18.0「动效基础 + 字体」: P0 页面转场缓动与动效令牌, P6 动效三档（标准/精简/关闭，跟随系统
// 移除动画与 Android 省电模式）, P2 连接按钮形变, P3 数字遮罩滚动与等待态扫光, P7 内置西文/数字字体.
// Part of 穿云 (GPLv3).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/go_router/helper/custom_transition.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/motion_level.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart' show MuseStartButton, museSwitchSweepTimeout;
import 'package:hiddify/features/muse/widget/muse_motion.dart';
import 'package:hiddify/features/muse/widget/muse_motion_widgets.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart' show MuseFont, MuseSize;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

/// [child] under a 动效 level (and optionally the system 「移除动画」).
Widget _app(Widget child, {MuseMotionLevel level = MuseMotionLevel.standard, bool systemOff = false}) => MaterialApp(
  builder: (ctx, c) => MediaQuery(
    data: MediaQuery.of(ctx).copyWith(disableAnimations: systemOff),
    child: Builder(builder: (ctx) => museWrapMotion(ctx, level, c!)),
  ),
  home: Scaffold(body: Center(child: child)),
);

class _Roll extends StatefulWidget {
  const _Roll();

  @override
  State<_Roll> createState() => _RollState();
}

class _RollState extends State<_Roll> {
  int v = 1;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => v++),
    child: MuseRoll(value: v, child: Text('$v ms', key: const ValueKey('roll_text'))),
  );
}

void main() {
  group('P0 动效令牌', () {
    test('主曲线、时长、弹簧', () {
      expect(MuseMotion.curve, const Cubic(0.32, 0.86, 0.22, 1.0));
      expect(MuseMotion.enter.inMilliseconds, inInclusiveRange(350, 400));
      expect(MuseMotion.exit.inMilliseconds, 200);
      expect(MuseMotion.feedback.inMilliseconds, 150);
      expect(MuseMotion.pressFeedback, MuseMotion.feedback);
      expect(MuseMotion.tabCurve, MuseMotion.curve);
      // 无回弹弹簧不过冲；「到达」弹簧轻回弹（< 5%）
      expect(MuseMotion.smoothCurve.peak, lessThanOrEqualTo(1.001));
      expect(MuseMotion.arriveCurve.peak, greaterThan(1.005));
      expect(MuseMotion.arriveCurve.peak, lessThan(1.05));
      for (final c in [MuseMotion.smoothCurve, MuseMotion.arriveCurve]) {
        expect(c.transform(0), 0);
        expect(c.transform(1), 1);
        expect(c.settleDuration.inMilliseconds, inInclusiveRange(150, 700));
      }
      expect(MuseMotion.curve.transform(0.5), greaterThan(0.8)); // fast start, long soft end
    });

    test('数字滚动与扫光参数', () {
      // 1.19.1 动效审查：MuseRoll 总长 510 → 300ms（出 180、延迟 40、入 260）
      expect(MuseMotion.maskOut.inMilliseconds, 180);
      expect(MuseMotion.maskIn.inMilliseconds, 260);
      expect(MuseMotion.maskInDelay.inMilliseconds, 40);
      expect(MuseMotion.sweep.inMilliseconds, 1100);
      expect(MuseMotion.sweepTimeout, lessThanOrEqualTo(const Duration(minutes: 1)));
    });

    test('页面转场不再是线性', () {
      final s = _src('lib/core/router/go_router/helper/custom_transition.dart');
      // 1.19.1 动效审查：页面进场改用页面令牌 MuseMotion.page（300ms）
      expect(s, contains('transitionDuration: MuseMotion.page'));
      expect(s, contains('reverseTransitionDuration: MuseMotion.exit'));
      expect(s, isNot(contains('milliseconds: 150')));
      final a = AnimationController(vsync: const TestVSync(), duration: MuseMotion.enter);
      addTearDown(a.dispose);
      final c = museTransitionCurve(a);
      expect(c.curve, MuseMotion.curve);
      expect(c.reverseCurve, isNotNull);
      a.value = 0.5;
      expect(c.value, closeTo(MuseMotion.curve.transform(0.5), 1e-9));
      expect(c.value, isNot(closeTo(0.5, 0.05)));
    });

    testWidgets('每档转场：标准滑入、精简淡入、关闭无动画', (tester) async {
      final a = AnimationController(vsync: const TestVSync(), duration: MuseMotion.enter);
      addTearDown(a.dispose);
      const child = SizedBox(key: ValueKey('page'));
      expect(museTransition(TransitionType.slide, MuseMotionLevel.standard, a, child, TextDirection.ltr), isA<SlideTransition>());
      expect(museTransition(TransitionType.slide, MuseMotionLevel.reduced, a, child, TextDirection.ltr), isA<FadeTransition>());
      expect(identical(museTransition(TransitionType.slide, MuseMotionLevel.off, a, child, TextDirection.ltr), child), isTrue);
    });
  });

  group('P6 动效三档', () {
    test('档位规则', () {
      MuseMotionLevel r(MuseMotionChoice c, {bool sys = false, bool ps = false}) =>
          museResolveMotionLevel(choice: c, systemDisable: sys, powerSave: ps);
      expect(r(MuseMotionChoice.auto), MuseMotionLevel.standard);
      expect(r(MuseMotionChoice.auto, ps: true), MuseMotionLevel.reduced);
      expect(r(MuseMotionChoice.auto, sys: true), MuseMotionLevel.off);
      expect(r(MuseMotionChoice.standard, ps: true), MuseMotionLevel.standard);
      expect(r(MuseMotionChoice.standard, sys: true), MuseMotionLevel.off); // 系统移除动画永远优先
      expect(r(MuseMotionChoice.reduced), MuseMotionLevel.reduced);
      expect(r(MuseMotionChoice.off), MuseMotionLevel.off);
      expect(MuseMotionChoice.fromKey('?'), MuseMotionChoice.auto);
      expect([for (final c in MuseMotionChoice.values) c.title], ['跟随系统', '标准', '精简', '关闭']);
    });

    test('时长：关闭为 0，精简 ×0.6', () {
      const d = Duration(milliseconds: 400);
      expect(museScaleDuration(MuseMotionLevel.standard, d), d);
      expect(museScaleDuration(MuseMotionLevel.reduced, d), const Duration(milliseconds: 240));
      expect(museScaleDuration(MuseMotionLevel.off, d), Duration.zero);
    });

    testWidgets('界面读到的档位（系统移除动画优先）', (tester) async {
      Future<BuildContext> at(MuseMotionLevel level, {bool sys = false}) async {
        await tester.pumpWidget(_app(const SizedBox(key: ValueKey('probe')), level: level, systemOff: sys));
        return tester.element(find.byKey(const ValueKey('probe')));
      }

      var c = await at(MuseMotionLevel.standard);
      expect(museMotionLevel(c), MuseMotionLevel.standard);
      expect(museMotion(c), MuseMotion.fast);
      expect(museMotionRich(c), isTrue);
      c = await at(MuseMotionLevel.reduced);
      expect(museMotion(c), MuseMotion.fast * 0.6);
      expect(museCurve(c), MuseMotion.plainCurve);
      expect(museMotionRich(c), isFalse);
      expect(museReduceMotion(c), isFalse);
      c = await at(MuseMotionLevel.off);
      expect(museReduceMotion(c), isTrue);
      expect(museMotion(c), Duration.zero);
      // 「关闭」也告诉 Flutter 自带控件
      expect(MediaQuery.disableAnimationsOf(c), isTrue);
      c = await at(MuseMotionLevel.standard, sys: true);
      expect(museMotionLevel(c), MuseMotionLevel.off);
    });

    Future<ProviderContainer> container(StreamController<Object?> power, {String? choice}) async {
      SharedPreferences.setMockInitialValues({if (choice != null) 'muse_motion_level': choice});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => sp),
          musePowerSaveEventsProvider.overrideWithValue(power.stream),
        ],
      );
      await c.read(sharedPreferencesProvider.future);
      addTearDown(c.dispose);
      return c;
    }

    test('省电模式降为精简（事件推送，跟随系统时）', () async {
      final power = StreamController<Object?>.broadcast();
      addTearDown(power.close);
      final c = await container(power);
      final sub = c.listen(museAppMotionLevelProvider, (_, _) {});
      addTearDown(sub.close);
      expect(c.read(MusePrefs.motionLevel), 'auto');
      expect(c.read(museAppMotionLevelProvider), MuseMotionLevel.standard);
      power.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(museAppMotionLevelProvider), MuseMotionLevel.reduced);
      power.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(museAppMotionLevelProvider), MuseMotionLevel.standard);
    });

    test('手动选档后不再订阅省电事件', () async {
      final power = StreamController<Object?>.broadcast();
      addTearDown(power.close);
      final c = await container(power, choice: 'standard');
      final sub = c.listen(museAppMotionLevelProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      expect(power.hasListener, isFalse);
      power.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(museAppMotionLevelProvider), MuseMotionLevel.standard);
      await c.read(MusePrefs.motionLevel.notifier).update('off');
      expect(c.read(museAppMotionLevelProvider), MuseMotionLevel.off);
      await c.read(MusePrefs.motionLevel.notifier).update('auto');
      await Future<void>.delayed(Duration.zero);
      expect(power.hasListener, isTrue);
    });

    test('Android 省电模式：动态注册广播、不轮询、构造时不碰 Context', () {
      final k = _src('android/app/src/main/kotlin/com/hiddify/hiddify/bg/ChuanyunPowerWatch.kt');
      expect(k, contains('ACTION_POWER_SAVE_MODE_CHANGED'));
      expect(k, contains('ContextCompat.registerReceiver'));
      expect(k, contains('unregisterReceiver'));
      expect(k, contains('isPowerSaveMode'));
      expect(k, isNot(contains('Timer')));
      expect(k, isNot(contains('postDelayed')));
      expect(k, contains('class ChuanyunPowerWatch(private val contextOf: () -> Context)'));
      final h = _src('android/app/src/main/kotlin/com/hiddify/hiddify/ChuanyunHandler.kt');
      expect(h, contains('ChuanyunPowerWatch.channelName'));
      expect(h, contains('powerWatch.unregister()'));
      expect(_src('lib/features/muse/data/motion_level.dart'), contains("'com.chuanyun.app/power'"));
    });

    test('外观 › 动效 与设置搜索', () {
      final page = _src('lib/features/muse/settings/appearance_page.dart');
      expect(page, contains('const MuseMotionTile()'));
      expect(page, contains("ValueKey('appearance_motion')"));
      expect(page, contains('MusePrefs.motionLevel.notifier'));
      expect(_src('lib/features/muse/logic/settings_index.dart'), contains("MuseSettingEntry('动效'"));
      expect(_src('lib/features/app/widget/app.dart'), contains('museWrapMotion(context, motionLevel, child)'));
    });

    test('订阅更新不再转圈（尊重移除动画）', () {
      final s = _src('lib/features/profile/widget/profile_tile.dart');
      expect(s, isNot(contains('.repeat(')));
      expect(s, isNot(contains('RotationTransition')));
      expect(s, contains("ValueKey('profile_updating_sweep')"));
    });

    test('首页不再有循环光带；所有新动画无 repeat 之外的循环', () {
      final home = _src('lib/features/muse/home/muse_home_page.dart');
      expect(home, isNot(contains('_Shimmer')));
      final w = _src('lib/features/muse/widget/muse_motion_widgets.dart');
      expect('.repeat('.allMatches(w).length, 1); // only MuseSweep, bounded by its timeout
      expect(w, contains('Timer(widget.timeout'));
    });
  });

  group('P2 连接按钮形变', () {
    double radius(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byKey(const ValueKey('home_connect_shape')), matching: find.byType(DecoratedBox)).first,
      );
      final shape = (box.decoration as ShapeDecoration).shape as RoundedSuperellipseBorder;
      return (shape.borderRadius as BorderRadius).topLeft.x;
    }

    Widget button(bool on, MuseMotionLevel level) =>
        _app(MuseStartButton(key: const ValueKey('b'), on: on, onBrand: false, onTap: () {}, semanticLabel: '连接'), level: level);

    testWidgets('标准：圆 → 圆角方形，弹簧一次性完成，内容独立交叉淡入', (tester) async {
      await tester.pumpWidget(button(false, MuseMotionLevel.standard));
      expect(radius(tester), MuseStartButton.radiusOff);
      expect(MuseStartButton.radiusOff, MuseSize.startButton / 2);
      await tester.pumpWidget(button(true, MuseMotionLevel.standard));
      await tester.pump(const Duration(milliseconds: 60));
      final mid = radius(tester);
      expect(mid, lessThan(MuseStartButton.radiusOff));
      expect(mid, greaterThan(MuseStartButton.radiusOn));
      // the glyph cross-fades on its own (both icons present mid-way)
      expect(find.byIcon(Icons.pause_outlined), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
      await tester.pumpAndSettle();
      expect(radius(tester), closeTo(MuseStartButton.radiusOn, 0.01));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.byIcon(Icons.play_arrow_outlined), findsNothing);
    });

    testWidgets('关闭档：直接终态，无动画帧', (tester) async {
      await tester.pumpWidget(button(false, MuseMotionLevel.off));
      await tester.pumpWidget(button(true, MuseMotionLevel.off));
      await tester.pump();
      expect(radius(tester), MuseStartButton.radiusOn);
      expect(find.byIcon(Icons.play_arrow_outlined), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('精简档：无回弹、时长缩短', (tester) async {
      await tester.pumpWidget(button(false, MuseMotionLevel.reduced));
      await tester.pumpWidget(button(true, MuseMotionLevel.reduced));
      var min = 100.0;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final r = radius(tester);
        if (r < min) min = r;
      }
      expect(min, greaterThanOrEqualTo(MuseStartButton.radiusOn - 0.01)); // never past the target
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('P3 数字遮罩滚动', () {
    testWidgets('标准：旧字上滑出、新字延迟滑入，300ms 内结束（1.19.1 起，原 510ms）', (tester) async {
      await tester.pumpWidget(_app(const _Roll()));
      expect(find.text('1 ms'), findsOneWidget);
      await tester.tap(find.byType(_Roll));
      await tester.pump();
      expect(MuseRoll.debugRolling, 1);
      expect(find.text('1 ms'), findsOneWidget); // the old one is still sliding out
      expect(find.text('2 ms'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 30)); // new text has not started (40ms delay, 1.19.1)
      final inSlide = tester.widget<SlideTransition>(
        find.ancestor(of: find.text('2 ms'), matching: find.byType(SlideTransition)).first,
      );
      expect(inSlide.position.value.dy, 1.0);
      await tester.pump(const Duration(milliseconds: 440));
      await tester.pump();
      expect(MuseRoll.debugRolling, 0);
      expect(find.text('1 ms'), findsNothing);
      expect(find.descendant(of: find.byType(MuseRoll), matching: find.byType(SlideTransition)), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    for (final level in [MuseMotionLevel.reduced, MuseMotionLevel.off]) {
      testWidgets('${level.name}：直接替换，不滚动', (tester) async {
        await tester.pumpWidget(_app(const _Roll(), level: level));
        await tester.tap(find.byType(_Roll));
        await tester.pump();
        expect(MuseRoll.debugRolling, 0);
        expect(find.text('1 ms'), findsNothing);
        expect(find.text('2 ms'), findsOneWidget);
        expect(find.descendant(of: find.byType(MuseRoll), matching: find.byType(SlideTransition)), findsNothing);
        await tester.pumpAndSettle();
      });
    }

    test('首页节点名与延迟滚动、使用等宽数字；实时速率不滚动', () {
      final home = _src('lib/features/muse/home/muse_home_page.dart');
      expect(home, contains('value: text,'));
      expect(home, contains('value: delay,'));
      expect(home, contains("ValueKey('home_node_name')"));
      // MuseRoll is used only for the node name and its delay on 首页 (not for per-second numbers)
      expect('MuseRoll('.allMatches(home).length, 2);
      expect(_src('lib/features/muse/widget/muse_tokens.dart'), contains('static const tabular = [FontFeature.tabularFigures()];'));
    });
  });

  group('P3 等待态扫光', () {
    Widget sweep({bool active = true, Duration timeout = const Duration(seconds: 2)}) =>
        MuseSweep(active: active, timeout: timeout, child: const Text('停止'));

    testWidgets('标准：运行扫光，超时后停在静态文字', (tester) async {
      await tester.pumpWidget(_app(sweep()));
      expect(MuseSweep.debugRunning, 1);
      expect(find.byKey(const ValueKey('muse_sweep_mask')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(MuseSweep.debugRunning, 0);
      expect(find.byKey(const ValueKey('muse_sweep_mask')), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('等待结束即停；再次等待重新开始', (tester) async {
      await tester.pumpWidget(_app(sweep()));
      expect(MuseSweep.debugRunning, 1);
      await tester.pumpWidget(_app(sweep(active: false)));
      expect(MuseSweep.debugRunning, 0);
      await tester.pumpAndSettle(); // nothing left running
      await tester.pumpWidget(_app(sweep()));
      expect(MuseSweep.debugRunning, 1);
      await tester.pumpWidget(_app(const SizedBox()));
      expect(MuseSweep.debugRunning, 0);
    });

    testWidgets('页面不可见时不出帧', (tester) async {
      await tester.pumpWidget(_app(TickerMode(enabled: false, child: sweep())));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(_app(const SizedBox()));
    });

    for (final level in [MuseMotionLevel.reduced, MuseMotionLevel.off]) {
      testWidgets('${level.name}（含省电模式降级）：静态文字，无动画', (tester) async {
        await tester.pumpWidget(_app(sweep(), level: level));
        expect(MuseSweep.debugRunning, 0);
        expect(find.byKey(const ValueKey('muse_sweep_mask')), findsNothing);
        expect(find.text('停止'), findsOneWidget);
        await tester.pumpAndSettle(); // would time out if anything kept animating
      });
    }

    test('扫光代替转圈：切节点、测速、更新订阅、连接中', () {
      final nodes = _src('lib/features/muse/nodes/node_list.dart');
      expect(nodes, contains("ValueKey('node_test_sweep')"));
      expect(nodes, isNot(contains('CircularProgressIndicator')));
      final home = _src('lib/features/muse/home/muse_home_page.dart');
      expect(home, contains('active: switching != null'));
      expect(home, contains('active: link == MuseLinkState.connecting'));
      expect(museSwitchSweepTimeout, lessThanOrEqualTo(const Duration(seconds: 30)));
      final mem = _src('lib/features/muse/home/node_memory.dart');
      expect(mem, contains('museNodeSwitchingProvider'));
      expect(mem, contains('finally'));
    });
  });

  group('P7 字体', () {
    test('内置 Inter（SIL OFL，精简子集）', () {
      final pub = _src('pubspec.yaml');
      expect(pub, contains('family: MuseSans'));
      var total = 0;
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        expect(pub, contains('assets/fonts/MuseSans-$w.ttf'));
        final f = File('assets/fonts/MuseSans-$w.ttf');
        total += f.lengthSync();
        // the tabular-figures feature survived the subset
        expect(String.fromCharCodes(f.readAsBytesSync()).contains('tnum'), isTrue, reason: w);
      }
      expect(total, lessThan(1024 * 1024));
      final ofl = _src('assets/fonts/OFL-Inter.txt');
      expect(ofl, contains('SIL Open Font License, Version 1.1'));
      expect(ofl, contains('The Inter Project Authors'));
      expect(pub, contains('- assets/fonts/OFL-Inter.txt'));
      expect(_src('THIRD_PARTY_NOTICES.md'), contains('SIL Open Font License 1.1'));
      expect(_src('lib/features/about/widget/open_source_page.dart'), contains("ValueKey('about_credit_font')"));
      // no OPPO Sans anywhere in the assets
      for (final f in Directory('assets/fonts').listSync()) {
        expect(f.path.toLowerCase(), isNot(contains('oppo')));
      }
    });

    // 1.19.2：中文不再回退系统字体，而是回退内置思源黑体（MuseFont.fallback），断言随改
    test('大号数字与节点名用内置字体，中文回退内置思源黑体', () {
      expect(MuseFont.family, 'MuseSans');
      final tokens = _src('lib/features/muse/widget/muse_tokens.dart');
      expect(tokens, contains('fontFamily: MuseFont.family,\n    fontFamilyFallback: MuseFont.fallback,\n    fontSize: numberSize,'));
      // glyphs outside the subset (Chinese) use the bundled Chinese face, not the system font
      expect(MuseFont.fallback.first, MuseFont.cjk);
      expect('fontFamily: MuseFont.family'.allMatches(_src('lib/features/muse/nodes/node_rows.dart')).length, 4);
      expect('fontFamily: MuseFont.family'.allMatches(_src('lib/features/muse/home/muse_home_page.dart')).length, 2);
    });
  });

  group('版本 1.18.0', () {
    test('pubspec, changelog, CHANGELOG.md', () {
      // 1.19.0 and later: the 1.18.0 notes stay in the changelog, the version only moves forward
      expect(_src('pubspec.yaml'), contains('version: 1.1'));
      expect(museChangelog.keys, contains('1.18.0'));
      expect(museChangelog.keys.toList().indexOf('1.18.0'), lessThan(museChangelog.keys.toList().indexOf('1.17.1')));
      expect(museChangelog['1.18.0']!.join(), contains('动效'));
      expect(_src('CHANGELOG.md'), contains('### 1.18.0'));
    });
  });
}
