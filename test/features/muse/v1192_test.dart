// 穿云 1.19.2：按实机反馈一次改完——窄窗口图标栏与紧凑双栏、首页去大标题、地图铺满卡片宽度、终点城市名
// 在地图内靠边翻转（各地区最坏情况）、已连接色（对比度）与一次性颜色过渡、删掉无分类时的提示、内置中文字体。
// Part of 穿云 (GPLv3).
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/home/route_map/muse_route_map.dart';
import 'package:hiddify/features/muse/home/route_map/route_geo.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/hiddifycore/generated/google/protobuf/timestamp.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Exit extends MuseExitNotifier {
  _Exit([String country = 'JP']) : super(() => 0) {
    state = MuseExitResult(info: MuseExitInfo(ip: '45.76.112.9', country: country));
  }
}

class _Reach extends MuseReachNotifier {
  _Reach() : super(() => 0) {
    state = MuseReach.ok;
  }
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
  String exit = 'JP',
  double inset = 0,
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
      museExitProvider.overrideWith((ref) => _Exit(exit)),
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
      child: MaterialApp(
        home: inset == 0
            ? const MuseHomePage()
            : Row(children: [SizedBox(width: inset), const Expanded(child: MuseHomePage())]),
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


const _cities = <String, MuseCity>{
  '洛杉矶': MuseCity('洛杉矶', 'US', 34.05, -118.24),
  '纽约': MuseCity('纽约', 'US', 40.71, -74.01),
  '伦敦': MuseCity('伦敦', 'GB', 51.51, -0.13),
  '圣保罗': MuseCity('圣保罗', 'BR', -23.55, -46.63),
  '悉尼': MuseCity('悉尼', 'AU', -33.87, 151.21),
  '雷克雅未克': MuseCity('雷克雅未克', 'IS', 64.15, -21.94),
  '奥克兰': MuseCity('奥克兰', 'NZ', -36.85, 174.76),
  '檀香山': MuseCity('檀香山', 'US', 21.31, -157.86),
  '开普敦': MuseCity('开普敦', 'ZA', -33.92, 18.42),
  '圣地亚哥': MuseCity('圣地亚哥', 'CL', -33.45, -70.67),
  '上海': MuseCity('上海', 'CN', 31.23, 121.47),
};

Future<MuseWorldDots> _dots(WidgetTester t) async =>
    MuseWorldDots.parse(File('assets/map/world_dots.bin').readAsBytesSync())!;

Future<void> _pumpMap(
  WidgetTester t, {
  required MuseCity city,
  required double width,
  bool connected = true,
  double? maxHeight,
  bool disableAnimations = false,
  MuseWorldDots? dots,
  Duration settle = const Duration(seconds: 3),
}) async {
  dots ??= await _dots(t);
  t.view.physicalSize = Size(width + 40, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width + 40, 900), disableAnimations: disableAnimations),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MuseRouteMap(
                key: const ValueKey('map'),
                connected: connected,
                exit: MuseExitPlace(city, MuseExitSource.measured),
                dots: dots,
                maxHeight: maxHeight,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump(settle);
}

/// UTF-16 BMP cmap (format 4) of a TrueType font: the code points it has glyphs for.
Set<int> _cmap(List<int> b) {
  int u16(int o) => (b[o] << 8) | b[o + 1];
  int u32(int o) => (u16(o) << 16) | u16(o + 2);
  final n = u16(4);
  var cmap = -1;
  for (var i = 0; i < n; i++) {
    final r = 12 + 16 * i;
    if (String.fromCharCodes(b.sublist(r, r + 4)) == 'cmap') cmap = u32(r + 8);
  }
  final out = <int>{};
  final tables = u16(cmap + 2);
  for (var i = 0; i < tables; i++) {
    final off = cmap + u32(cmap + 4 + 8 * i + 4);
    if (u16(off) != 4) continue;
    final segX2 = u16(off + 6);
    final ends = off + 14;
    final starts = ends + segX2 + 2;
    final deltas = starts + segX2;
    final ranges = deltas + segX2;
    for (var s = 0; s < segX2 ~/ 2; s++) {
      final end = u16(ends + 2 * s);
      final start = u16(starts + 2 * s);
      final delta = u16(deltas + 2 * s);
      final ro = u16(ranges + 2 * s);
      for (var c = start; c <= end && c != 0xFFFF; c++) {
        int g;
        if (ro == 0) {
          g = (c + delta) & 0xFFFF;
        } else {
          final gi = ranges + 2 * s + ro + 2 * (c - start);
          g = u16(gi);
          if (g != 0) g = (g + delta) & 0xFFFF;
        }
        if (g != 0) out.add(c);
      }
    }
  }
  return out;
}

void main() {
  group('1 窄窗口：图标栏与紧凑双栏', () {
    test('导航形态：< 600 底栏；600–1080 图标栏（64 宽）；> 1080 可展开侧栏（184 宽）', () {
      expect(museNavForm(390), MuseNavForm.dock);
      expect(museNavForm(800), MuseNavForm.rail);
      expect(museNavForm(880), MuseNavForm.rail);
      expect(museNavForm(1000), MuseNavForm.rail);
      expect(museNavForm(1080), MuseNavForm.rail);
      expect(museNavForm(1100), MuseNavForm.sidebar);
      expect(MuseSize.navRailCollapsed, 64);
      expect(MuseSize.navSidebarExpanded, 184);
    });

    for (final w in [800.0, 880.0]) {
      testWidgets('${w.toInt()} 宽窗口：图标栏 64，内容区 ≥ ${(w - 64).toInt()}', (t) async {
        await _pumpShell(t, Size(w, 680));
        expect(find.byKey(const ValueKey('muse_sidebar_collapsed')), findsOneWidget);
        expect(t.getSize(find.byKey(const ValueKey('muse_sidebar_collapsed'))).width, 64);
        expect(find.byKey(const ValueKey('muse_sidebar_toggle')), findsNothing);
      });
    }

    for (final w in [800.0, 880.0]) {
      testWidgets('${w.toInt()} 宽窗口首页（左侧扣掉 64 图标栏）：紧凑双栏，无大标题', (t) async {
        await _pumpHome(t, Size(w, 680), inset: 64);
        expect(find.byKey(const ValueKey('home_desk_columns')), findsOneWidget);
        expect(find.byKey(const ValueKey('muse_page_title')), findsNothing);
        expect(find.byKey(const ValueKey('home_desk_toolbar')), findsOneWidget);
        expect(t.takeException(), isNull);
        await _done(t);
      });
    }

    testWidgets('电脑窗口但页面本身不足 700 宽（侧栏展开等）：同一工具行下的单栏，不挤成两栏', (t) async {
      await _pumpHome(t, const Size(820, 680), inset: 184);
      expect(find.byKey(const ValueKey('home_desk_columns')), findsNothing);
      expect(find.byKey(const ValueKey('home_desk_toolbar')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_dashboard')), findsOneWidget);
      expect(t.takeException(), isNull);
      await _done(t);
      expect(MuseDesk.twoColumn, 800);
      expect(MuseDesk.twoColumnContent, 700);
    });
  });

  group('2 首页没有大标题「穿云」', () {
    for (final size in const [Size(390, 844), Size(1000, 700), Size(1600, 1000)]) {
      testWidgets('${size.width.toInt()} 宽：无「穿云」标题；工具行带编辑首页', (t) async {
        await _pumpHome(t, size);
        expect(find.byKey(const ValueKey('muse_page_title')), findsNothing);
        expect(find.text('穿云'), findsNothing);
        expect(find.byKey(const ValueKey('home_desk_toolbar')), findsOneWidget);
        expect(find.byKey(const ValueKey('home_edit_button')), findsOneWidget);
        // 手机不加测速（不改手机信息架构）；≥ 1280 测速在右侧节点栏
        expect(
          find.byKey(const ValueKey('home_desk_speedtest')),
          size.width < 600 || size.width >= MuseDesk.threeColumn ? findsNothing : findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await _done(t);
      });
    }

    testWidgets('手机：工具行在状态栏下方（不被遮住）', (t) async {
      t.view.padding = const FakeViewPadding(top: 24);
      addTearDown(t.view.resetPadding);
      await _pumpHome(t, const Size(390, 844));
      expect(t.getTopLeft(find.byKey(const ValueKey('home_desk_toolbar'))).dy, greaterThanOrEqualTo(24));
      await _done(t);
    });
  });

  group('3 地图铺满卡片宽度', () {
    test('取景：宽高比 ≤ 2.5 用整幅；更扁时裁纬度（中心北纬 12°，跨度不小于 100°）', () {
      expect(museMapView(const Size(358, 163)), MuseMapView.full);
      expect(museMapView(const Size(600, 240)), MuseMapView.full);
      final v = museMapView(const Size(800, 240));
      expect(v.north - v.south, closeTo(108, 1e-9));
      expect((v.north + v.south) / 2, closeTo(12, 1e-9));
      final w = museMapView(const Size(1400, 240));
      expect(w.north - w.south, museMapMinLatSpan);
      // 伦敦、悉尼、圣保罗、开普敦都在取景内
      for (final c in ['伦敦', '悉尼', '圣保罗', '开普敦']) {
        expect(_cities[c]!.lat, inInclusiveRange(w.south, w.north), reason: c);
      }
    });

    test('高度：宽 / 2.2，电脑窗口不超上限；宽度始终铺满', () {
      expect(museRouteMapHeight(358, 2.2, null), closeTo(162.7, 0.1));
      expect(museRouteMapHeight(700, 2.2, 224), 224);
      expect(museRouteMapHeight(400, 2.2, 224), closeTo(181.8, 0.1));
    });

    for (final w in [358.0, 520.0, 900.0]) {
      testWidgets('卡片宽 ${w.toInt()}：地图与卡片同宽', (t) async {
        await _pumpMap(t, city: _cities['伦敦']!, width: w, maxHeight: w > 400 ? 224 : null);
        expect(t.getSize(find.byKey(const ValueKey('muse_route_map_box'))).width, w);
        expect(t.getSize(find.byKey(const ValueKey('muse_route_base'))).width, w);
      });
    }
  });

  group('4 终点城市名在地图内、靠边向内翻（break-ui）', () {
    for (final name in _cities.keys.where((k) => k != '上海')) {
      for (final w in [358.0, 560.0, 900.0]) {
        testWidgets('$name · 地图宽 ${w.toInt()}：城市名整块在地图内、单行、贴着终点', (t) async {
          await _pumpMap(t, city: _cities[name]!, width: w, maxHeight: w > 400 ? 224 : null);
          final map = t.getRect(find.byKey(const ValueKey('muse_route_map_box')));
          final label = t.getRect(find.byKey(const ValueKey('muse_route_label_exit')));
          expect(label.left, greaterThanOrEqualTo(map.left - 0.5), reason: 'left');
          expect(label.right, lessThanOrEqualTo(map.right + 0.5), reason: 'right');
          expect(label.top, greaterThanOrEqualTo(map.top - 0.5));
          expect(label.bottom, lessThanOrEqualTo(map.bottom + 0.5));
          // 单行：高度不超过一行字
          expect(label.height, lessThan(26));
          // 贴着终点（与终点水平距离不超过标签宽 + 间距）
          final size = map.size;
          final c = _cities[name]!;
          final e = museProject(c.lat, c.lon, size, view: museMapView(size)) + map.topLeft;
          final dx = e.dx < label.left ? label.left - e.dx : (e.dx > label.right ? e.dx - label.right : 0);
          expect(dx, lessThanOrEqualTo(MuseDesk.mapLabelGap + 1), reason: 'near its dot');
          expect(t.takeException(), isNull);
        });
      }
    }

    test('洛杉矶在上海右边（展开后的经度），不再被画到地图左外侧', () {
      const size = Size(560, 224);
      final v = museMapView(size);
      final la = museProject(34.05, -118.24, size, view: v);
      final sh = museProject(31.23, 121.47, size, view: v);
      expect(la.dx, greaterThan(sh.dx));
      expect(la.dx, inInclusiveRange(0, size.width));
    });

    test('标签放置：右缘向左翻、左缘向右翻、上缘放到点下方、窄到放不下时贴边', () {
      const map = Size(300, 120);
      const box = Size(50, 18);
      expect(museLabelOffset(const Offset(290, 60), box, map, before: false, above: true).dx, lessThan(290 - 50));
      expect(museLabelOffset(const Offset(5, 60), box, map, before: true, above: true).dx, greaterThan(5));
      expect(museLabelOffset(const Offset(150, 4), box, map, before: false, above: true).dy, greaterThan(4));
      final o = museLabelOffset(const Offset(10, 60), const Size(400, 18), map, before: true, above: true);
      expect(o.dx, 0);
    });
  });

  group('5 已连接色', () {
    const seeds = [
      Color(0xFF2775B6), Color(0xFF4B5CC4), Color(0xFF789262), Color(0xFFBCE672), Color(0xFF9D2933),
      Color(0xFFC32136), Color(0xFFFFB61E), Color(0xFF48C0A3), Color(0xFFCCA4E3), Color(0xFF845A33),
    ];
    test('各主题色、深浅色：图形与卡片底色 ≥ 3:1，终点文字 ≥ 4.5:1', () {
      for (final seed in seeds) {
        for (final b in Brightness.values) {
          for (final variant in [DynamicSchemeVariant.fidelity, DynamicSchemeVariant.tonalSpot]) {
            final s = ColorScheme.fromSeed(seedColor: seed, brightness: b, dynamicSchemeVariant: variant);
            for (final bg in [s.surface, s.surfaceContainerLowest, s.surfaceContainerLow, s.surfaceContainer]) {
              expect(museContrast(museLinkedColor(s, bg), bg), greaterThanOrEqualTo(3), reason: '$seed $b');
              expect(museContrast(museLinkedColor(s, bg, ratio: 4.5), bg), greaterThanOrEqualTo(4.5), reason: '$seed $b');
            }
          }
        }
      }
    });

    test('主色本身够对比时就用主色（与连接卡同一色相）', () {
      final s = ColorScheme.fromSeed(seedColor: const Color(0xFF2775B6));
      expect(museLinkedColor(s, s.surface), s.primary);
    });

    testWidgets('未连接 → 已连接：起点由中性色一次性过渡到已连接色（约 200ms 后停）', (t) async {
      final dots = await _dots(t);
      await _pumpMap(t, city: _cities['伦敦']!, width: 520, connected: false, dots: dots);
      final st = t.state<MuseRouteMapState>(find.byKey(const ValueKey('map')));
      expect(st.tint, 0);
      await _pumpMap(t, city: _cities['伦敦']!, width: 520, dots: dots);
      expect(st.tint, 1);
      // 弧线画完后光点跑一趟（各一次性），之后不再出帧
      await t.pump(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(st.animating, isFalse, reason: '过渡结束后不再出帧');
      await _pumpMap(t, city: _cities['伦敦']!, width: 520, connected: false, dots: dots);
      expect(st.tint, 0);
    });

    testWidgets('过渡时长：标准 ≤ 300ms；关闭档（移除动画）直接终态', (t) async {
      final dots = await _dots(t);
      await _pumpMap(t, city: _cities['伦敦']!, width: 520, connected: false, dots: dots);
      final st = t.state<MuseRouteMapState>(find.byKey(const ValueKey('map')));
      await _pumpMap(t, city: _cities['伦敦']!, width: 520, dots: dots, settle: Duration.zero);
      await t.pump(const Duration(milliseconds: 100));
      expect(st.tint, inExclusiveRange(0, 1));
      await t.pump(const Duration(milliseconds: 200));
      expect(st.tint, 1);
      await t.pump(const Duration(seconds: 3));
      await _pumpMap(t, city: _cities['伦敦']!, width: 520, connected: false, dots: dots, disableAnimations: true);
      final st2 = t.state<MuseRouteMapState>(find.byKey(const ValueKey('map')));
      await _pumpMap(t, city: _cities['伦敦']!, width: 520, dots: dots, disableAnimations: true);
      await t.pump();
      expect(st2.tint, 1);
    });
  });

  group('6 没有分类数据时不显示提示', () {
    testWidgets('已连接、无流量分类：地图下没有「有流量后显示…」', (t) async {
      await _pumpHome(t, const Size(390, 844));
      expect(find.textContaining('有流量后显示'), findsNothing);
      expect(find.byKey(const ValueKey('home_route_sentence')), findsNothing);
      await _done(t);
    });

    test('源码里不再有这句提示', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('changelog.dart'))
          .where((f) => f.readAsStringSync().contains('有流量后显示各类流量走哪里'));
      expect(hits, isEmpty);
    });
  });

  group('7 内置中文字体（思源黑体子集 MuseHei）', () {
    test('两端默认字族都是 MuseHei；Windows 用 Emoji 作后备', () {
      expect(AppLocale.zhCn.preferredFontFamily, MuseFont.cjk);
      expect(MuseFont.cjk, 'MuseHei');
      final theme = AppTheme(AppThemeMode.light, MuseFont.cjk, fontFallback: const ['Emoji']).lightTheme(null);
      expect(theme.textTheme.bodyMedium!.fontFamily, 'MuseHei');
      expect(theme.textTheme.bodyMedium!.fontFamilyFallback, ['Emoji']);
    });

    test('pubspec 声明 400 + 600 两个字重、许可证随附', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(pub, contains('family: MuseHei'));
      expect(pub, contains('assets/fonts/MuseHei-Regular.ttf'));
      expect(pub, contains('assets/fonts/MuseHei-SemiBold.ttf'));
      expect(pub, contains('assets/fonts/OFL-NotoSansSC.txt'));
      final ofl = File('assets/fonts/OFL-NotoSansSC.txt').readAsStringSync();
      expect(ofl, contains('SIL Open Font License, Version 1.1'));
      expect(ofl, contains('MuseHei'));
      expect(File('tool/fonts/subset_cjk.py').existsSync(), isTrue);
    });

    test('体积：两个字重合计 ≤ 5 MB（压缩后每包增量约 3 MB，≤ 4 MB 目标）', () {
      final total = File('assets/fonts/MuseHei-Regular.ttf').lengthSync() + File('assets/fonts/MuseHei-SemiBold.ttf').lengthSync();
      expect(total, lessThanOrEqualTo(5 * 1024 * 1024));
      final z = gzip.encode(File('assets/fonts/MuseHei-Regular.ttf').readAsBytesSync()).length +
          gzip.encode(File('assets/fonts/MuseHei-SemiBold.ttf').readAsBytesSync()).length;
      expect(z, lessThanOrEqualTo(4 * 1024 * 1024));
    });

    test('lib/ 里出现的每个汉字与中文标点，两个字重都有字形；GB2312 一级字全在', () {
      final need = <int>{};
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        for (final r in f.readAsStringSync().runes) {
          if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3000 && r <= 0x303F) || (r >= 0xFF00 && r <= 0xFFEF)) need.add(r);
        }
      }
      expect(need.length, greaterThan(800));
      for (final w in ['Regular', 'SemiBold']) {
        final have = _cmap(File('assets/fonts/MuseHei-$w.ttf').readAsBytesSync());
        final missing = need.difference(have);
        expect(missing.map(String.fromCharCode).join(), isEmpty, reason: w);
        // 抽查 GB2312 一级字（啊…座）与常见二级字
        for (final c in '啊阿埃挨哎座穿云节点订阅连接断开测速丌亍'.runes) {
          expect(have, contains(c), reason: '$w ${String.fromCharCode(c)}');
        }
      }
    });

    // 1.20.3: the 致谢 group (思源黑体 row included) is gone from 关于 › 开源许可; the font's licence file stays bundled
    testWidgets('关于 › 开源许可没有致谢行；思源黑体的许可文件仍随应用打包', (t) async {
      final src = File('lib/features/about/widget/open_source_page.dart').readAsStringSync();
      expect(src, isNot(contains('about_credit_font_cjk')));
      expect(src, isNot(contains('思源黑体')));
      expect(File('assets/fonts/OFL-NotoSansSC.txt').existsSync(), isTrue);
    });
  });

  group('8 打磨', () {
    test('数字字体（Inter）里的汉字回退到内置思源黑体，Windows 再回退 Emoji', () {
      expect(MuseFont.fallback.first, MuseFont.cjk);
      final src = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final f in src) {
        final text = f.readAsStringSync();
        final uses = 'fontFamily: MuseFont.family'.allMatches(text).length;
        final falls = 'fontFamilyFallback: MuseFont.fallback'.allMatches(text).length;
        expect(falls, greaterThanOrEqualTo(uses), reason: f.path);
      }
    });

    test('选中节点卡的协议标签用卡片正文色（深色主题下主色字在主色底上只有约 1.5:1）', () {
      final src = File('lib/features/muse/nodes/node_rows.dart').readAsStringSync();
      expect(src, contains('color: highlighted ? mt.text1 : mt.text2'));
    });

    test('电脑窗口页面标题行 56；Windows 冒烟脚本点击侧栏的 x 落在 64 宽图标栏内', () {
      expect(MuseDesk.titleBarHeight, 56);
      final smoke = File('tool/smoke/app_smoke.ps1').readAsStringSync();
      expect(smoke, contains(r'$x = $r.L + [int](32 * $scale)'));
      expect(32, lessThan(MuseSize.navRailCollapsed));
      // 1.20.2：三栏，点第 2 项「节点」
      expect(smoke, contains('(32 + 48 + 52 * 1 + 26)'));
    });
  });
}
