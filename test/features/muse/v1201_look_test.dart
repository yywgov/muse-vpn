// 穿云 1.20.1 B 三种首页风格（留白 / 细线 / 数字）与 C 后台省电（安卓后台停统计流、断开时补读最后流量）、
// 首页计时与网速块分块重绘。
// Part of 穿云 (GPLv3).
import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/traffic_recorder.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart' show museLinkedColor;
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/logic/stats_pause.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/settings/home_look_picker.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

class _Exit extends MuseExitNotifier {
  _Exit() : super(() => 0) {
    state = MuseExitResult(info: MuseExitInfo(ip: '45.76.112.9', country: 'NL'));
  }
}

class _Reach extends MuseReachNotifier {
  _Reach() : super(() => 0) {
    state = MuseReach.ok;
  }
}

OutboundInfo _node(String tag, String type, int delay) => OutboundInfo(tag: tag, tagDisplay: tag, type: type, urlTestDelay: delay);

OutboundGroup _group() => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '🇳🇱 荷兰·阿姆斯特丹-HY2',
  selectable: true,
  items: [
    _node('🇳🇱 荷兰·阿姆斯特丹-HY2', 'hysteria2', 236),
    _node('🇯🇵 东京 02 · 一个很长很长的节点名字用来测试大字号下的省略', 'vless', 86),
  ],
);

/// Stats pushed by a test (the home reads them through [museStatsProvider]).
final _stats = StateProvider<SystemInfo>(
  (ref) => SystemInfo(uplink: Int64(1024), downlink: Int64(2048), uplinkTotal: Int64(1), downlinkTotal: Int64(2)),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String? look,
  bool connected = true,
  Size size = const Size(412, 1400),
  double textScale = 1,
  bool dark = false,
  String accent = 'jingtailan',
  Widget page = const MuseHomePage(),
}) async {
  SharedPreferences.setMockInitialValues({'muse_home_look': ?look});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => sp),
      museConnectionProvider.overrideWithValue(AsyncData(connected ? const Connected() : const Disconnected())),
      museConnectPreparingProvider.overrideWith((ref) => false),
      museRunningProvider.overrideWithValue(connected),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue('VPS主力'),
      museAppVersionProvider.overrideWithValue(null),
      museSubInfoProvider.overrideWithValue(SubscriptionInfo(upload: 1, download: 2, total: 120 << 30, expire: DateTime(2027))),
      museStatsProvider.overrideWith((ref) => ref.watch(_stats)),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group())),
      museConnectedSinceProvider.overrideWith((ref) => connected ? DateTime.now() : null),
      museExitProvider.overrideWith((ref) => _Exit()),
      museReachProvider.overrideWith((ref) => _Reach()),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  museApplyAccent(accent);
  final theme = AppTheme(dark ? AppThemeMode.dark : AppThemeMode.light, 'Roboto');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme.lightTheme(null),
        darkTheme: theme.darkTheme(null),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 3));
  return container;
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  museApplyAccent('jingtailan');
}

void main() {
  group('B 首页风格：令牌', () {
    test('三种风格，默认留白；留白的取值就是 1.20.0 的 MuseHomeA', () {
      expect(MuseHomeLookKind.values.map((e) => e.title), ['留白', '细线', '数字']);
      expect(MuseHomeLook.fromKey(null), same(MuseHomeLook.airy));
      expect(MuseHomeLook.fromKey('奇怪的值'), same(MuseHomeLook.airy));
      expect(MuseHomeLook.fromKey('line'), same(MuseHomeLook.line));
      expect(MuseHomeLook.fromKey('number'), same(MuseHomeLook.number));
      const a = MuseHomeLook.airy;
      expect(a.radiusCard, MuseHomeA.radiusCard);
      expect(a.pad, MuseHomeA.pad);
      expect(a.value, MuseHomeA.value);
      expect(a.tile, MuseHomeA.tile);
      expect(a.buttonSize, MuseHomeA.button);
      expect(a.button, MuseHomeButton.circle);
      expect(MuseHomeLook.line.mergedGrid, isTrue);
      expect(MuseHomeLook.line.edge, MuseHomeEdge.line);
      expect(MuseHomeLook.number.uptime, 40);
      expect(MuseHomeLook.number.button, MuseHomeButton.pill);
      // 4 / 8 网格
      for (final l in [MuseHomeLook.airy, MuseHomeLook.line, MuseHomeLook.number]) {
        for (final v in [l.pad, l.padDesk, l.tilePadH, l.tilePadV, l.headTop, l.gap]) {
          expect(v % 4, 0, reason: '${l.kind} $v');
        }
      }
    });

    test('持久化：muse_home_look 默认 airy，随设置同步；外观里第一项；设置搜索能找到', () {
      final prefs = _src('lib/features/muse/data/muse_prefs.dart');
      expect(prefs, contains('"muse_home_look", "airy"'));
      expect(prefs, contains("  'muse_home_look',"));
      final page = _src('lib/features/muse/settings/appearance_page.dart');
      final first = page.indexOf('MuseSection(');
      expect(page.indexOf('MuseHomeLookPicker()'), greaterThan(first));
      // 1.20.3: 「深浅色」一行没有了，首页风格在「配色」之前
      expect(page.indexOf('MuseHomeLookPicker()'), lessThan(page.indexOf('MuseColorChoicePicker()')));
      final e = museSettingEntries.where((e) => e.title == '首页风格').single;
      expect(e.page, MuseSettingPage.appearance);
      expect(e.keywords, containsAll(['留白', '细线', '数字']));
    });

    test('无循环动画：首页风格相关源码没有 repeat / Timer.periodic', () {
      for (final f in ['lib/features/muse/settings/home_look_picker.dart', 'lib/features/muse/widget/muse_tokens_home.dart']) {
        final s = _src(f);
        expect(s, isNot(contains('.repeat(')), reason: f);
        expect(s, isNot(contains('Timer.periodic')), reason: f);
      }
    });
  });

  group('B 首页风格：首页', () {
    testWidgets('默认留白：56 连接钮（1.21.0：已连接为圆角方形）、没有状态小圆点、下方卡片各自分开', (tester) async {
      await _pump(tester);
      final shape = tester.widget<DecoratedBox>(find.byKey(const ValueKey('home_connect_shape')));
      expect((shape.decoration as ShapeDecoration).shape, isA<RoundedSuperellipseBorder>());
      expect(tester.getSize(find.byKey(const ValueKey('home_connect_shape'))), const Size.square(MuseHomeA.button));
      expect(find.byKey(const ValueKey('home_status_dot')), findsNothing);
      expect(find.byKey(const ValueKey('home_tiles_rule_1')), findsNothing);
      final hero = tester.widget<DecoratedBox>(find.byKey(const ValueKey('home_hero_card')));
      expect((hero.decoration as BoxDecoration).borderRadius, MuseHomeA.cardAll);
      await _done(tester);
    });

    testWidgets('细线：细线框连接卡、单行状态头带小圆点、40 方钮（点击区 48）、下方卡片合成一块分格面板、网速细柱', (tester) async {
      await _pump(tester, look: 'line');
      final hero = tester.widget<DecoratedBox>(find.byKey(const ValueKey('home_hero_card')));
      final heroShape = (hero.decoration as ShapeDecoration).shape as RoundedSuperellipseBorder;
      expect(heroShape.side.width, 1);
      expect(heroShape.borderRadius, MuseHomeLook.line.cardAll);
      expect(find.byKey(const ValueKey('home_status_dot')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('home_connect_shape'))), const Size.square(40));
      expect(tester.getSize(find.byKey(const ValueKey('home_connect_switch'))).width, greaterThanOrEqualTo(48));
      // 状态、时长、模式与按钮同一行
      final dot = tester.getCenter(find.byKey(const ValueKey('home_status_dot')));
      final timer = tester.getCenter(find.byKey(const ValueKey('home_timer')));
      final pill = tester.getCenter(find.byKey(const ValueKey('home_mode_pill')));
      final button = tester.getCenter(find.byKey(const ValueKey('home_connect_shape')));
      for (final c in [timer, pill, button]) {
        expect((c.dy - dot.dy).abs(), lessThan(6));
      }
      expect(find.byKey(const ValueKey('home_tiles_rule_1')), findsOneWidget);
      // the tiles draw no card of their own (one panel)
      final tiles = find.byKey(const ValueKey('home_tiles'));
      expect(tester.widget<DecoratedBox>(tiles).decoration, isA<ShapeDecoration>());
      expect(find.byKey(const ValueKey('speed_bars')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_node_caption')), findsOneWidget); // HY2 小标签
      await _done(tester);
    });

    testWidgets('数字：40 号已连接时长、药丸按钮写「断开」；未连接时「连接」是实心主色、时长位次要色 00:00:00', (tester) async {
      await _pump(tester, look: 'number');
      final timer = tester.widget<Text>(find.byKey(const ValueKey('home_timer')));
      expect(timer.style!.fontSize, 40);
      expect(timer.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(find.byKey(const ValueKey('home_connect_label')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('home_connect_label'))).data, '断开');
      expect(tester.getSize(find.byKey(const ValueKey('home_connect_shape'))).height, greaterThanOrEqualTo(44));
      await _done(tester);

      await _pump(tester, look: 'number', connected: false);
      expect(tester.widget<Text>(find.byKey(const ValueKey('home_connect_label'))).data, '连接');
      final ctx = tester.element(find.byKey(const ValueKey('home_connect_shape')));
      final scheme = Theme.of(ctx).colorScheme;
      final shape = tester.widget<DecoratedBox>(find.byKey(const ValueKey('home_connect_shape')));
      expect((shape.decoration as ShapeDecoration).color, scheme.primary);
      expect(find.byKey(const ValueKey('home_timer_idle')), findsOneWidget);
      await _done(tester);
    });

    testWidgets('切换即时生效：改设置后首页立刻换风格，无需重启，切换后没有常驻动画帧', (tester) async {
      final c = await _pump(tester);
      expect(find.byKey(const ValueKey('home_status_dot')), findsNothing);
      await c.read(MusePrefs.homeLook.notifier).update('line');
      await tester.pump();
      expect(find.byKey(const ValueKey('home_status_dot')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_tiles_rule_1')), findsOneWidget);
      await c.read(MusePrefs.homeLook.notifier).update('number');
      await tester.pump();
      expect(find.byKey(const ValueKey('home_connect_label')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      // only the once-a-second uptime ticks; no animation is left scheduling frames
      expect(tester.binding.transientCallbackCount, 0);
      await _done(tester);
    });

    for (final look in ['airy', 'line', 'number']) {
      testWidgets('$look：手机 320 / 412 × 1 / 1.3 / 2 倍字号 × 深浅色、电脑 800 / 880 / 1280 都不溢出', (tester) async {
        for (final dark in [false, true]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final w in [320.0, 412.0]) {
              for (final connected in [true, false]) {
                await _pump(tester, look: look, dark: dark, textScale: scale, size: Size(w, 2600), connected: connected);
                final e = tester.takeException();
                expect(e, isNull, reason: '$look $w ${scale}x dark=$dark connected=$connected ${e is FlutterError ? e.toStringDeep() : ''}');
                final status = tester.getRect(find.byKey(const ValueKey('home_status_block')));
                final card = tester.getRect(find.byKey(const ValueKey('home_connect_section')));
                expect(status.bottom, lessThanOrEqualTo(card.bottom));
                await _done(tester);
              }
            }
          }
        }
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          for (final w in [800.0, 880.0, 1280.0]) {
            for (final scale in [1.0, 2.0]) {
              await _pump(tester, look: look, textScale: scale, size: Size(w, 1600));
              expect(tester.takeException(), isNull, reason: '$look desk $w ${scale}x');
              await _done(tester);
            }
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('各色主题 × 深浅色：状态字、时长对卡片 ≥ 4.5:1，已连接色 ≥ 3:1，数字风格「连接」按钮文字 ≥ 4.5:1', (tester) async {
      for (final accent in MuseAccent.values) {
        for (final dark in [false, true]) {
          await _pump(tester, look: 'number', dark: dark, accent: accent.key, connected: false);
          final ctx = tester.element(find.byKey(const ValueKey('home_connect_shape')));
          final mt = MuseTheme.of(ctx);
          final scheme = Theme.of(ctx).colorScheme;
          expect(museContrast(mt.text1, mt.card), greaterThanOrEqualTo(4.5), reason: '${accent.key} $dark');
          expect(museContrast(mt.text2, mt.card), greaterThanOrEqualTo(4.5), reason: '${accent.key} $dark');
          expect(museContrast(museLinkedColor(scheme, mt.card), mt.card), greaterThanOrEqualTo(3), reason: '${accent.key} $dark');
          final label = tester.widget<Text>(find.byKey(const ValueKey('home_connect_label')));
          expect(museContrast(label.style!.color!, scheme.primary), greaterThanOrEqualTo(4.5), reason: '${accent.key} $dark');
          await _done(tester);
        }
      }
    });
  });

  group('B 首页风格：设置', () {
    // 1.20.3: 四张（+ 经典），没有说明句；首页风格之后是「配色」
    testWidgets('外观第一块「首页风格」四张预览，点一下立即保存并生效；读屏有名字与选中状态', (tester) async {
      final c = await _pump(tester, page: const MuseAppearancePage(android: false, windows: false), size: const Size(412, 1200));
      expect(find.byType(MuseHomeLookPicker), findsOneWidget);
      expect(find.byType(MuseHomeLookPreview), findsNWidgets(4));
      final picker = tester.getRect(find.byKey(const ValueKey('appearance_home_look')));
      final theme = tester.getRect(find.byKey(const ValueKey('appearance_color_choice')));
      expect(picker.bottom, lessThan(theme.top));
      final sem = tester.widget<Semantics>(
        find.ancestor(of: find.byKey(const ValueKey('home_look_airy')), matching: find.byType(Semantics)).first,
      );
      expect(sem.properties.label, '首页风格 留白');
      expect(sem.properties.selected, isTrue);
      expect(sem.properties.button, isTrue);
      await tester.tap(find.byKey(const ValueKey('home_look_number')));
      await tester.pump();
      expect(c.read(MusePrefs.homeLook), 'number');
      expect(c.read(museHomeLookProvider), same(MuseHomeLook.number));
      expect(find.byKey(const ValueKey('home_look_describe')), findsNothing); // 1.20.3: 说明句去掉
      await _done(tester);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('预览在 320 宽 ${scale}x 字号、深浅色下不溢出', (tester) async {
        for (final dark in [false, true]) {
          await _pump(tester, page: const MuseAppearancePage(android: false, windows: false), size: const Size(320, 1600), textScale: scale, dark: dark);
          expect(tester.takeException(), isNull);
          await _done(tester);
        }
      });
    }
  });

  group('C 首页分块重绘', () {
    testWidgets('新的网速读数只重建数字，不重建卡片外壳；计时与网速图各有自己的重绘层', (tester) async {
      final c = await _pump(tester);
      final before = museTileShellBuilds;
      for (var i = 1; i <= 5; i++) {
        c.read(_stats.notifier).state = SystemInfo(
          uplink: Int64(1024 * i),
          downlink: Int64(4096 * i),
          uplinkTotal: Int64(1000 * i),
          downlinkTotal: Int64(9000 * i),
        );
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(museTileShellBuilds - before, 0);
      expect(find.textContaining('20.0', findRichText: true), findsWidgets); // ↓ 4096 × 5
      final timer = find.byKey(const ValueKey('home_timer'));
      expect(find.ancestor(of: timer, matching: find.byType(RepaintBoundary)).evaluate().isNotEmpty, isTrue);
      final rb = tester.renderObject(find.ancestor(of: timer, matching: find.byType(RepaintBoundary)).first);
      expect((rb as RenderRepaintBoundary).isRepaintBoundary, isTrue);
      await _done(tester);
    });

    test('源码：网速 / 本次流量 / 流量卡外壳不直接读统计', () {
      final s = _src('lib/features/muse/home/muse_home_page.dart');
      for (final cls in ['_SpeedTile', '_TrafficTile', '_FlowTile']) {
        final start = s.indexOf('class $cls extends');
        final end = s.indexOf('\nclass ', start + 10);
        expect(s.substring(start, end), isNot(contains('ref.watch(museStatsProvider)')), reason: cls);
      }
    });
  });

  group('C 安卓后台停统计流', () {
    test('只在安卓、应用不在前台（paused / hidden / detached）时关；inactive（下拉通知栏）不关', () {
      for (final s in AppLifecycleState.values) {
        final expected = s == AppLifecycleState.paused || s == AppLifecycleState.hidden || s == AppLifecycleState.detached;
        expect(museStatsPausedFor(pauseEnabled: true, state: s), expected, reason: '$s');
        expect(museStatsPausedFor(pauseEnabled: false, state: s), isFalse, reason: '$s');
      }
      expect(museStatsPausedFor(pauseEnabled: true, state: null), isFalse);
    });

    testWidgets('后台时统计流不再发读数、保留最后一条（不变 0）；回到前台重新打开', (tester) async {
      var opened = 0;
      final paused = StateProvider<bool>((ref) => false);
      final container = ProviderContainer(
        overrides: [
          serviceRunningProvider.overrideWithValue(true),
          museStatsPausedProvider.overrideWith((ref) => ref.watch(paused)),
          statsNotifierProvider.overrideWith(() => _FakeStats(() => opened++)),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(museStatsProvider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 1500));
      expect(opened, 1);
      final last = container.read(museStatsProvider).downlinkTotal.toInt();
      expect(last, greaterThan(0));
      container.read(paused.notifier).state = true;
      await tester.pump(const Duration(seconds: 3));
      expect(container.read(museStatsProvider).downlinkTotal.toInt(), last, reason: 'held, not zero');
      expect(opened, 1, reason: 'no stream while paused');
      container.read(paused.notifier).state = false;
      await tester.pump(const Duration(milliseconds: 1500));
      expect(opened, 2);
      expect(container.read(museStatsProvider).downlinkTotal.toInt(), greaterThan(last));
      sub.close();
      container.dispose();
      await tester.pump(const Duration(seconds: 1));
    });

    test('今日流量：回到前台的第一条读数补上后台期间的流量（按总量差）', () async {
      final f = await _Recorder.start();
      f.push(up: 100, down: 1000);
      f.push(up: 200, down: 3000); // +100 / +2000
      f.paused = true; // background: no readings for a while
      f.paused = false;
      f.push(up: 900, down: 15000); // +700 / +12000 counted on the first reading back
      f.stopAndFlush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(f.today(), (800, 14000));
      f.dispose();
    });

    test('后台期间断开：断开那一刻向内核读一次总量补上最后一段，不少算；读不到则不编', () async {
      final f = await _Recorder.start();
      f.push(up: 100, down: 1000);
      f.push(up: 200, down: 3000);
      f.paused = true;
      f.finalReading = SystemInfo(uplinkTotal: Int64(500), downlinkTotal: Int64(9000));
      f.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(f.reads, 1);
      expect(f.today(), (400, 8000)); // 100 + 300 / 2000 + 6000
      f.dispose();

      final g = await _Recorder.start();
      g.push(up: 100, down: 1000);
      g.push(up: 200, down: 3000);
      g.paused = true;
      g.finalReading = null; // the core did not answer
      g.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(g.today(), (100, 2000));
      g.dispose();
    });

    test('前台断开不额外读；重开统计流时的空读数（全 0）不让下一条被当成新会话重复计', () async {
      final f = await _Recorder.start();
      f.push(up: 100, down: 1000);
      f.push(up: 200, down: 3000);
      f.push(up: 0, down: 0); // a reopened stream's empty reading
      f.push(up: 250, down: 3500);
      f.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(f.reads, 0);
      expect(f.today(), (150, 2500));
      f.dispose();
    });

    test('计数器副本与空读数判断', () {
      final c = MuseTrafficCounter()..delta(10, 20);
      final copy = c.copy();
      expect(copy.primed, isTrue);
      expect(c.isGap(0, 0), isTrue);
      expect(MuseTrafficCounter().isGap(0, 0), isFalse);
      expect(museFinalStatsDelta(copy, 15, 40), (5, 20));
      expect(c.delta(12, 25), (2, 5), reason: 'the copy is independent');
    });

    test('源码：统计流在后台时返回不发读数的流；首页读 valueOrNull（保留最后一条）', () {
      expect(_src('lib/features/stats/notifier/stats_notifier.dart'), contains('ref.watch(museStatsPausedProvider)'));
      expect(_src('lib/features/muse/home/home_data.dart'), contains('statsNotifierProvider).valueOrNull'));
      expect(_src('lib/features/muse/logic/stats_pause.dart'), isNot(contains('Timer')));
    });
  });
}

class _FakeStats extends StatsNotifier {
  _FakeStats(this.onOpen);

  final void Function() onOpen;

  /// grows across streams (the core's session total)
  static int total = 0;

  @override
  Stream<SystemInfo> build() {
    if (ref.watch(museStatsPausedProvider)) {
      final held = StreamController<SystemInfo>();
      ref.onDispose(held.close);
      return held.stream;
    }
    onOpen();
    return Stream.periodic(const Duration(milliseconds: 300), (_) {
      total += 1000;
      return SystemInfo(downlinkTotal: Int64(total));
    }).take(4);
  }
}

/// The traffic recorder with pushed readings, a pausable stream and a scripted final reading.
class _Recorder {
  _Recorder._(this.container, this.stats, this.running, this.conn, this.pausedState);

  final ProviderContainer container;
  final StateProvider<SystemInfo> stats;
  final StateProvider<bool> running;
  final StateProvider<AsyncValue<ConnectionStatus>> conn;
  final StateProvider<bool> pausedState;
  SystemInfo? finalReading;
  int reads = 0;

  static Future<_Recorder> start() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final stats = StateProvider<SystemInfo>((ref) => SystemInfo());
    final running = StateProvider<bool>((ref) => false);
    final conn = StateProvider<AsyncValue<ConnectionStatus>>((ref) => const AsyncData(Disconnected()));
    final pausedState = StateProvider<bool>((ref) => false);
    late _Recorder r;
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => sp),
        museStatsProvider.overrideWith((ref) => ref.watch(stats)),
        museRunningProvider.overrideWith((ref) => ref.watch(running)),
        museConnectionProvider.overrideWith((ref) => ref.watch(conn)),
        museStatsPausedProvider.overrideWith((ref) => ref.watch(pausedState)),
        museStatsReadOnceProvider.overrideWithValue(() async {
          r.reads++;
          return r.finalReading;
        }),
      ],
    );
    await c.read(sharedPreferencesProvider.future);
    r = _Recorder._(c, stats, running, conn, pausedState);
    c.listen(museTrafficRecorderProvider, (_, _) {});
    // connect: a new session starts at 0
    c.read(running.notifier).state = true;
    c.read(conn.notifier).state = const AsyncData(Connected());
    r._sync();
    return r;
  }

  /// let the container deliver the change to the recorder's listeners
  void _sync() {
    container.read(museStatsProvider);
    container.read(museConnectionProvider);
    container.read(museRunningProvider);
    container.read(museStatsPausedProvider);
  }

  set paused(bool v) {
    container.read(pausedState.notifier).state = v;
    _sync();
  }

  void push({required int up, required int down}) {
    container.read(stats.notifier).state = SystemInfo(uplinkTotal: Int64(up), downlinkTotal: Int64(down));
    _sync();
  }

  void disconnect() {
    container.read(conn.notifier).state = const AsyncData(Disconnected());
    container.read(museConnectionProvider);
    container.read(running.notifier).state = false;
    _sync();
  }

  void stopAndFlush() => disconnect();

  (int, int) today() => MuseTrafficLog.parse(container.read(MusePrefs.trafficLog)).days[museDayKey(DateTime.now())] ?? (0, 0);

  void dispose() => container.dispose();
}
