// 穿云 1.20.2 - 订阅并入节点页：三栏、节点页标题「订阅名 ▾」与订阅弹层、旧 /config 地址只开一次弹层、
// 从弹层打开的覆写页 / 编辑页的返回键与预测性返回、首页订阅名、设置「分流规则」、空状态。
import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart' show mobileBranches, getIndexOfBranch;
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/nodes/muse_nodes_page.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart' show museActiveConfigProvider;
import 'package:hiddify/features/muse/nodes/subs_sheet.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart' show museOpenSubOverride;
import 'package:hiddify/features/settings/overview/settings_page.dart' show museSettingsHomeRows;
import 'package:hiddify/hiddifycore/generated/google/protobuf/timestamp.pb.dart';
import 'package:hiddify/utils/utils.dart' show PlatformUtils;
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

class _Profiles extends ProfilesNotifier {
  _Profiles(this.list);
  final List<ProfileEntity> list;
  @override
  Stream<List<ProfileEntity>> build() => Stream.value(list);
}

final _two = <ProfileEntity>[
  ProfileEntity.remote(
    id: 'p1',
    active: true,
    name: '机场订阅',
    url: 'https://sub.example.com/a',
    lastUpdate: DateTime.now().subtract(const Duration(hours: 3)),
    subInfo: SubscriptionInfo(
      upload: 3 << 30,
      download: 30 << 30,
      total: 120 << 30,
      expire: DateTime.now().add(const Duration(days: 29, hours: 2)),
    ),
  ),
  ProfileEntity.remote(id: 'p2', active: false, name: '备用订阅', url: 'https://sub.example.com/b', lastUpdate: DateTime(2026, 11, 1)),
];

OutboundInfo _node(String tag, String type, int delay, {bool group = false, String pick = ''}) => OutboundInfo(
  tag: tag,
  tagDisplay: tag,
  type: type,
  isGroup: group,
  urlTestDelay: delay,
  urlTestTime: Timestamp.fromDateTime(DateTime.now()),
  groupSelectedTagDisplay: pick,
);

final _group = OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '东京 02',
  selectable: true,
  items: [
    _node('lowest', 'URLTest', 86, group: true, pick: '东京 02'),
    _node('东京 02', 'vless', 86),
    _node('香港 01', 'hysteria2', 42),
    _node('新加坡 03', 'trojan', 120),
  ],
);

Future<ProviderContainer> _container(WidgetTester t, {bool hasProfile = true, List<ProfileEntity>? profiles}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      museConnectionProvider.overrideWithValue(const AsyncData(Connected())),
      museRunningProvider.overrideWithValue(true),
      museHasProfileProvider.overrideWithValue(hasProfile),
      museActiveProfileIdProvider.overrideWithValue(hasProfile ? 'p1' : null),
      museActiveProfileNameProvider.overrideWithValue(hasProfile ? '机场订阅' : null),
      museAppVersionProvider.overrideWithValue(null),
      museSubInfoProvider.overrideWithValue(null),
      // no database in a widget test (some node-page helpers read it and tolerate a failure)
      dbProvider.overrideWith((ref) => throw StateError('no database in widget tests')),
      museActiveConfigProvider.overrideWith((ref) async => ''),
      museStatsProvider.overrideWithValue(SystemInfo(uplink: Int64(0), downlink: Int64(0))),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
      profilesNotifierProvider.overrideWith(() => _Profiles(profiles ?? (hasProfile ? _two : const []))),
    ],
  );
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  await t.runAsync(() => c.read(translationsProvider.future));
  return c;
}

void _size(WidgetTester t, Size s) {
  t.view.physicalSize = s * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

/// The real shell ([MyAdaptiveLayout]) and the real 节点 page under a router shaped like the app's:
/// 首页 / 节点 / 设置, and `/config` redirecting to `/nodes` through [museRequestSubsSheet].
GoRouter _router(ProviderContainer c, {bool desktop = false}) {
  Widget stub(String name) => Scaffold(body: Center(child: Text('page:$name')));
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        name: 'config',
        path: '/config',
        redirect: (_, _) {
          museRequestSubsSheet(c.read(museSubsSheetPendingProvider.notifier));
          return '/nodes';
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) => MyAdaptiveLayout(navigationShell: shell, isMobileBreakpoint: !desktop, showProfilesAction: false, location: state.uri.path),
        branches: [
          StatefulShellBranch(routes: [GoRoute(name: 'home', path: '/home', builder: (_, _) => stub('home'))]),
          StatefulShellBranch(routes: [GoRoute(name: 'nodes', path: '/nodes', builder: (_, _) => const MuseNodesPage())]),
          StatefulShellBranch(routes: [GoRoute(name: 'settings', path: '/settings', builder: (_, _) => stub('settings'))]),
        ],
      ),
    ],
  );
}

Future<GoRouter> _pumpApp(WidgetTester t, ProviderContainer c, {bool desktop = false, Size size = const Size(390, 844)}) async {
  _size(t, size);
  final router = _router(c, desktop: desktop);
  addTearDown(router.dispose);
  final theme = AppTheme(AppThemeMode.light, '');
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: theme.lightTheme(null), routerConfig: router),
    ),
  );
  await _settle(t);
  return router;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _done(WidgetTester t) async {
  museCloseSubsSheet();
  await t.pumpWidget(const SizedBox.shrink());
  // UpdateProfileNotifier keeps itself 1 minute after the last listener
  await t.pump(const Duration(minutes: 2));
}

Finder get _panel => find.byType(MuseSubsPanel);

/// Android predictive back: the same messages the engine sends on a back swipe.
Future<void> _predictiveBack(WidgetTester t) async {
  const codec = StandardMethodCodec();
  Future<void> send(String method, [Object? args]) =>
      t.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/backgesture', codec.encodeMethodCall(MethodCall(method, args)), (_) {});
  await send('startBackGesture', <String, Object?>{'touchOffset': <double>[4, 400], 'progress': 0.0, 'swipeEdge': 0});
  await t.pump();
  await send('updateBackGestureProgress', <String, Object?>{'touchOffset': <double>[160, 400], 'progress': 0.6, 'swipeEdge': 0});
  await t.pump();
  await send('commitBackGesture');
  await t.pump();
  await _settle(t);
}

void main() {
  group('结构', () {
    test('底栏三栏：首页 / 节点 / 设置；分支同序；剪贴板圆点在「节点」', () {
      expect(museShellActions.map((a) => a.title), ['首页', '节点', '设置']);
      expect(mobileBranches, ['home', 'nodes', 'settings']);
      expect(getIndexOfBranch(true, false, 'settings'), 2);
      expect(museOfferTabIndex, 1);
      expect(museShellActions[museOfferTabIndex].title, '节点');
    });

    test('没有原型开关；/config 只重定向并请求弹层；订阅子页挂在 /nodes 下', () {
      final router = _src('lib/core/router/go_router/routing_config_notifier.dart');
      expect(router, isNot(contains('protoSubsMerge')));
      expect(router, isNot(contains('MuseConfigPage()')));
      expect(router, contains("path: '/config'"));
      expect(router, contains('museRequestSubsSheet(ref.read(museSubsSheetPendingProvider.notifier))'));
      expect(router, contains("return '/nodes';"));
      expect(router, contains('routes: configChildren'));
      expect(_src('lib/features/muse/data/muse_prefs.dart'), isNot(contains('muse_proto_subs_merge')));
      expect(_src('lib/features/muse/settings/developer_page.dart'), isNot(contains('dev_proto_subs')));
      // the old route names still open (shortcuts, tray, smoke scripts, deep links)
      expect(_src('lib/features/muse/desktop/smoke_control.dart'), contains("'config'"));
    });

    test('设置：「分流规则」在「网络」下面；搜索路径随新位置', () {
      final rows = museSettingsHomeRows(android: true, developer: false);
      expect(rows.indexOf('分流规则'), rows.indexOf('网络') + 1);
      expect(MuseSettingPage.routing.path, '设置 › 分流规则');
      expect(MuseSettingPage.subscriptions.path, '节点 › 订阅名 ▾ › ⋯');
      expect(museSearchSettings('订阅覆写', android: true, windows: false).first.page, MuseSettingPage.overrides);
      expect(museSearchSettings('订阅', android: true, windows: false).map((e) => e.page), contains(MuseSettingPage.subscriptions));
      final settings = _src('lib/features/settings/overview/settings_page.dart');
      expect(settings, contains('case MuseSettingPage.subscriptions:\n          museOpenSubscriptions(context, ref);'));
    });

    test('从弹层打开的编辑 / 覆写页走根导航（压在弹层上，返回回到弹层）；编辑页用 Navigator 关闭', () {
      final tile = _src('lib/features/profile/widget/profile_tile.dart');
      expect(tile, contains('onTap: () => museOpenProfileEdit(context, profile.id)'));
      expect(tile, contains('onTap: () => museOpenSubOverride(context, profile)'));
      expect(RegExp(r'museOpenProfileEdit[\s\S]*?rootNavigator: true').hasMatch(tile), isTrue);
      expect(RegExp(r'museOpenSubOverride[\s\S]*?rootNavigator: true').hasMatch(tile), isTrue);
      final details = _src('lib/features/profile/details/profile_details_page.dart');
      expect(details, isNot(contains('context.pop()')));
      expect(details, contains('Navigator.of(context).pop()'));
      final sheet = _src('lib/features/muse/nodes/subs_sheet.dart');
      expect(sheet, contains('useRootNavigator: true'));
    });

    test('首页：订阅名可点（去掉节点数），流量 / 到期卡就地打开弹层', () {
      final home = _src('lib/features/muse/home/muse_home_page.dart');
      expect(home, contains("ValueKey('home_sub_switcher')"));
      expect(home, isNot(contains("'\$nodes 个节点'")));
      expect(home, isNot(contains("goNamed('config')")));
      expect('onTap: () => museOpenSubscriptions(context, ref),'.allMatches(home).length, 2);
    });

    test('文案中文、不出现其他应用名、无循环动画', () {
      final sheet = _src('lib/features/muse/nodes/subs_sheet.dart');
      for (final banned in ['Clash', 'FlClash', 'Hiddify', 'sing-box', 'v2ray', 'repeat(', 'AnimationController']) {
        expect(sheet, isNot(contains(banned)), reason: banned);
      }
    });
  });

  group('节点页标题与订阅弹层（手机）', () {
    testWidgets('标题「订阅名 ▾」≥48 高、读屏标签；点开弹层：两行、当前订阅选中、余量与到期；返回键关闭', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c);
      router.go('/nodes');
      await _settle(t);
      final sw = find.byKey(const ValueKey('nodes_sub_switcher'));
      expect(sw, findsOneWidget);
      expect(find.descendant(of: sw, matching: find.text('机场订阅')), findsOneWidget);
      expect(t.getSize(sw).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('切换订阅，当前 机场订阅，共 2 个'), findsOneWidget);
      // 1.20.1 kept: 搜索 / 测速 / ⋯ on the title row, no 「订阅 · N 个节点」 line
      expect(find.byKey(const ValueKey('node_test_button')), findsOneWidget);
      expect(find.textContaining('个节点'), findsNothing);
      expect((t.getCenter(find.byKey(const ValueKey('node_test_button'))).dy - t.getCenter(sw).dy).abs(), lessThan(4));

      await t.tap(sw);
      await _settle(t);
      expect(_panel, findsOneWidget);
      expect(find.byKey(const ValueKey('subs_row_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('subs_row_p2')), findsOneWidget);
      // 「剩 87 GB / 120 GB」（数字与单位之间是不换行空格）
      expect(find.byWidgetPredicate((w) => w is Text && RegExp(r'^剩 87(\.0)?\s?GB / 120\s?GB$').hasMatch(w.data ?? '')), findsOneWidget);
      expect(find.textContaining('后到期'), findsOneWidget);
      expect(find.byKey(const ValueKey('subs_add')), findsOneWidget);
      expect(find.byKey(const ValueKey('subs_update_all')), findsOneWidget);
      // the sheet covers the dock (root navigator)
      expect(find.byKey(const ValueKey('muse_dock_floating')), findsOneWidget);
      expect(museSubsSheetOpen, isTrue);

      await t.binding.handlePopRoute();
      await _settle(t);
      expect(_panel, findsNothing);
      expect(museSubsSheetOpen, isFalse);
      expect(router.state.uri.path, '/nodes');
      await _done(t);
    });

    testWidgets('⋯ 菜单：排序（>1 个）、订阅自动更新、更新后测速新增节点、导入 / 导出配置', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c);
      router.go('/nodes');
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('nodes_sub_switcher')));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('subs_more')));
      await _settle(t);
      for (final k in ['subs_more_order', 'auto_update_hours', 'test_new_nodes', 'subs_more_import', 'subs_more_export']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await t.binding.handlePopRoute();
      await _settle(t);
      await _done(t);
    });

    testWidgets('⋮ › 订阅覆写：页面压在弹层上；返回键先关覆写页回到弹层，再按关弹层，留在节点页', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c);
      router.go('/nodes');
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('nodes_sub_switcher')));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('subs_row_menu_p2')));
      await _settle(t);
      expect(find.text('订阅覆写'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('节点筛选'), findsOneWidget);
      await t.tap(find.text('订阅覆写'));
      await _settle(t);
      expect(find.text('覆写 · 备用订阅'), findsOneWidget);

      await t.binding.handlePopRoute();
      await _settle(t);
      expect(find.text('覆写 · 备用订阅'), findsNothing);
      expect(_panel, findsOneWidget, reason: 'back returns to the sheet');

      await t.binding.handlePopRoute();
      await _settle(t);
      expect(_panel, findsNothing);
      expect(router.state.uri.path, '/nodes');
      expect(find.byKey(const ValueKey('nodes_sub_switcher')), findsOneWidget);
      await _done(t);
    });

    testWidgets('⋮ › 编辑：编辑页压在弹层上（根导航）；返回键与预测性返回都先回到弹层', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c);
      router.go('/nodes');
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('nodes_sub_switcher')));
      await _settle(t);
      for (final viaGesture in [false, true]) {
        await t.tap(find.byKey(const ValueKey('subs_row_menu_p1')));
        await _settle(t);
        await t.tap(find.text('编辑'));
        await _settle(t);
        final page = find.byType(ProfileDetailsPage);
        expect(page, findsOneWidget);
        final route = ModalRoute.of(t.element(page))!;
        expect(route.navigator, same(Navigator.of(t.element(find.byType(MuseSubsPanel, skipOffstage: false)), rootNavigator: true)));
        if (viaGesture) {
          await _predictiveBack(t);
        } else {
          await t.binding.handlePopRoute();
          await _settle(t);
        }
        expect(find.byType(ProfileDetailsPage), findsNothing, reason: viaGesture ? 'predictive back' : 'back key');
        expect(_panel, findsOneWidget);
        expect(router.state.uri.path, '/nodes');
      }
      await _done(t);
    });

    testWidgets('预测性返回（安卓滑动返回）：关掉覆写页、弹层还在', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c);
      router.go('/nodes');
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('nodes_sub_switcher')));
      await _settle(t);
      final ctx = t.element(_panel);
      // the same call the ⋮ menu makes
      unawaited(museOpenSubOverrideForTest(ctx, _two[0]));
      await _settle(t);
      expect(find.text('覆写 · 机场订阅'), findsOneWidget);
      final route = ModalRoute.of(t.element(find.text('覆写 · 机场订阅')))!;
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route.popGestureEnabled, isTrue);
      expect(route.navigator, same(Navigator.of(ctx, rootNavigator: true)));

      await _predictiveBack(t);
      expect(find.text('覆写 · 机场订阅'), findsNothing);
      expect(_panel, findsOneWidget);
      expect(router.state.uri.path, '/nodes');
      await _done(t);
    });

    testWidgets('点一行 = 切换并关闭弹层，留在节点页', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c);
      router.go('/nodes');
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('nodes_sub_switcher')));
      await _settle(t);
      // tapping the row already in use only closes the sheet (switching another one needs the core)
      await t.tap(find.byKey(const ValueKey('subs_row_p1')));
      await _settle(t);
      expect(_panel, findsNothing);
      expect(router.state.uri.path, '/nodes');
      await _done(t);
    });
  });

  group('旧订阅地址 /config', () {
    testWidgets('从首页跳 /config：到节点页、弹层只开一次（同一帧里求值多次也一样）', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c);
      router.go('/config');
      router.go('/config');
      // a third request straight to the helper in the same frame
      museRequestSubsSheet(c.read(museSubsSheetPendingProvider.notifier));
      await _settle(t);
      await _settle(t);
      expect(router.state.uri.path, '/nodes');
      expect(_panel, findsOneWidget);
      expect(c.read(museSubsSheetPendingProvider), isFalse);

      // asked again while it is open: still one
      router.go('/config');
      await _settle(t);
      await _settle(t);
      expect(_panel, findsOneWidget);
      expect(c.read(museSubsSheetPendingProvider), isFalse);

      // another page (tray, shortcut, smoke script): the sheet does not stay on top of it
      router.go('/settings');
      await _settle(t);
      expect(_panel, findsNothing);
      expect(find.text('page:settings'), findsOneWidget);
      expect(museSubsSheetOpen, isFalse);

      // back on 节点 it does not come back by itself
      router.go('/nodes');
      await _settle(t);
      await _settle(t);
      expect(_panel, findsNothing);
      await _done(t);
    });

    testWidgets('节点页第一次被打开时就在等的请求也会打开（只一次）', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c);
      c.read(museSubsSheetPendingProvider.notifier).state = true;
      router.go('/nodes');
      await _settle(t);
      await _settle(t);
      expect(_panel, findsOneWidget);
      await t.binding.handlePopRoute();
      await _settle(t);
      await _settle(t);
      expect(_panel, findsNothing);
      await _done(t);
    });

    testWidgets('没有订阅：节点页是空状态（添加订阅 + 导入方式），/config 不再补开弹层', (t) async {
      final c = await _container(t, hasProfile: false);
      final router = await _pumpApp(t, c);
      router.go('/config');
      await _settle(t);
      await _settle(t);
      expect(router.state.uri.path, '/nodes');
      expect(find.byKey(const ValueKey('nodes_empty')), findsOneWidget);
      expect(find.text('还没有订阅'), findsOneWidget);
      expect(find.byKey(const ValueKey('nodes_empty_add')), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('nodes_empty_add'))).height, greaterThanOrEqualTo(56));
      for (final k in ['nodes_empty_paste', 'nodes_empty_file', 'nodes_empty_restore']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      // 扫描二维码只在手机上
      expect(find.byKey(const ValueKey('nodes_empty_qr')), PlatformUtils.isDesktop ? findsNothing : findsOneWidget);
      expect(_panel, findsNothing);
      expect(c.read(museSubsSheetPendingProvider), isFalse);
      await _done(t);
    });
  });

  group('电脑窗口', () {
    testWidgets('1280 宽：标题 24/600，弹层是挂在标题下的 440 宽浮层', (t) async {
      final c = await _container(t);
      final router = await _pumpApp(t, c, desktop: true, size: const Size(1280, 800));
      router.go('/nodes');
      await _settle(t);
      final title = t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('nodes_sub_switcher')), matching: find.text('机场订阅')));
      expect(title.style!.fontSize, 24);
      expect(title.style!.fontWeight, FontWeight.w600);
      final sw = t.getRect(find.byKey(const ValueKey('nodes_sub_switcher')));
      await t.tap(find.byKey(const ValueKey('nodes_sub_switcher')));
      await _settle(t);
      final panel = t.getRect(find.byKey(const ValueKey('subs_panel')));
      expect(panel.width, lessThanOrEqualTo(MuseSubsPanel.deskWidth));
      expect(panel.width, greaterThan(400));
      expect(panel.top, greaterThan(sw.bottom - 1));
      expect((panel.left - sw.left).abs(), lessThan(24));
      await t.binding.handlePopRoute();
      await _settle(t);
      expect(_panel, findsNothing);
      await _done(t);
    });
  });
}

/// The ⋮ menu's 订阅覆写 (exposed under a test name so the test does not depend on the menu's layout).
Future<void> museOpenSubOverrideForTest(BuildContext context, ProfileEntity p) => museOpenSubOverride(context, p);
