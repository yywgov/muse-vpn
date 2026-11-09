// 穿云 1.10.2 自查: every page touched by the 1.10.0 slimming (设置 home, each settings sub-page, 节点,
// 规则, 订阅, 活动 with all five tabs, 关于) opens on a phone (portrait / landscape) and a tablet
// (portrait / landscape), light and dark, without a layout overflow or any FlutterError; the 节点
// page also with no subscription, disconnected, while 测速 runs, in 多选 and with each ⋯ entry.
import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/about/widget/open_source_page.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/activity/activity_page.dart';
import 'package:hiddify/features/muse/config/muse_config_page.dart';
import 'package:hiddify/features/muse/config/rules_page.dart';
import 'package:hiddify/features/muse/config/sub_override_page.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/nodes/muse_nodes_page.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart' show museScrollToKey;
import 'package:hiddify/features/muse/settings/android_settings.dart' show museExcludeRecentsTitle;
import 'package:hiddify/features/muse/settings/auto_connect_page.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/settings/resources_page.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/hiddifycore/generated/google/protobuf/timestamp.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Info extends AppInfo {
  @override
  Future<AppInfoEntity> build() async => const AppInfoEntity(
    name: '穿云',
    version: '1.10.2',
    buildNumber: '195',
    release: Release.general,
    operatingSystem: 'android',
    operatingSystemVersion: '14',
    environment: Environment.prod,
  );
}

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

class _History extends MuseSpeedHistory {
  @override
  List<int> build() => [for (var i = 0; i < 30; i++) 1000 * i];
}

class _Profiles extends ProfilesNotifier {
  _Profiles(this.count);

  final int count;

  @override
  Stream<List<ProfileEntity>> build() => Stream.value([
    for (var i = 0; i < count; i++)
      ProfileEntity.remote(
        id: 'p$i',
        active: i == 0,
        name: i == 0 ? '一个名字非常非常非常长的机场订阅（备用线路 · 每月 200 GB）' : '订阅 $i',
        url: 'https://sub.example.com/p$i',
        lastUpdate: DateTime(2026, 10),
      ),
  ]);
}

OutboundInfo _node(String tag, String type, int delay, {bool group = false, String pick = ''}) => OutboundInfo(
  tag: tag,
  tagDisplay: tag,
  type: type,
  isGroup: group,
  urlTestDelay: delay,
  urlTestTime: Timestamp.fromDateTime(DateTime.now()),
  groupSelectedTagDisplay: pick,
);

OutboundGroup _group({String selected = '🇬🇧 伦敦 01 · 一个很长很长的节点名字用来测试换行与省略'}) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: selected,
  selectable: true,
  items: [
    _node('自动选择', 'URLTest', 86, group: true, pick: '🇯🇵 东京 02'),
    _node('🇯🇵 东京 02', 'vless', 86),
    _node('🇭🇰 香港 01', 'hysteria2', 42),
    _node('🇸🇬 新加坡 03', 'trojan', 120),
    _node('🇺🇸 洛杉矶 01', 'vless', 386),
    _node('🇹🇼 台北 01', 'vmess', 652),
    _node('🇰🇷 首尔 01', 'anytls', 154),
    _node('🇩🇪 法兰克福 01', 'shadowsocks', 238),
    _node('🇬🇧 伦敦 01 · 一个很长很长的节点名字用来测试换行与省略', 'trojan', 65535),
    for (var i = 0; i < 30; i++) _node('🇺🇸 美国 ${i + 10}', 'vless', 300 + i),
  ],
);

MuseConn _conn(int i) => MuseConn(
  id: 'c$i',
  host: 'host$i.example.com',
  destination: '1.2.3.4:443',
  network: 'tcp',
  inbound: 'mixed',
  chains: const ['🇭🇰 香港 01'],
  rule: 'final',
  process: '',
  upload: i,
  download: i * 10,
  start: DateTime(2026),
);

class _Screen {
  const _Screen(this.name, this.size, {this.mobile = true});

  final String name;
  final Size size;
  final bool mobile;
}

const _screens = [
  _Screen('手机竖屏', Size(360, 740)),
  _Screen('手机横屏', Size(740, 360)),
  _Screen('平板竖屏', Size(800, 1280), mobile: false),
  _Screen('平板横屏', Size(1280, 800), mobile: false),
];

class _Opts {
  const _Opts({
    this.connected = true,
    this.hasProfile = true,
    this.group,
    this.noGroup = false,
    this.prefs = const {},
    this.textScale = 1.0,
  });

  final bool connected;
  final bool hasProfile;
  final OutboundGroup? group;
  final bool noGroup;
  final int profiles = 3;
  final Map<String, Object> prefs;
  final double textScale;
}

List<Override> _overrides(_Opts o, SharedPreferences sp, MuseRequestHistory history) {
  final group = o.noGroup ? null : (o.group ?? _group());
  return [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      appInfoProvider.overrideWith(_Info.new),
      museConnectionProvider.overrideWithValue(AsyncData(o.connected ? const Connected() : const Disconnected())),
      museConnectPreparingProvider.overrideWith((ref) => false),
      museRunningProvider.overrideWithValue(o.connected),
      serviceRunningProvider.overrideWithValue(false),
      museHasProfileProvider.overrideWithValue(o.hasProfile),
      museActiveProfileIdProvider.overrideWithValue(o.hasProfile ? 'p0' : null),
      museActiveProfileNameProvider.overrideWithValue(o.hasProfile ? '订阅 0' : null),
      museAppVersionProvider.overrideWithValue(null),
      museStatsProvider.overrideWithValue(SystemInfo(uplink: Int64(1000), downlink: Int64(2000))),
      museNodeGroupProvider.overrideWithValue(group == null ? const AsyncData(null) : AsyncData(group)),
      museConnectedSinceProvider.overrideWith((ref) async => null),
      museEngineVersionProvider.overrideWith((ref) async => null),
      profilesNotifierProvider.overrideWith(() => _Profiles(o.hasProfile ? o.profiles : 0)),
      museSubInfoProvider.overrideWithValue(null),
      museSpeedHistoryProvider.overrideWith(_History.new),
      museExitProvider.overrideWith((ref) => _Exit()),
      museReachProvider.overrideWith((ref) => _Reach()),
      museLocalApiProvider.overrideWithValue(null),
      museRunningCoreKindProvider.overrideWithValue(MuseCoreKind.standard),
      museConnectionsProvider.overrideWith((ref) => Stream.value(MuseConnState(connections: [for (var i = 0; i < 40; i++) _conn(i)]))),
      museRequestHistoryProvider.overrideWithValue(history),
      museLogsProvider.overrideWith((ref) => Stream.value([for (var i = 0; i < 60; i++) MuseLogLine('info', 'line $i', DateTime(2026))])),
      museDnsQueriesProvider.overrideWith((ref) => Stream.value(const MuseDnsState())),
      museHotkeysForceProvider.overrideWithValue(true),
      museOnDemandForceProvider.overrideWithValue(true),
  ];
}

Future<ProviderContainer> _pump(WidgetTester t, _Screen s, Brightness b, int tab, Widget page, [_Opts o = const _Opts()]) async {
  SharedPreferences.setMockInitialValues({'muse_node_sort': 'delay', ...o.prefs});
  final sp = await SharedPreferences.getInstance();
  final history = MuseRequestHistory();
  for (var i = 0; i < 40; i++) {
    history.add(_conn(1000 + i));
  }
  _sp = sp;
  _history = history;
  final c = ProviderContainer(overrides: _overrides(o, sp, history));
  _live = c;
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  await t.runAsync(() => c.read(translationsProvider.future));
  await t.runAsync(() => c.read(appInfoProvider.future));
  const dpr = 2.0;
  t.view.physicalSize = s.size * dpr;
  t.view.devicePixelRatio = dpr;
  t.platformDispatcher.textScaleFactorTestValue = o.textScale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final theme = AppTheme(b == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light, '');
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: theme.lightTheme(null),
        darkTheme: theme.darkTheme(null),
        themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: MuseShellFrame(isMobile: s.mobile, currentIndex: tab, onTap: (_) {}, child: page),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 200));
  }
  return c;
}

ProviderContainer? _live;
late SharedPreferences _sp;
late MuseRequestHistory _history;

/// No overflow and no other FlutterError since the last check (the whole message on failure).
void _clean(WidgetTester t) {
  final e = t.takeException();
  if (e != null) fail(e is FlutterError ? e.toStringDeep() : '$e');
}

Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  // timers a page started (diagnose's lookups time out after 5 s, providers linger for a minute)
  await t.pump(const Duration(minutes: 2));
  _live?.dispose();
  _live = null;
  await t.pump(const Duration(minutes: 2));
  _clean(t);
}

/// (name, tab, page, options)
final _pages = <(String, int, Widget, _Opts)>[
  ('设置首页', 3, const SettingsPage(), const _Opts()),
  ('设置首页 开发者', 3, const SettingsPage(), const _Opts(prefs: {'muse_dev_mode': true})),
  ('外观 Android', 3, const MuseAppearancePage(android: true, windows: false), const _Opts()),
  ('外观 Windows', 3, const MuseAppearancePage(android: false, windows: true), const _Opts()),
  ('自动连接 Android', 3, const MuseAutoConnectPage(android: true, windows: false), const _Opts()),
  ('自动连接 Windows', 3, const MuseAutoConnectPage(android: false, windows: true), const _Opts()),
  ('网络', 3, const MuseNetworkPage(windows: false), const _Opts()),
  ('网络 Windows', 3, const MuseNetworkPage(windows: true), const _Opts()),
  ('节点设置', 3, const MuseNodeSettingsPage(), const _Opts()),
  ('内核与资源', 3, const MuseResourcesPage(), const _Opts()),
  ('开发者选项', 3, const MuseDeveloperPage(), const _Opts(prefs: {'muse_dev_mode': true})),
  ('关于', 3, const AboutPage(), const _Opts()),
  ('开源许可与致谢', 3, const OpenSourcePage(), const _Opts()),
  ('订阅', 2, const MuseConfigPage(), const _Opts()),
  ('订阅 空', 2, const MuseConfigPage(), const _Opts(hasProfile: false, noGroup: true)),
  ('规则 分流', 2, const MuseRulesPage(), const _Opts()),
  ('规则 订阅覆写', 2, const MuseRulesPage(initialTab: MuseRulesTab.overrides), const _Opts()),
  ('分流', 2, const MuseRoutingPage(), const _Opts()),
  ('预设', 2, const MusePresetsPage(), const _Opts()),
  ('指定节点', 2, const MuseNodeRulesPage(), const _Opts()),
  ('远程规则集', 2, const MuseRemoteRuleSetsPage(), const _Opts()),
  ('规则测试', 2, const MuseRuleTesterPage(), const _Opts()),
  ('订阅覆写', 2, const MuseSubOverridePage(profileId: 'p0', profileName: '一个名字非常非常非常长的机场订阅（备用线路 · 每月 200 GB）'), const _Opts()),
  ('覆写 JSON', 2, const MuseOverrideJsonPage(profileId: 'p0', profileName: '一个名字非常非常非常长的机场订阅（备用线路 · 每月 200 GB）'), const _Opts()),
  ('节点 已连接', 1, const MuseNodesPage(), const _Opts()),
  ('节点 按地区', 1, const MuseNodesPage(), const _Opts(prefs: {'muse_node_sort': 'region'})),
  ('节点 卡片', 1, const MuseNodesPage(), const _Opts(prefs: {'muse_node_layout': 'grid'})),
  ('节点 未连接', 1, const MuseNodesPage(), const _Opts(connected: false)),
  ('节点 无订阅', 1, const MuseNodesPage(), const _Opts(connected: false, hasProfile: false, noGroup: true)),
  ('节点 空列表', 1, const MuseNodesPage(), _Opts(group: OutboundGroup(tag: 'select', type: 'selector', selected: '', selectable: true))),
  for (final tab in MuseActivityTab.values) ('活动 ${tab.title}', 3, MuseActivityPage(initial: tab), const _Opts()),
];

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    final mode = b == Brightness.light ? '浅色' : '深色';
    for (final s in _screens) {
      for (final p in _pages) {
        testWidgets('${s.name} $mode: ${p.$1}', (t) async {
          await _pump(t, s, b, p.$2, p.$3, p.$4);
          _clean(t);
          await _done(t);
        });
      }
    }
  }

  // large text on the narrowest phone: the rows that moved in 1.10.0
  for (final p in _pages.where((e) => const ['设置首页', '外观 Android', '自动连接 Android', '网络', '节点 已连接', '关于', '活动 连接', '活动 诊断', '规则 分流'].contains(e.$1))) {
    testWidgets('320 宽 大字号 1.3: ${p.$1}', (t) async {
      await _pump(t, const _Screen('窄', Size(320, 640)), Brightness.light, p.$2, p.$3, _Opts(prefs: p.$4.prefs, textScale: 1.3));
      _clean(t);
      await _done(t);
    });
  }

  group('节点页 ⋯ 菜单', () {
    const phone = _Screen('手机', Size(360, 740));
    Future<void> openMore(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('node_more_button')));
      await t.pumpAndSettle();
    }

    testWidgets('every entry opens what it says, nothing throws', (t) async {
      await _pump(t, phone, Brightness.light, 1, const MuseNodesPage(), const _Opts(prefs: {'muse_node_tags': ''}));
      await openMore(t);
      for (final k in ['sort', 'select', 'settings']) {
        expect(find.byKey(ValueKey('node_more_$k')), findsOneWidget, reason: k);
      }
      // 1.11.0 (A): one layout (双列卡片), no 布局 entry
      expect(find.byKey(const ValueKey('node_more_layout')), findsNothing);
      // 排序
      await t.tap(find.byKey(const ValueKey('node_more_sort')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('node_sort_original')));
      await t.pumpAndSettle();
      final sp = await t.runAsync(SharedPreferences.getInstance);
      expect(sp!.getString('muse_node_sort'), 'original');
      // 筛选 (several protocols)
      await openMore(t);
      await t.tap(find.byKey(const ValueKey('node_more_filter')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('node_filter_p_VLESS')).hitTestable().evaluate().isEmpty
          ? find.byKey(const ValueKey('node_filter_all'))
          : find.byKey(const ValueKey('node_filter_p_VLESS')));
      await t.pumpAndSettle();
      // 滚动到当前节点
      await openMore(t);
      await t.tap(find.byKey(const ValueKey('node_more_locate')));
      await t.pumpAndSettle();
      // 节点设置
      await openMore(t);
      await t.tap(find.byKey(const ValueKey('node_more_settings')));
      await t.pumpAndSettle();
      expect(find.byType(MuseNodeSettingsPage), findsOneWidget);
      _clean(t);
      await _done(t);
    });

    testWidgets('多选 then 完成 leaves 多选', (t) async {
      await _pump(t, phone, Brightness.dark, 1, const MuseNodesPage());
      await openMore(t);
      await t.tap(find.byKey(const ValueKey('node_more_select')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('node_batch_bar')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('node_select_button')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('node_batch_bar')), findsNothing);
      _clean(t);
      await _done(t);
    });

    testWidgets('no subscription / disconnected: the page opens without auto-scroll errors', (t) async {
      for (final o in const [
        _Opts(connected: false, hasProfile: false, noGroup: true),
        _Opts(connected: false),
      ]) {
        await _pump(t, phone, Brightness.light, 1, const MuseNodesPage(), o);
        _clean(t);
        await _done(t);
      }
    });
  });

  group('1.10.2 修复', () {
    const phone = _Screen('手机', Size(360, 740));
    double offset(WidgetTester t) => t
        .state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('home_node_list')), matching: find.byType(Scrollable)).first)
        .position
        .pixels;
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('节点页: opens at the node in use, 测速 and ⋯ stay on screen; re-entering scrolls only after the node changed', (t) async {
      final visible = ValueNotifier(true);
      const far = '🇬🇧 伦敦 01 · 一个很长很长的节点名字用来测试换行与省略';
      final page = ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, v, _) => TickerMode(enabled: v, child: const MuseNodesPage()),
      );
      final c = await _pump(t, phone, Brightness.light, 1, page);
      await settle(t);
      expect(offset(t), greaterThan(0), reason: 'scrolled to the node in use');
      expect(find.byKey(const ValueKey('node_more_button')).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('node_test_button')).hitTestable(), findsOneWidget);
      expect(find.byKey(ValueKey(far)).hitTestable(), findsWidgets);

      // the user scrolls back up, leaves and comes back: nothing changed, the list stays put
      t.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('home_node_list')), matching: find.byType(Scrollable)).first).position.jumpTo(0);
      await t.pump();
      visible.value = false;
      await settle(t);
      visible.value = true;
      await settle(t);
      expect(offset(t), 0);

      // another node was picked elsewhere (首页) while the page was hidden: it opens at that one
      visible.value = false;
      await t.pump();
      const other = '🇺🇸 美国 35';
      c.updateOverrides(_overrides(_Opts(group: _group(selected: other)), _sp, _history));
      await settle(t);
      visible.value = true;
      await settle(t);
      expect(offset(t), greaterThan(0));
      expect(find.byKey(const ValueKey(other)).hitTestable(), findsWidgets);
      _clean(t);
      await _done(t);
    });

    testWidgets('museScrollToKey: the list going away mid-search ends it quietly', (t) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final never = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          home: ListView.builder(controller: scroll, itemCount: 500, itemExtent: 40, itemBuilder: (_, i) => Text('row $i')),
        ),
      );
      bool? result;
      unawaited(museScrollToKey(scroll, never).then((v) => result = v));
      await t.pump();
      await t.pump();
      await t.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(result, isFalse);
      _clean(t);
    });

    testWidgets('活动 › 连接 on a phone held sideways: the header scrolls with the list, no overflow', (t) async {
      await _pump(t, const _Screen('手机横屏', Size(740, 360)), Brightness.dark, 3, const MuseActivityPage());
      _clean(t);
      expect(find.byType(CustomScrollView), findsWidgets);
      expect(find.byKey(const ValueKey('conn_search')), findsOneWidget);
      await _done(t);
    });

    for (final android in [true, false]) {
      testWidgets('外观: 在最近任务中隐藏 ${android ? 'on Android, saved under exclude_from_recents' : 'not on Windows'}', (t) async {
        await _pump(t, phone, Brightness.light, 3, MuseAppearancePage(android: android, windows: !android));
        final row = find.byKey(const ValueKey('settings_exclude_recents'), skipOffstage: false);
        if (!android) {
          expect(row, findsNothing);
          await _done(t);
          return;
        }
        expect(row, findsOneWidget);
        expect(find.text(museExcludeRecentsTitle, skipOffstage: false), findsOneWidget);
        // 1.19.0: 外观 多了「首页样式」「主题」两行，这一行在手机上滚到屏幕外了，先滚到可见再操作
        await t.ensureVisible(row);
        await t.pump();
        final sw = t.widget<Switch>(find.descendant(of: row, matching: find.byType(Switch), skipOffstage: false));
        expect(sw.value, isFalse);
        sw.onChanged!(true);
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
        expect(_sp.getBool('exclude_from_recents'), isTrue);
        _clean(t);
        await _done(t);
      });
    }
  });
}
