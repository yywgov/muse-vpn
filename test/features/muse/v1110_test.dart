// 穿云 1.11.0: 精简批 + 节点页 A 双列卡片 + 6 项优化（失效自动切换、桌面小组件、APK 瘦身、首页、订阅进度条与提醒、冷启动）。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/core/preferences/general_preferences.dart' show museDefaultHiddenTiles;
import 'package:hiddify/features/muse/data/bundled_rule_sets.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/muse_prefs_migration.dart';
import 'package:hiddify/features/muse/data/sync_service.dart' show museSyncedPrefs;
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/node_failover.dart';
import 'package:hiddify/features/muse/home/node_label.dart' show museRegionCode;
import 'package:hiddify/features/muse/home/subscription_alert.dart';
import 'package:hiddify/features/muse/home/widget_sync.dart';
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart' show MuseNodeMetas;
import 'package:hiddify/features/muse/logic/resources.dart' show museCoreRelease;
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/logic/subscription_bar.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart' show MuseGroupedBody;
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
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
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
import 'package:hiddify/features/muse/nodes/node_list.dart';
import 'package:hiddify/features/muse/settings/auto_connect_page.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
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
    this.group,
    this.prefs = const {},
    this.textScale = 1.0,
  });

  final bool connected;
  bool get hasProfile => true;
  final OutboundGroup? group;
  bool get noGroup => false;
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

String _src(String p) => File(p).readAsStringSync();

Finder get _bodyScroll => find.descendant(of: find.byType(MuseGroupedBody), matching: find.byType(Scrollable)).first;

MuseNodeSample _s(String tag, int delay, {String? region, bool group = false}) =>
    MuseNodeSample(tag: tag, delay: delay, testedAt: 1, isGroup: group, region: region);

void main() {
  // ------------------------------------------------------------------ 1 节点失效自动切换
  group('节点失效自动切换', () {
    test('stand-in: fastest working node of the same region first', () {
      final items = [_s('lowest', 80, group: true), _s('US1', 65535, region: 'us'), _s('US2', 300, region: 'us'), _s('US3', 200, region: 'us'), _s('JP1', 90, region: 'jp')];
      expect(museFailoverTarget(failed: items[1], items: items, autoTag: 'lowest'), 'US3');
    });

    test('no working node in the region: 自动最快, else the fastest node', () {
      final items = [_s('US1', 65535, region: 'us'), _s('US2', 65535, region: 'us'), _s('JP1', 150, region: 'jp'), _s('SG1', 90, region: 'sg')];
      expect(museFailoverTarget(failed: items[0], items: items, autoTag: 'lowest'), 'lowest');
      expect(museFailoverTarget(failed: items[0], items: items, autoTag: null), 'SG1');
      expect(museFailoverTarget(failed: items[0], items: [items[0], items[1]], autoTag: null), isNull);
    });

    test('tracker: two fresh failures switch within the region, recovery switches back', () {
      final f = MuseFailoverTracker();
      List<MuseNodeSample> items(int a, int t) => [
        MuseNodeSample(tag: 'A', delay: a, testedAt: t, region: 'hk'),
        MuseNodeSample(tag: 'B', delay: 120, testedAt: t, region: 'hk'),
        MuseNodeSample(tag: 'C', delay: 60, testedAt: t, region: 'jp'),
      ];
      expect(f.update(selected: 'A', items: items(65535, 1), autoTag: null), isNull);
      expect(f.update(selected: 'A', items: items(65535, 2), autoTag: null), 'B');
      expect(f.standIn, 'B');
      expect(f.update(selected: 'B', items: items(100, 3), autoTag: null), isNull);
      expect(f.update(selected: 'B', items: items(110, 4), autoTag: null), 'A');
      expect(f.active, isFalse);
    });

    test('own switch, on by default; acts on test results only (no timer)', () {
      expect(_src('lib/features/muse/data/muse_prefs.dart'), contains('PreferencesNotifier.create<bool, bool>("muse_auto_failover", true)'));
      final p = _src('lib/features/muse/home/node_failover.dart');
      expect(p, contains('ref.watch(MusePrefs.autoFailover)'));
      expect(p, isNot(contains('Timer')));
      expect(p, contains('showInfoToast'));
    });

    test('toast text', () {
      expect(museFailoverToast(from: '香港 01', to: '香港 02', back: false), '「香港 01」连续测速失败，已自动切换到「香港 02」');
      expect(museFailoverToast(from: '香港 02', to: '香港 01', back: true), '「香港 01」已恢复，已换回');
    });

    test('samples carry the region (set by hand, else from the name)', () {
      final g = OutboundGroup(tag: 'select', selected: 'a', items: [
        OutboundInfo(tag: 'a', tagDisplay: '🇭🇰 香港 01', type: 'vless'),
        OutboundInfo(tag: 'b', tagDisplay: '日本 02', type: 'vless'),
        OutboundInfo(tag: 'auto', type: 'urltest', isGroup: true),
      ]);
      final s = museFailoverSamples(g, MuseNodeMetas.parse(''));
      expect(s[0].region, isNotNull);
      expect(s[0].region, museRegionCode('🇭🇰 香港 01'));
      expect(s[2].region, isNull);
    });
  });

  // ------------------------------------------------------------------ 精简
  group('精简：设置', () {
    test('设置首页 has seven rows (备份与同步 gone)', () {
      // 1.20.2：「网络」下面加「分流规则」
      expect(museSettingsHomeRows(android: true, developer: false), ['外观', '自动连接', '分应用代理', '网络', '分流规则', '活动', '内核与资源', '关于']);
    });

    test('removed settings are not found by search; moved ones point at 高级', () {
      for (final q in ['配色风格', '文字缩放', '隐藏桌面图标', '局域网同步', 'WebDAV', '每周本地快照', '连接质量提醒', 'CSV']) {
        expect(museSearchSettings(q, android: true, windows: true).map((e) => e.title), isNot(contains(q)), reason: q);
      }
      expect(museSearchSettings('订阅 UA', android: true, windows: false).first.page, MuseSettingPage.nodesAdvanced);
      expect(museSearchSettings('重复判断', android: true, windows: false).first.page, MuseSettingPage.nodesAdvanced);
      expect(museSearchSettings('Fake-IP', android: true, windows: false).first.page, MuseSettingPage.advanced);
      expect(museSearchSettings('TLS 分片', android: true, windows: false).first.page, MuseSettingPage.network);
      expect(museSearchSettings('窗口置顶', android: false, windows: true).first.page, MuseSettingPage.windowAdvanced);
      expect(museSearchSettings('快捷键', android: false, windows: true).first.page, MuseSettingPage.windowAdvanced);
      expect(museSearchSettings('导出配置', android: true, windows: false).first.page, MuseSettingPage.sync);
      expect(MuseSettingPage.sync.path, '设置 › 关于 › 导出 / 导入配置');
      // old names still lead to the new place
      expect(museSearchSettings('备份与同步', android: true, windows: false).first.page, MuseSettingPage.sync);
      expect(museSearchSettings('自动运行', android: true, windows: false).first.title, '打开即连接');
      expect(museSearchSettings('节点失效', android: true, windows: false).first.page, MuseSettingPage.nodes);
    });

    test('migration 3→4 hides 内网 IP once, leaves everything else (removed settings are ignored, not deleted)', () {
      final prefs = <String, Object?>{'muse_prefs_version': 3, 'muse_home_tiles_hidden': 'adblock', 'muse_text_scale_on': true, 'muse_color_style': 'vibrant'};
      expect(musePrefsMigrate(prefs), 4);
      expect(prefs['muse_home_tiles_hidden'], 'adblock,lanip');
      expect(prefs['muse_text_scale_on'], true);
      expect(prefs['muse_color_style'], 'vibrant');
      expect(musePrefsMigrate(prefs), 4);
      expect(prefs['muse_home_tiles_hidden'], 'adblock,lanip');
      final fresh = <String, Object?>{'muse_prefs_version': 3};
      musePrefsMigrate(fresh);
      expect(fresh.containsKey('muse_home_tiles_hidden'), isFalse);
      expect(museDefaultHiddenTiles.split(','), contains('lanip'));
    });

    test('配色风格 fixed to 忠实, text follows the system; old backups still import', () {
      final app = _src('lib/features/app/widget/app.dart');
      expect(app, contains('museApplyColorStyle(museDefaultColorStyle);'));
      expect(app, isNot(contains('MusePrefs.textScaleOn')));
      expect(app, isNot(contains('MusePrefs.colorStyle')));
      for (final k in ['muse_color_style', 'muse_text_size', 'muse_text_scale_on', 'muse_text_scale_pct']) {
        expect(museSyncedPrefs.containsKey(k), isFalse, reason: k);
      }
      expect(museSyncedPrefs.containsKey('muse_accent'), isTrue);
      // apply() skips keys it does not know: an old backup with them imports the rest
      expect(_src('lib/features/muse/data/sync_service.dart'), contains('if (provider == null) continue;'));
    });

    test('WebDAV / 局域网同步 / 自动备份 / 每周快照 / 连接质量提醒 / 隐藏桌面图标 code is gone', () {
      expect(File('lib/features/muse/data/lan_sync_service.dart').existsSync(), isFalse);
      expect(File('lib/features/muse/logic/lan_sync.dart').existsSync(), isFalse);
      final sync = _src('lib/features/muse/data/sync_service.dart');
      for (final s in ['syncNow', 'autoBackup(', 'weeklySnapshotIfDue', 'MusePrefs.webdav', 'Dio(']) {
        expect(sync, isNot(contains(s)), reason: s);
      }
      expect(_src('lib/features/muse/home/net_watch.dart'), isNot(contains('museQualityAlertProvider')));
      expect(_src('lib/features/muse/settings/android_settings.dart'), isNot(contains('settings_hide_icon')));
      // an icon hidden by an older version comes back once
      expect(_src('lib/features/muse/settings/android_settings.dart'), contains('setLauncherIconHidden(false)'));
      expect(_src('lib/features/muse/settings/stats_page.dart'), isNot(contains('stats_export_csv')));
    });
  });

  group('精简：页面', () {
    testWidgets('自动连接 (Android): only 打开即连接 until 「更多」', (t) async {
      await _pump(t, _screens[0], Brightness.light, 3, const MuseAutoConnectPage(android: true, windows: false));
      expect(find.text('打开即连接'), findsOneWidget);
      expect(find.byKey(const ValueKey('keep_alive')), findsNothing);
      expect(find.byKey(const ValueKey('settings_on_demand')), findsNothing);
      expect(find.byKey(const ValueKey('network_schedule_connect')), findsNothing);
      await t.tap(find.byKey(const ValueKey('auto_connect_more')));
      await t.pump();
      expect(find.byKey(const ValueKey('keep_alive')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_on_demand')), findsOneWidget);
      expect(find.byKey(const ValueKey('network_schedule_connect')), findsOneWidget);
      await _done(t);
    });

    testWidgets('自动连接 (Windows): 开机自启 in view, 静默启动 in 「更多」', (t) async {
      await _pump(t, _screens[2], Brightness.dark, 3, const MuseAutoConnectPage(android: false, windows: true));
      expect(find.text('打开即连接'), findsNothing);
      expect(find.byKey(const ValueKey('settings_silent_start')), findsNothing);
      await t.tap(find.byKey(const ValueKey('auto_connect_more')));
      await t.pump();
      expect(find.byKey(const ValueKey('settings_silent_start')), findsOneWidget);
      await _done(t);
    });

    testWidgets('外观: no 配色风格 / 文字缩放; Windows window rows behind 高级', (t) async {
      await _pump(t, _screens[2], Brightness.light, 3, const MuseAppearancePage(android: true, windows: true));
      expect(find.byKey(const ValueKey('appearance_color_style')), findsNothing);
      expect(find.byKey(const ValueKey('appearance_text_scale')), findsNothing);
      expect(find.byKey(const ValueKey('settings_hide_icon')), findsNothing);
      expect(find.byKey(const ValueKey('settings_close_action')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_always_on_top')), findsNothing);
      await t.scrollUntilVisible(find.byKey(const ValueKey('window_advanced_fold')), 200, scrollable: _bodyScroll);
      await t.ensureVisible(find.byKey(const ValueKey('window_advanced_fold')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('window_advanced_fold')));
      await t.pump();
      // 1.20.1: 外观 opens with the 首页风格 previews, so the unfolded rows are built once scrolled to
      for (final k in ['settings_always_on_top', 'settings_custom_title_bar', 'settings_hotkeys']) {
        await t.scrollUntilVisible(find.byKey(ValueKey(k)), 200, scrollable: _bodyScroll);
        expect(find.byKey(ValueKey(k)), findsOneWidget);
      }
      await _done(t);
    });

    testWidgets('网络: 连接质量提醒 gone, four rows behind 高级 (opened for a search result)', (t) async {
      await _pump(t, _screens[0], Brightness.light, 3, const MuseNetworkPage(windows: false));
      expect(find.byKey(const ValueKey('network_quality_alert')), findsNothing);
      expect(find.byKey(const ValueKey('network_tls_tricks')), findsOneWidget);
      expect(find.byKey(const ValueKey('block_quic')), findsOneWidget);
      for (final k in ['balancer_strategy', 'ipv6_policy', 'fake_ip', 'settings_auto_close']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      await t.tap(find.byKey(const ValueKey('network_advanced_fold')));
      await t.pump();
      for (final k in ['balancer_strategy', 'ipv6_policy', 'fake_ip', 'settings_auto_close']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await _done(t);
      await _pump(t, _screens[0], Brightness.light, 3, const MuseNetworkPage(windows: false, advancedOpen: true));
      expect(find.byKey(const ValueKey('fake_ip')), findsOneWidget);
      await _done(t);
    });

    testWidgets('节点设置: 节点失效自动切换 on top (on), 订阅 UA / 重复判断 behind 高级', (t) async {
      await _pump(t, _screens[0], Brightness.light, 3, const MuseNodeSettingsPage());
      expect(find.text(museAutoFailoverTitle), findsOneWidget);
      final sw = t.widget<Switch>(find.descendant(of: find.byKey(const ValueKey('node_auto_failover')), matching: find.byType(Switch)));
      expect(sw.value, isTrue);
      expect(find.byKey(const ValueKey('node_sub_ua')), findsNothing);
      expect(find.byKey(const ValueKey('node_dedup_mode')), findsNothing);
      await t.scrollUntilVisible(find.byKey(const ValueKey('node_advanced_fold')), 200, scrollable: _bodyScroll);
      await t.tap(find.byKey(const ValueKey('node_advanced_fold')));
      await t.pump();
      expect(find.byKey(const ValueKey('node_sub_ua')), findsOneWidget);
      expect(find.byKey(const ValueKey('node_dedup_mode')), findsOneWidget);
      await _done(t);
    });

    testWidgets('关于: 导出配置 / 导入配置 / 开源许可与致谢 at the bottom', (t) async {
      await _pump(t, _screens[0], Brightness.light, 3, const AboutPage());
      expect(find.text('导出配置'), findsOneWidget);
      expect(find.text('导入配置'), findsOneWidget);
      expect(find.byKey(const ValueKey('about_open_source')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('about_export_config')));
      await t.pump();
      expect(find.byType(MuseExportBackupDialog), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('backup_export_cancel')));
      await t.pump();
      await _done(t);
    });
  });

  // ------------------------------------------------------------------ 节点页 A
  group('节点页 A 双列卡片', () {
    // 1.20.1：原断言「自动最快 184」删去——用户要求「自动最快」后不再显示延迟数字
    test('modes: 手动选择 + groups (自动最快 without a delay since 1.20.1, 负载均衡)', () {
      final groups = [
        OutboundInfo(tag: 'auto', tagDisplay: '自动选择', type: 'URLTest', isGroup: true, urlTestDelay: 184),
        OutboundInfo(tag: 'lb', tagDisplay: '负载均衡', type: 'balancer', isGroup: true),
      ];
      final modes = museNodeModes(groups, delayOf: (g) => g.urlTestDelay);
      expect(modes.map((e) => e.label), ['手动选择', '自动最快', '负载均衡']);
      expect(modes.any((m) => RegExp(r'\d').hasMatch(m.label)), isFalse, reason: '分段控件里不再出现延迟数字');
      expect(museNodeModeOf(modes, 'auto'), 'auto');
      expect(museNodeModeOf(modes, 'some node'), 'manual');
      expect(museNodeModes(const [], delayOf: (_) => 0), isEmpty);
    });

    test('手动选择 from a group: recent node, else fastest tested, else first', () {
      final nodes = [OutboundInfo(tag: 'a', urlTestDelay: 300), OutboundInfo(tag: 'b', urlTestDelay: 90), OutboundInfo(tag: 'c')];
      expect(museManualPick(recent: ['x', 'c'], nodes: nodes, delayOf: (e) => e.urlTestDelay), 'c');
      expect(museManualPick(recent: const [], nodes: nodes, delayOf: (e) => e.urlTestDelay), 'b');
      expect(museManualPick(recent: const [], nodes: [OutboundInfo(tag: 'z')], delayOf: (_) => 0), 'z');
      expect(museManualPick(recent: const [], nodes: const [], delayOf: (_) => 0), isNull);
    });

    test('two columns on a phone, more on a wide window', () {
      expect(museNodeColumnsA(328), 2);
      expect(museNodeColumnsA(1232), greaterThanOrEqualTo(4));
      expect(museNodeColumnsA(150), 1);
      expect(museDelayParts(const MuseDelayView(MuseDelayKind.live, 167)), (number: '167', unit: 'ms'));
      expect(museDelayParts(const MuseDelayView(MuseDelayKind.timeout, 0)), (number: '超时', unit: ''));
    });

    for (final s in _screens) {
      for (final b in Brightness.values) {
        testWidgets('节点页 cards + mode bar, ${s.name} ${b.name}', (t) async {
          await _pump(t, s, b, 1, const MuseNodesPage(), _Opts(prefs: const {'muse_node_layout': 'list'}, group: _group(selected: '🇭🇰 香港 01')));
          expect(find.byKey(const ValueKey('node_mode_bar')), findsOneWidget);
          expect(find.text('手动选择'), findsOneWidget);
          expect(find.textContaining('自动最快'), findsWidgets);
          expect(find.byType(MuseNodeCard), findsWidgets);
          expect(find.byType(MuseNodeRow), findsNothing);
          // the selected card: tick + accent fill
          expect(find.byKey(const ValueKey('node_card_tick')), findsOneWidget);
          expect(find.byKey(const ValueKey('node_test_button')), findsOneWidget);
          // 1.20.1：标题下不再有「订阅名 · N 个节点」；搜索 / 测速 / ⋯ 右对齐，左侧不留文字；「自动最快」不带数字
          expect(find.textContaining('个节点'), findsNothing);
          expect(find.byKey(const ValueKey('node_count_label')), findsNothing);
          final mode = find.descendant(of: find.byKey(const ValueKey('node_mode_bar')), matching: find.textContaining('自动最快'));
          for (final e in mode.evaluate()) {
            final text = (e.widget as Text).data ?? '';
            expect(RegExp(r'\d').hasMatch(text), isFalse, reason: text);
          }
          final barRight = t.getTopRight(find.byKey(const ValueKey('node_mode_bar'))).dx;
          final more = find.byKey(const ValueKey('node_more_button'));
          final testBtn = t.getTopRight(find.byKey(const ValueKey('node_test_button'))).dx;
          expect(more.evaluate().isEmpty ? testBtn : t.getTopRight(more).dx, greaterThan(barRight - 56), reason: '按钮右对齐');
          // 标题与按钮同一行（不再多一行空着的左侧），按钮点击区域 ≥ 48dp
          final title = t.getRect(find.byKey(const ValueKey('muse_page_title')));
          for (final k in ['node_search_button', 'node_test_button', 'node_more_button']) {
            final f = find.byKey(ValueKey(k));
            if (f.evaluate().isEmpty) continue;
            final r = t.getRect(f);
            expect(r.height, greaterThanOrEqualTo(48), reason: '$k 高 ${r.height}');
            expect(r.width, greaterThanOrEqualTo(48), reason: '$k 宽 ${r.width}');
            expect((r.center.dy - title.center.dy).abs(), lessThan(12), reason: '$k 与标题同一行');
          }
          _clean(t);
          await _done(t);
        });
      }
    }

    testWidgets('large text, narrow phone: no overflow', (t) async {
      await _pump(t, const _Screen('窄', Size(320, 640)), Brightness.light, 1, const MuseNodesPage(), const _Opts(textScale: 1.3));
      expect(find.byType(MuseNodeCard), findsWidgets);
      _clean(t);
      await _done(t);
    });

    testWidgets('a card: region, bold name, protocol tag, coloured delay + small ms', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 170,
            height: museNodeCardExtentA((v) => v),
            child: MuseNodeCard(
              proxy: OutboundInfo(tag: 'x', tagDisplay: '🇺🇸 DediRock-HY2', type: 'hysteria2', urlTestDelay: 167, urlTestTime: Timestamp.fromDateTime(DateTime.now())),
              since: null,
              selected: true,
              onTap: () {},
            ),
          ),
        ),
      ));
      expect(find.text('DediRock-HY2'), findsOneWidget);
      expect(find.text('美国'), findsOneWidget);
      expect(find.byKey(const ValueKey('node_protocol_tag')), findsOneWidget);
      expect(find.byKey(const ValueKey('node_card_tick')), findsOneWidget);
      expect(find.textContaining('167'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    test('the sheet and the side column keep rows; layout menu item gone from the page', () {
      final s = _src('lib/features/muse/nodes/node_list.dart');
      expect(s, contains('final cardsA = !embedded;'));
      expect(s, isNot(contains("('layout', '布局")));
    });
  });

  // ------------------------------------------------------------------ 小组件
  group('Android 桌面小组件', () {
    test('event driven: no update period, redrawn on status / node change only', () {
      expect(_src('android/app/src/main/res/xml/chuanyun_widget_info.xml'), contains('android:updatePeriodMillis="0"'));
      final m = _src('android/app/src/main/AndroidManifest.xml');
      expect(m, contains('android:name=".bg.ChuanyunWidget"'));
      expect(m, contains('@xml/chuanyun_widget_info'));
      final kt = _src('android/app/src/main/kotlin/com/hiddify/hiddify/bg/ChuanyunWidget.kt');
      expect(kt, contains('QuickActionActivity.ACTION_TOGGLE'));
      expect(kt, isNot(contains('AlarmManager')));
      expect(kt, isNot(contains('Handler(')));
      expect(_src('android/app/src/main/kotlin/com/hiddify/hiddify/bg/BoxService.kt'), contains('ChuanyunWidget.onStatus(it)'));
      expect(_src('android/app/src/main/kotlin/com/hiddify/hiddify/bg/CompatService.kt'), contains('ChuanyunWidget.onStatus(it)'));
      expect(_src('android/app/src/main/kotlin/com/hiddify/hiddify/ChuanyunHandler.kt'), contains('"widget_update"'));
      expect(_src('lib/features/muse/home/widget_sync.dart'), isNot(contains('Timer')));
    });

    test('what the widget shows for the pick', () {
      final g = OutboundGroup(tag: 'select', selected: 'a', items: [
        OutboundInfo(tag: 'a', tagDisplay: '🇭🇰 香港 01', type: 'vless', urlTestDelay: 88),
        OutboundInfo(tag: 'auto', tagDisplay: '自动选择', type: 'urltest', isGroup: true, groupSelectedTagDisplay: '🇯🇵 东京 02', urlTestDelay: 70),
      ]);
      expect(museWidgetNode(g), ('香港 01', 88));
      expect(museWidgetNode(g.deepCopy()..selected = 'auto').$1, contains('东京 02'));
      expect(museWidgetNode(null), ('', 0));
      expect(museWidgetNode(g.deepCopy()..items[0].urlTestDelay = 65535).$2, 0);
    });
  });

  // ------------------------------------------------------------------ 首页
  group('首页', () {
    test('网速 is idle while disconnected or with a few quiet samples', () {
      expect(museSpeedIdle(running: false, history: const [5000, 6000]), isTrue);
      expect(museSpeedIdle(running: true, history: const [0, 0]), isFalse);
      expect(museSpeedIdle(running: true, history: const [9000, 10, 0, 500]), isTrue);
      expect(museSpeedIdle(running: true, history: const [10, 0, 50000]), isFalse);
    });

    test('今日流量 from the traffic log', () {
      final now = DateTime(2026, 11, 6, 9);
      final log = MuseTrafficLog.empty.add(now, 100, 900).add(DateTime(2026, 11, 5), 5, 5).toRaw();
      expect(museTodayTraffic(log, now), (100, 900));
      expect(museTodayTraffic('', now), (0, 0));
    });

    testWidgets('disconnected: the 网速 tile shows 今日流量; the 内网 IP tile is hidden by default', (t) async {
      final today = MuseTrafficLog.empty.add(DateTime.now(), 1024 * 1024, 3 * 1024 * 1024).toRaw();
      await _pump(t, _screens[0], Brightness.light, 0, const MuseHomePage(), _Opts(connected: false, prefs: {'muse_traffic_log': today}));
      expect(find.text('今日流量'), findsOneWidget);
      expect(find.byKey(const ValueKey('tile_speed_today')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile_lanip')), findsNothing);
      _clean(t);
      await _done(t);
    });
  });

  // ------------------------------------------------------------------ 订阅
  group('订阅流量 / 到期', () {
    final now = DateTime(2026, 11, 6);
    const gb = 1024 * 1024 * 1024;
    test('two bars, warn at ≤10 % / ≤3 days', () {
      final bars = museSubscriptionBars(SubscriptionInfo(upload: 0, download: 95 * gb, total: 100 * gb, expire: DateTime(2026, 11, 8)), now: now);
      expect(bars.map((e) => e.kind), ['traffic', 'expiry']);
      expect(bars[0].warn, isTrue);
      expect(bars[0].trailing, '剩 5%');
      expect(bars[1].warn, isTrue);
      final ok = museSubscriptionBars(SubscriptionInfo(upload: 0, download: 10 * gb, total: 100 * gb, expire: DateTime(2026, 12, 6)), now: now);
      expect(ok.every((e) => !e.warn), isTrue);
      expect(ok[1].trailing, '剩 30 天');
      expect(museSubscriptionBars(SubscriptionInfo(upload: 0, download: 0, total: 0, expire: DateTime(1970)), now: now), isEmpty);
    });

    test('reminder once at ≤10 % or ≤3 days (no 80 % reminder any more)', () {
      List<String> keys(int used, DateTime expire) => [
        for (final a in museSubscriptionAlerts(profileId: 'p', upload: 0, download: used, total: 100 * gb, expire: expire, now: now)) a.key.split(':')[1],
      ];
      expect(keys(85 * gb, DateTime(2027)), isEmpty);
      expect(keys(91 * gb, DateTime(2027)), ['traffic90']);
      expect(keys(10 * gb, DateTime(2026, 11, 8)), ['expire']);
    });
  });

  // ------------------------------------------------------------------ 冷启动
  group('冷启动', () {
    test('bundled lists are copied once per app build', () {
      final dir = Directory.systemTemp.createTempSync('cy_rs');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(museBundledRuleSetsCurrent(saved: null, stamp: '1.11.0+197', baseDir: dir.path), isFalse);
      Directory('${dir.path}/rule-sets').createSync();
      for (final n in museBundledRuleSets) {
        File('${dir.path}/rule-sets/$n.srs').writeAsStringSync('x');
      }
      expect(museBundledRuleSetsCurrent(saved: '1.11.0+197', stamp: '1.11.0+197', baseDir: dir.path), isTrue);
      expect(museBundledRuleSetsCurrent(saved: '1.10.3+196', stamp: '1.11.0+197', baseDir: dir.path), isFalse);
      File('${dir.path}/rule-sets/${museBundledRuleSets.first}.srs').deleteSync();
      expect(museBundledRuleSetsCurrent(saved: '1.11.0+197', stamp: '1.11.0+197', baseDir: dir.path), isFalse);
    });

    testWidgets('measured: the start-up rule-set step before / after (sandbox, test asset bundle)', (t) async {
      await t.runAsync(() async {
        final dir = Directory.systemTemp.createTempSync('cy_cold');
        // first install (a new version): both versions copy the files once
        await museInstallBundledRuleSets(dir.path);
        // every later start, before 1.11.0: every list read from the bundle to compare sizes
        final before = Stopwatch()..start();
        for (var i = 0; i < 5; i++) {
          await museInstallBundledRuleSets(dir.path, bundle: _FreshBundle());
        }
        before.stop();
        // 1.11.0: a stamp check (stat of each file)
        final after = Stopwatch()..start();
        for (var i = 0; i < 5; i++) {
          expect(museBundledRuleSetsCurrent(saved: 's', stamp: 's', baseDir: dir.path), isTrue);
        }
        after.stop();
        // ignore: avoid_print
        print('muse cold start rule-sets step: before ${(before.elapsedMicroseconds / 5000).toStringAsFixed(1)} ms, after ${(after.elapsedMicroseconds / 5000).toStringAsFixed(2)} ms');
        expect(after.elapsedMicroseconds, lessThan(before.elapsedMicroseconds));
        dir.deleteSync(recursive: true);
      });
    });

    test('refresh rate after the first frame; edge-to-edge stays before it', () {
      final b = _src('lib/bootstrap.dart');
      expect(b, contains('museAfterFirstFrame.add(() => _safeInit("android display mode", FlutterDisplayMode.setHighRefreshRate));'));
      expect(b, contains('addPostFrameCallback'));
      expect(b, contains('museRuleSetsStampKey'));
    });
  });

  // ------------------------------------------------------------------ 版本
  test('版本 1.11.0 与更新说明', () {
    // 1.11.0 or later (1.20.0: the pattern takes 1.2x too)
    expect(RegExp(r'version: 1\.(1[1-9]|[2-9]\d)\.').hasMatch(_src('pubspec.yaml')), isTrue);
    final notes = museChangelog['1.11.0']!.join('\n');
    for (final w in ['节点', '小组件', '自动切换', '导出配置', '高级', '更多']) {
      expect(notes, contains(w), reason: w);
    }
    expect(notes.toLowerCase(), isNot(anyOf(contains('sing-box'), contains('hiddify'), contains('mihomo'), contains('clash'))));
    final md = _src('CHANGELOG.md');
    expect(md.indexOf('### 1.11.0'), lessThan(md.indexOf('### 1.10.4')));
    expect(md.indexOf('### 1.10.4'), lessThan(md.indexOf('### 1.10.3')));
    final keys = museChangelog.keys.toList();
    expect(keys.indexOf('1.11.0') + 1, keys.indexOf('1.10.4'));
  });

  // APK 瘦身: the standard core without tor / openvpn / openconnect is a new core release, built from
  // a commit that already has the 1.10.4 测速 (muse.22)
  test('内核 5.0.0-muse.23（瘦身）', () {
    final deps = _src('dependencies.properties');
    expect(deps, contains('muse.core.version=5.0.0-muse.23'));
    expect(museCoreRelease, '5.0.0-muse.23');
    expect(deps, contains('muse.compat.ref=66d82b1502a3b735643faf0e8102aa95f217dd34'));
    expect(int.parse(RegExp(r'muse\.core\.version=5\.0\.0-muse\.(\d+)').firstMatch(deps)!.group(1)!), greaterThan(22));
  });
}

/// An asset bundle without a cache (each load reads the asset again, as a cold start does).
class _FreshBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);
}
