// 穿云 1.19.1 第 2 段：电脑版界面 A1–A10——地图限高、点阵加深（按逻辑像素、最小点径）、地图上的城市名与
// 13 号图注、首页按窗口宽度分栏、桌面连接卡、桌面首页工具行、侧栏、标题栏、统一标题与内容宽度、悬停 / 焦点。
// 窗口 < 900 时首页保持 1.19.0 的单栏（手机布局）。
// Part of 穿云 (GPLv3).
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/desktop/title_bar.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_card.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/hiddifycore/generated/google/protobuf/timestamp.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class _Exit extends MuseExitNotifier {
  _Exit() : super(() => 0) {
    state = const MuseExitResult(info: MuseExitInfo(ip: '45.76.112.9', country: 'JP'));
  }
}

class _Reach extends MuseReachNotifier {
  _Reach() : super(() => 0) {
    state = MuseReach.ok;
  }
}

class _Ops implements MuseWindowOps {
  @override
  Future<void> close() async {}
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<void> maximize() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> setAlwaysOnTop(bool on) async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> unmaximize() async {}
}

const _longName = '🇯🇵 日本东京 IPLC 专线 08 | 0.5x 倍率 | 解锁流媒体 | 限速 300M | 备用线路（家宽）';

OutboundInfo _node(String tag, String type, int delay) =>
    OutboundInfo(tag: tag, tagDisplay: tag, type: type, urlTestDelay: delay, urlTestTime: Timestamp.fromDateTime(DateTime.now()));

OutboundGroup _group(String selected) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: selected,
  selectable: true,
  items: [_node('🇯🇵 东京 02', 'vless', 86), _node('🇭🇰 香港 01', 'hysteria2', 42), _node(_longName, 'vless', 120)],
);

Future<ProviderContainer> _pumpHome(
  WidgetTester tester,
  Size size, {
  bool connected = true,
  String selected = '🇯🇵 东京 02',
  String profileName = '机场订阅',
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => sp),
      museConnectionProvider.overrideWithValue(AsyncData(connected ? const Connected() : const Disconnected())),
      museConnectPreparingProvider.overrideWith((ref) => false),
      museRunningProvider.overrideWithValue(connected),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p1'),
      museActiveProfileNameProvider.overrideWithValue(profileName),
      museAppVersionProvider.overrideWithValue(null),
      museSubInfoProvider.overrideWithValue(
        SubscriptionInfo(upload: 1, download: 2, total: 1024 * 1024 * 1024, expire: DateTime(2027)),
      ),
      museStatsProvider.overrideWithValue(
        SystemInfo(uplink: Int64(1024), downlink: Int64(2048), uplinkTotal: Int64(1), downlinkTotal: Int64(2)),
      ),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group(selected))),
      museConnectedSinceProvider.overrideWith((ref) => connected ? DateTime.now() : null),
      museExitProvider.overrideWith((ref) => _Exit()),
      museReachProvider.overrideWith((ref) => _Reach()),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MuseHomePage()),
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
}

Future<void> _pumpShell(WidgetTester t, Size size, {int index = 0, Widget? child, ThemeData? theme}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) => sp)]);
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: theme ?? ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)),
        home: MuseShellFrame(isMobile: false, currentIndex: index, onTap: (_) {}, child: child ?? const SizedBox()),
      ),
    ),
  );
  await t.pumpAndSettle();
}

double _mapHeight(WidgetTester t) => t.getSize(find.byKey(const ValueKey('muse_route_arc'))).height;

void main() {
  group('A1 路由图限高', () {
    test('上限：≤ 260 且 ≤ 窗口高 32%，不低于 160；手机不限', () {
      expect(museRouteMapMaxHeight(const Size(1000, 700)), closeTo(224, 0.01));
      // 1.19.2：上限 260 → 240（地图改为铺满卡片宽度）
      expect(museRouteMapMaxHeight(const Size(1600, 1000)), MuseDesk.mapMaxHeight);
      expect(MuseDesk.mapMaxHeight, 240);
      expect(museRouteMapMaxHeight(const Size(1000, 400)), 160);
      expect(museRouteMapMaxHeight(const Size(390, 844)), isNull);
    });

    for (final size in [const Size(1000, 700), const Size(1600, 1000), const Size(860, 700)]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}：地图不超上限，连接卡顶边在首屏 55% 以内', (t) async {
        await _pumpHome(t, size);
        expect(t.takeException(), isNull);
        expect(_mapHeight(t), lessThanOrEqualTo(museRouteMapMaxHeight(size)! + 0.5));
        expect(t.getTopLeft(find.byKey(const ValueKey('home_connect_section'))).dy, lessThan(size.height * 0.55));
        await _done(t);
      });
    }
  });

  group('A2 点阵', () {
    test('浅 32% / 深 24%；浅色卡片上点与底色对比度 ≥ 1.35:1', () {
      final light = museSeededScheme(brightness: Brightness.light);
      final dark = museSeededScheme(brightness: Brightness.dark);
      expect(museDotColor(light).a, closeTo(0.32, 0.01));
      expect(museDotColor(dark).a, closeTo(0.24, 0.01));
      final card = MuseSurface.card.color(light);
      expect(museContrast(Color.alphaBlend(museDotColor(light), card), card), greaterThanOrEqualTo(1.35));
      // 比 1.19.0 的 16% 明显更深
      final old = museContrast(Color.alphaBlend(light.onSurface.withValues(alpha: 0.16), card), card);
      expect(museContrast(Color.alphaBlend(museDotColor(light), card), card), greaterThan(old * 1.3));
    });

    test('点径按逻辑像素：格距小时隔点取，点半径不小于最小值', () {
      // 1° 格距、400 宽：每格 1.1 逻辑像素 → 隔 4 个取 1 个
      expect(museDotStride(1.1), greaterThan(1));
      expect(1.1 * museDotStride(1.1) * MuseDesk.dotRadiusShare, greaterThanOrEqualTo(MuseDesk.dotMinRadius));
      expect(museDotStride(10), 1);
      final src = File('lib/features/muse/home/route_map/muse_route_map.dart').readAsStringSync();
      expect(src.contains('clamp(0.6, 6.0)'), isFalse, reason: '不再按物理像素限制');
    });

    testWidgets('同一尺寸底图只渲染一次（重建不重画）', (t) async {
      await _pumpHome(t, const Size(1000, 700));
      final n = museDotImageRenders;
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(museDotImageRenders, n);
      await _done(t);
    });
  });

  group('A3 城市名与图注', () {
    // 1.20.0 方向 A（断言随改）：连接卡上的地图只标本机；出口城市不标名（节点所在国家已高亮、节点行写着国家，
    // 城市名会压住国家轮廓），图注行与节点行重复，去掉。1.19 路由卡的城市名 / 图注规则仍由 MuseRouteMap 默认参数保留。
    testWidgets('已连接：地图上有本机名，出口国家高亮而不标城市名；没有图注行', (t) async {
      await _pumpHome(t, const Size(1000, 700));
      expect(find.byKey(const ValueKey('muse_route_label_home')), findsOneWidget);
      expect(find.byKey(const ValueKey('muse_route_label_exit')), findsNothing);
      expect(t.widget<MuseRouteMap>(find.byType(MuseRouteMap)).highlightRegion, 'JP');
      expect(find.byKey(const ValueKey('muse_route_caption')), findsNothing);
      await _done(t);
    });

    testWidgets('未连接：不画出口城市名，只留本机', (t) async {
      await _pumpHome(t, const Size(1000, 700), connected: false);
      expect(find.byKey(const ValueKey('muse_route_label_home')), findsOneWidget);
      expect(find.byKey(const ValueKey('muse_route_label_exit')), findsNothing);
      await _done(t);
    });
  });

  group('A4 首页按窗口宽度分栏', () {
    // 1.20.0: the map is inside the connect card (断言随改：左栏是融合后的连接卡)
    testWidgets('1000 宽：双栏，左连接卡（含路由图），右卡片；无节点栏', (t) async {
      await _pumpHome(t, const Size(1000, 700));
      final left = t.getRect(find.byKey(const ValueKey('home_desk_left')));
      final right = t.getRect(find.byKey(const ValueKey('home_desk_right')));
      expect(right.left, greaterThan(left.right));
      expect(left.width / (left.width + right.width), closeTo(MuseDesk.leftShare, 0.02));
      expect(find.descendant(of: find.byKey(const ValueKey('home_desk_left')), matching: find.byKey(const ValueKey('home_hero_map'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('home_connect_section')), matching: find.byKey(const ValueKey('home_hero_map'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('home_desk_right')), matching: find.byKey(const ValueKey('home_tiles'))), findsOneWidget);
      expect(find.byKey(const ValueKey('home_side_nodes')), findsNothing);
      await _done(t);
    });

    testWidgets('1280 宽：再加右侧节点栏（按窗口宽度判断）', (t) async {
      await _pumpHome(t, const Size(1280, 800));
      expect(find.byKey(const ValueKey('home_desk_columns')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_side_nodes')), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('home_side_nodes'))).width, MuseDesk.nodeColumn);
      expect(t.takeException(), isNull);
      await _done(t);
    });

    // 1.19.2：电脑布局从 800（原 900）起；更窄的单栏也没有大标题「穿云」，顶部是同一行工具行（无测速）
    // 1.20.0: 单栏里地图也在连接卡里（断言随改）
    testWidgets('799 宽：单栏（路由图在连接卡里），无大标题、有工具行', (t) async {
      await _pumpHome(t, const Size(799, 700));
      expect(find.byKey(const ValueKey('home_desk_columns')), findsNothing);
      expect(find.byKey(const ValueKey('home_desk_toolbar')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_desk_speedtest')), findsNothing);
      expect(find.byKey(const ValueKey('home_dashboard')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('home_connect_section')), matching: find.byKey(const ValueKey('home_hero_map'))), findsOneWidget);
      expect(find.text('穿云'), findsNothing);
      await _done(t);
    });

    // 1.20.0 方向 A（断言随改）：手机上地图在连接卡里，高 = 卡宽 / 2.6（148–220）；连接钮 56 圆钮；没有图注行
    testWidgets('手机 390 宽：单栏，地图在连接卡里、高度按卡宽，56 圆钮', (t) async {
      await _pumpHome(t, const Size(390, 844));
      expect(find.byKey(const ValueKey('home_desk_columns')), findsNothing);
      expect(find.byKey(const ValueKey('home_status_desk')), findsNothing);
      final w = t.getSize(find.byKey(const ValueKey('muse_route_arc'))).width;
      expect(_mapHeight(t), closeTo(museHeroMapHeight(w), 0.5));
      expect(t.getSize(find.byKey(const ValueKey('home_connect_press'))).width, MuseHomeA.button);
      expect(find.byKey(const ValueKey('muse_route_caption')), findsNothing);
      await _done(t);
    });
  });

  group('A5 桌面连接卡', () {
    // 1.20.0 方向 A（断言随改）：电脑与手机同一张卡——状态 28 与时长 / 模式两行在左、56 圆钮在右并与这块垂直居中
    testWidgets('按钮与状态块同一行（按钮居中于状态块，差 < 8）、按钮 56；节点名 ≥ 16 号', (t) async {
      await _pumpHome(t, const Size(1000, 700));
      final button = t.getCenter(find.byKey(const ValueKey('home_connect_press')));
      final block = t.getCenter(find.byKey(const ValueKey('home_status_block')));
      expect((button.dy - block.dy).abs(), lessThan(8));
      expect(t.getSize(find.byKey(const ValueKey('home_connect_press'))).width, MuseDesk.startButton);
      final name = t.widget<Text>(find.byKey(const ValueKey('home_node_name')));
      expect(name.style!.fontSize, greaterThanOrEqualTo(16));
      // 换行时不留孤零零的「·」
      expect(find.byKey(const ValueKey('home_status_dot')), findsNothing);
      await _done(t);
    });

    testWidgets('超长节点名 / 订阅名：截断不溢出', (t) async {
      const long = '一个名字非常非常非常长的机场订阅（备用线路 · 每月 200 GB · 到期自动续费 · 客服 @example）';
      await _pumpHome(t, const Size(1000, 700), selected: _longName, profileName: long);
      expect(t.takeException(), isNull);
      final name = t.widget<Text>(find.byKey(const ValueKey('home_node_name')));
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(t.widget<Text>(find.byKey(const ValueKey('home_desk_summary'))).overflow, TextOverflow.ellipsis);
      await _done(t);
    });
  });

  group('A6 桌面首页工具行', () {
    testWidgets('宽屏：没有大标题「穿云」，换成「订阅名 ▾」+ 测速 + 编辑首页', (t) async {
      await _pumpHome(t, const Size(1000, 700));
      expect(find.byKey(const ValueKey('muse_page_title')), findsNothing);
      expect(find.text('穿云'), findsNothing);
      // 1.20.2：只留订阅名（可点「订阅名 ▾」打开订阅弹层），节点数去掉
      expect(find.text('机场订阅'), findsOneWidget);
      expect(find.byKey(const ValueKey('home_sub_switcher')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_desk_speedtest')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_edit_button')), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('home_desk_toolbar'))).height, MuseDesk.toolRow);
      await _done(t);
    });

    // 1.19.2：手机也去掉大标题，换成同一行工具行（不加测速）
    testWidgets('手机：无大标题「穿云」，顶部为工具行（无测速）', (t) async {
      await _pumpHome(t, const Size(390, 844));
      expect(find.text('穿云'), findsNothing);
      expect(find.byKey(const ValueKey('home_desk_toolbar')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_desk_speedtest')), findsNothing);
      await _done(t);
    });
  });

  group('A7 侧栏', () {
    // 1.19.2：展开侧栏 200 → 184
    testWidgets('184 宽、品牌行、选中项圆角底 + 左侧指示条、侧栏底色与分隔线', (t) async {
      await _pumpShell(t, const Size(1280, 800), index: 1);
      expect(t.getSize(find.byKey(const ValueKey('muse_sidebar_expanded'))).width, MuseSize.navSidebarExpanded);
      expect(MuseSize.navSidebarExpanded, 184);
      expect(t.getSize(find.byKey(const ValueKey('muse_sidebar_brand'))).height, MuseSidebar.headerHeight);
      expect(find.descendant(of: find.byKey(const ValueKey('muse_sidebar_brand')), matching: find.text('穿云')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('muse_nav_1')), matching: find.byKey(const ValueKey('muse_nav_indicator'))), findsOneWidget);
      expect(find.byKey(const ValueKey('muse_nav_indicator')), findsOneWidget);
      final ind = t.getSize(find.byKey(const ValueKey('muse_nav_indicator')));
      expect(ind, const Size(MuseDesk.navIndicatorWidth, MuseDesk.navIndicatorHeight));
      final scheme = Theme.of(t.element(find.byKey(const ValueKey('muse_nav_1')))).colorScheme;
      Material fill(String k) => t.widget<Material>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byKey(const ValueKey('muse_nav_fill'))));
      expect(fill('muse_nav_1').color, scheme.primary.withValues(alpha: MuseDesk.selectedAlpha));
      expect(fill('muse_nav_0').color, MusePalette.transparent);
      final box = t.widget<AnimatedContainer>(find.byKey(const ValueKey('muse_sidebar_expanded'))).decoration! as BoxDecoration;
      expect(box.color, MuseSidebar.fill(scheme));
      expect((box.border! as Border).right.width, MuseSize.hairline);
    });

    testWidgets('悬停改变底色（只靠指针事件，不起计时器）', (t) async {
      await _pumpShell(t, const Size(1280, 800), index: 1);
      final scheme = Theme.of(t.element(find.byKey(const ValueKey('muse_nav_0')))).colorScheme;
      Material fill() => t.widget<Material>(find.descendant(of: find.byKey(const ValueKey('muse_nav_0')), matching: find.byKey(const ValueKey('muse_nav_fill'))));
      expect(fill().color, MusePalette.transparent);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(t.getCenter(find.byKey(const ValueKey('muse_nav_0'))));
      await t.pump();
      expect(fill().color, scheme.onSurface.withValues(alpha: MuseDesk.hoverAlpha));
      await mouse.moveTo(const Offset(900, 700));
      await t.pump();
      expect(fill().color, MusePalette.transparent);
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    test('Windows 冒烟脚本按 headerHeight / itemHeight 点侧栏：数字与代码一致', () {
      final ps = File('tool/smoke/app_smoke.ps1').readAsStringSync();
      final h = MuseSidebar.headerHeight.toInt();
      final i = MuseSidebar.itemHeight.toInt();
      // 1.20.2：三栏，点第 2 项「节点」（原来点第 3 项「订阅」）
      expect(ps.contains('(32 + $h + $i * 1 + ${i ~/ 2})'), isTrue, reason: 'header $h, item $i');
      expect(MuseSize.titleBar, 32);
    });
  });

  group('A8 标题栏', () {
    Future<void> pumpBar(WidgetTester t, {String? glyphs}) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => sp),
          museTitleBarForceProvider.overrideWithValue(true),
          museWindowOpsProvider.overrideWithValue(_Ops()),
          museCaptionGlyphFamilyProvider.overrideWithValue(glyphs),
        ],
      );
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(sharedPreferencesProvider.future));
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: MuseTitleBarFrame(child: Scaffold(body: Text('page')))),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('应用图标 + 标题；有系统字形字体时用 Segoe Fluent Icons 字形', (t) async {
      await pumpBar(t, glyphs: 'Segoe Fluent Icons');
      expect(find.byKey(const ValueKey('muse_title_icon')), findsOneWidget);
      expect(find.byKey(const ValueKey('muse_title_text')), findsOneWidget);
      String glyph(String k) => t.widget<Text>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byKey(const ValueKey('muse_caption_glyph')))).data!;
      expect(glyph('muse_title_min'), String.fromCharCode(0xE921));
      expect(glyph('muse_title_max'), String.fromCharCode(0xE922));
      expect(glyph('muse_title_close'), String.fromCharCode(0xE8BB));
      expect(glyph('muse_title_pin'), String.fromCharCode(0xE718));
      final style = t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('muse_title_min')), matching: find.byKey(const ValueKey('muse_caption_glyph')))).style!;
      expect(style.fontFamily, 'Segoe Fluent Icons');
      expect(style.fontSize, MuseDesk.captionGlyph);
      expect(find.byIcon(Icons.remove_outlined), findsNothing);
    });

    testWidgets('字体不存在：回退现有 Material 图标', (t) async {
      await pumpBar(t);
      expect(find.byKey(const ValueKey('muse_caption_glyph')), findsNothing);
      expect(find.byIcon(Icons.remove_outlined), findsOneWidget);
      expect(find.byIcon(Icons.close_outlined), findsOneWidget);
      expect(museCaptionGlyphFamily(), Platform.isWindows ? isNotNull : isNull);
    });

    testWidgets('窗口失焦：标题与按钮变灰，回到前台恢复', (t) async {
      await pumpBar(t, glyphs: 'Segoe Fluent Icons');
      Color title() => t.widget<Text>(find.byKey(const ValueKey('muse_title_text'))).style!.color!;
      Color glyph() => t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('muse_title_min')), matching: find.byKey(const ValueKey('muse_caption_glyph')))).style!.color!;
      final active = title();
      final activeGlyph = glyph();
      final listener = t.state(find.byType(MuseTitleBar)) as WindowListener;
      listener.onWindowBlur();
      await t.pump();
      expect(title(), isNot(active));
      expect(title().a, lessThan(active.a));
      expect(glyph().a, lessThan(activeGlyph.a));
      listener.onWindowFocus();
      await t.pump();
      expect(title(), active);
    });
  });

  group('A9 统一标题与内容宽度', () {
    Widget page({bool large = true}) => MuseScaffold(
      large: large,
      title: '设置',
      body: MuseGroupedBody(
        children: [
          MuseSection(children: [ListTile(key: const ValueKey('row'), title: const Text('外观'), onTap: () {})]),
        ],
      ),
    );

    for (final large in [true, false]) {
      testWidgets('1600 宽（${large ? '大标题页' : '普通页'}）：标题 24 / w600，与卡片左边缘对齐；内容宽 840', (t) async {
        await _pumpShell(t, const Size(1600, 1000), index: 2, /* 1.20.2：三栏，设置是第 3 项 */ child: page(large: large));
        final title = t.widget<Text>(find.byKey(const ValueKey('muse_page_title')));
        expect(title.style!.fontSize, 24);
        expect(title.style!.fontWeight, FontWeight.w600);
        final titleLeft = t.getTopLeft(find.byKey(const ValueKey('muse_page_title'))).dx;
        final cardLeft = t.getTopLeft(find.byKey(const ValueKey('row'))).dx;
        expect((titleLeft - cardLeft).abs(), lessThan(1));
        final body = t.getSize(find.byType(MuseGroupedBody));
        expect(body.width, lessThanOrEqualTo(MuseDesk.contentMax));
        expect(body.width, greaterThan(800));
        expect(desktopContentMaxWidth, 840);
      });
    }

    testWidgets('手机：普通页标题仍是默认样式（不改）', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: page(large: false)));
      expect(t.widget<Text>(find.byKey(const ValueKey('muse_page_title'))).style, isNull);
    });
  });

  group('A10 悬停 / 焦点', () {
    test('主题统一的 hoverColor / focusColor', () {
      final theme = AppTheme(AppThemeMode.light, 'x').lightTheme(null);
      expect(theme.hoverColor, theme.colorScheme.onSurface.withValues(alpha: MuseDesk.themeHoverAlpha));
      expect(theme.focusColor, theme.colorScheme.primary.withValues(alpha: MuseDesk.themeFocusAlpha));
    });

    testWidgets('可点的 MuseCard 悬停时底色提高一级；不可点的不变；不起计时器', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MuseCard(key: const ValueKey('tap'), onTap: () {}, child: const SizedBox(width: 200, height: 80)),
                const MuseCard(key: ValueKey('plain'), child: SizedBox(width: 200, height: 80)),
              ],
            ),
          ),
        ),
      );
      Color fill(String k) => t.widget<Material>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Material)).first).color!;
      final base = fill('tap');
      final plain = fill('plain');
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(t.getCenter(find.byKey(const ValueKey('tap'))));
      await t.pump();
      final scheme = Theme.of(t.element(find.byKey(const ValueKey('tap')))).colorScheme;
      expect(fill('tap'), MuseCard.hoverFill(scheme, base));
      expect(fill('tap'), isNot(base));
      await mouse.moveTo(t.getCenter(find.byKey(const ValueKey('plain'))));
      await t.pump();
      expect(fill('plain'), plain);
      expect(fill('tap'), base);
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('键盘焦点：可点卡片显示 2 px 主色描边', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MuseCard(key: const ValueKey('tap'), onTap: () {}, child: const SizedBox(width: 200, height: 80)),
          ),
        ),
      );
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final m = t.widget<Material>(find.descendant(of: find.byKey(const ValueKey('tap')), matching: find.byType(Material)).first);
      final side = (m.shape! as OutlinedBorder).side;
      expect(side.width, MuseDesk.focusRing);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    });
  });
}
