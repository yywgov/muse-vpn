// 穿云 1.22.0：底栏四栏（首页 / 节点 / 流量 / 设置，F1 方向 A）、设置一级 6 组 + 常驻搜索框（F2）、术语统一（F20 界面文案）。
// 旧路由都跳到新位置、1.21 的每个搜索项仍能按原名搜到、存储键不变。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/features/muse/activity/activity_page.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/logic/terms.dart';
import 'package:hiddify/features/muse/settings/auto_connect_page.dart' show museStartupTitle;
import 'package:hiddify/features/muse/settings/more_settings.dart' show MuseRoutingMoreMenu;
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/traffic/traffic_page.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart' show ServiceMode;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

/// v1.21.0 设置搜索索引里的全部标题（a = 仅 Android，w = 仅 Windows，v = 开发者选项，d = 调试测试页）。
const _titles121 = <(String, String)>[
  ('外观', ''),
  ('深浅色', ''),
  ('纯黑', ''),
  ('主题', ''),
  ('配色', ''),
  ('首页风格', ''),
  ('首页样式', ''),
  ('动效', ''),
  ('主题色', ''),
  ('自定义主题色', ''),
  ('编辑首页卡片', ''),
  ('隐私与通知', ''),
  ('隐私', ''),
  ('隐私模式', ''),
  ('敏感页禁止截屏', 'a'),
  ('智能保持连接', ''),
  ('节点失效自动切换', ''),
  ('隐藏通知', 'a'),
  ('去广告', ''),
  ('订阅设置', ''),
  ('订阅自动更新', ''),
  ('更新后测速新增节点', ''),
  ('订阅列表', ''),
  ('请求头', ''),
  ('节点筛选（单个订阅）', ''),
  ('分应用代理', 'a'),
  ('节点设置', ''),
  ('节点', ''),
  ('节点名美化', ''),
  ('隐藏重复节点', ''),
  ('重复判断', ''),
  ('只显示 / 排除', ''),
  ('显示全部已隐藏节点', ''),
  ('订阅 UA', ''),
  ('订阅更新方式', ''),
  ('清除测速记录', ''),
  ('订阅覆写', ''),
  ('分流规则', ''),
  ('规则 / 全局模式', ''),
  ('我的规则', ''),
  ('自定义规则列表', ''),
  ('分流预设', ''),
  ('指定节点', ''),
  ('来自连接的规则', ''),
  ('已屏蔽的网站', ''),
  ('远程规则集', ''),
  ('规则测试', ''),
  ('自定义 hosts', ''),
  ('导入 / 导出 / 粘贴规则', ''),
  ('远程 DNS', ''),
  ('每天定时连接 / 断开', ''),
  ('导出 / 导入配置', ''),
  ('备份与恢复', ''),
  ('备份与同步', ''),
  ('流量统计', ''),
  ('统计', ''),
  ('高级', ''),
  ('负载均衡策略', ''),
  ('TLS 分片', ''),
  ('IPv6', ''),
  ('Fake-IP', ''),
  ('不走代理的地址', 'w'),
  ('允许商店应用走代理', 'w'),
  ('屏蔽 QUIC', ''),
  ('活动', ''),
  ('连接', ''),
  ('日志', ''),
  ('DNS 查询', ''),
  ('切换节点时关闭旧连接', ''),
  ('测速并发数 / 超时', 'v'),
  ('导入后清空剪贴板', ''),
  ('导出为 sing-box 格式', ''),
  ('恢复推荐 DNS', ''),
  ('诊断', ''),
  ('一键诊断', ''),
  ('出口与解锁', ''),
  ('DNS 泄漏检测', ''),
  ('运行模式', 'w'),
  ('开机自启', 'w'),
  ('静默启动', 'w'),
  ('关闭窗口时', 'w'),
  ('开机自启时静默', 'w'),
  ('穿云标题栏', 'w'),
  ('窗口置顶', 'w'),
  ('Wi‑Fi 规则', ''),
  ('按需运行', ''),
  ('按 Wi‑Fi 切换模式', ''),
  ('快捷键', 'w'),
  ('启动与断线', ''),
  ('自动连接', ''),
  ('通知栏断开按钮', 'a'),
  ('在最近任务中隐藏', 'a'),
  ('检查更新', ''),
  ('内核与资源', ''),
  ('内核', ''),
  ('地理规则库', ''),
  ('规则集', ''),
  ('主题预览', 'd'),
  ('内核版本', ''),
  ('版本与构建号', ''),
  ('开源许可', ''),
  ('恢复范围 / 恢复策略', ''),
  ('调试日志', 'v'),
  ('清除缓存', 'v'),
  ('消息样式测试', 'd'),
  ('崩溃记录测试', 'd'),
  ('重置引导', 'v'),
];

Future<ProviderContainer> _pumpTraffic(WidgetTester t, MuseTrafficPage page) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      museRunningProvider.overrideWithValue(true),
      museLocalApiProvider.overrideWithValue(null),
      museRunningCoreKindProvider.overrideWithValue(MuseCoreKind.standard),
      museConnectionsProvider.overrideWith((ref) => Stream.value(const MuseConnState())),
    ],
  );
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  t.view.physicalSize = const Size(412, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)), home: page),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  return c;
}

void main() {
  group('F1-A 底栏四栏', () {
    test('首页 / 节点 / 流量 / 设置；分支同序；剪贴板圆点仍在「节点」；侧栏没有附加项', () {
      expect(museShellActions.map((a) => a.title), ['首页', '节点', '流量', '设置']);
      expect(mobileBranches, ['home', 'nodes', 'traffic', 'settings']);
      expect(getIndexOfBranch(true, false, 'traffic'), 2);
      expect(getIndexOfBranch(true, false, 'settings'), 3);
      expect(museShellActions[museOfferTabIndex].title, '节点');
      // 「流量」沿用原「活动」的图标
      expect(museShellActions[2].icon, museShellActivity.icon);
      expect(museShellExtras(logCapture: true, logsAvailable: true), isEmpty);
      expect(branchesScope.keys, containsAll(mobileBranches));
    });

    test('活动 → 流量 › 连接；旧地址跳到流量页（查询参数保留）', () {
      expect(museActivityLocation(MuseActivityTab.dns), '/traffic?tab=dns');
      expect(museActivityRedirect(Uri.parse('/settings/activity?tab=logs')), '/traffic?tab=logs');
      expect(museActivityRedirect(Uri.parse('/settings/activity')), '/traffic?tab=connections');
      expect(museTrafficSubLocation(Uri.parse('/settings/routing-options?routeRule=x')), '/traffic/routing-options?routeRule=x');
      expect(museTrafficSubLocation(Uri.parse('/nodes/routing-options/rule/3/generic-list/domain')), '/traffic/routing-options/rule/3/generic-list/domain');
      expect(museTrafficSubLocation(Uri.parse('/settings/per-app/app-list')), '/traffic/per-app/app-list');
      expect(museSettingsRulesLocation(Uri.parse('/nodes/routing-options')), '/traffic/routing-options');
      expect(MuseTrafficSeg.fromKey('rules'), MuseTrafficSeg.rules);
      expect(MuseTrafficSeg.fromKey(null), MuseTrafficSeg.connections);
      expect(museTrafficRulesLocation, '/traffic?seg=rules');
    });

    test('路由：/traffic 一个分支，我的规则与分应用代理挂在下面；旧 /settings 路由名不变、只跳转', () {
      final r = _src('lib/core/router/go_router/routing_config_notifier.dart');
      expect(r, contains('name: museTrafficRoute'));
      expect(r, contains('path: museTrafficPath'));
      expect(r, contains("name: 'routingOptions'"));
      expect("name: 'routingOptions'".allMatches(r).length, 1);
      expect("'perAppProxy'".allMatches(r).length, 1);
      expect(r, contains('name: museActivityRoute'));
      expect(r, contains("GoRoute(name: 'connections', path: 'connections', redirect: (_, _) => museActivityLocation(MuseActivityTab.connections))"));
      expect(r, contains("GoRoute(name: 'logs', path: 'logs', redirect: (_, _) => museActivityLocation(MuseActivityTab.logs))"));
      expect(r, contains('museActivityRedirect(state.uri)'));
      expect(r, contains("path: 'per-app',\n                      redirect: (_, state) => museTrafficSubLocation(state.uri)"));
      expect(_src('lib/features/muse/desktop/smoke_control.dart'), contains("'traffic'"));
    });

    testWidgets('流量页「连接」段：标题「流量」，两排分段（连接 / 规则，实时 / 日志 / DNS / 统计）', (t) async {
      await _pumpTraffic(t, const MuseTrafficPage());
      expect(find.text('流量'), findsWidgets);
      expect(find.byKey(const ValueKey('traffic_seg')), findsOneWidget);
      expect(find.byKey(const ValueKey('activity_tabs')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('activity_tabs')), matching: find.text('实时')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('traffic_seg')), matching: find.text('规则')), findsOneWidget);
      // 切到「规则」段：分流规则页（分流模式、我的规则…），切换条还在顶上
      await t.tap(find.descendant(of: find.byKey(const ValueKey('traffic_seg')), matching: find.text('规则')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('traffic_rules')), findsOneWidget);
      expect(find.byKey(const ValueKey('traffic_seg')), findsOneWidget);
      expect(find.byKey(const ValueKey('routing_mode')), findsOneWidget);
      expect(find.text(museRouteModeTitle), findsOneWidget);
      expect(find.byType(MuseRoutingMoreMenu), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('从地址打开「规则」段、「连接」段的统计', (t) async {
      await _pumpTraffic(t, const MuseTrafficPage(seg: MuseTrafficSeg.rules));
      expect(find.byKey(const ValueKey('traffic_rules')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      await _pumpTraffic(t, const MuseTrafficPage(tab: MuseActivityTab.stats));
      expect(find.byKey(const ValueKey('activity_stats')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    test('活动四块单独打开时标题仍是「活动」', () {
      for (final f in ['lib/features/muse/activity/dns_view.dart', 'lib/features/muse/connections/connections_page.dart', 'lib/features/muse/logs/logs_page.dart', 'lib/features/muse/settings/stats_page.dart']) {
        expect(_src(f), contains(': museActivityTitle(context)'), reason: f);
      }
    });
  });

  group('F2 设置 6 组', () {
    test('一级 6 行，开发者选项进了「关于」组', () {
      const rows = ['连接与网络', '订阅与节点', '外观', '自动化', '诊断', '关于'];
      expect(museSettingsHomeRows(android: true, developer: false), rows);
      expect(museSettingsHomeRows(android: false, developer: true), rows);
      expect(museStartupTitle, '自动化');
      final page = _src('lib/features/settings/overview/settings_page.dart');
      for (final k in ['settings_search', 'settings_group_net', 'settings_group_subs', 'theme_mode', 'settings_auto_connect', 'settings_diagnose', 'settings_group_about']) {
        expect(page, contains("ValueKey('$k')"), reason: k);
      }
      // 二级：原来的入口都还在
      for (final k in ['settings_network', 'settings_resources', 'settings_privacy_home', 'settings_about', 'settings_backup', 'settings_developer', 'settings_subs_list', 'settings_sub_settings', 'settings_node_settings', 'settings_overrides']) {
        expect(page, contains("ValueKey('$k')"), reason: k);
      }
      // 搜索框常驻，不再是右上角放大镜
      expect(page, isNot(contains('actions: [\n        IconButton(\n          key: const ValueKey(\'settings_search\')')));
    });

    test('每行副标题是当前状态', () {
      expect(museSubsGroupSummary(null), '还没有订阅');
      expect(museSubsGroupSummary(' '), '还没有订阅');
      expect(museSubsGroupSummary('机场'), '当前订阅：机场');
      expect(museNetGroupSummary(core: '标准内核', takeover: museTakeoverTitle(ServiceMode.tun)), '标准内核 · TUN');
      expect(museNetGroupSummary(), '网络、内核与资源、隐私与通知');
      expect(museAutomationSummary('关'), '自动连接：关');
      expect(museAutomationSummary('按需、定时'), '按需、定时');
    });

    test('v1.21 的每个搜索项仍能按原名搜到', () {
      for (final (title, f) in _titles121) {
        final hits = museSearchSettings(title, android: f != 'w', windows: f == 'w', developer: f == 'v' || f == 'd', debugBuild: true);
        expect(hits.map((e) => e.title), contains(title), reason: title);
      }
    });

    test('新名字搜得到，路径是新位置', () {
      for (final (q, page) in [
        ('流量', MuseSettingPage.activity),
        ('连接与网络', MuseSettingPage.netGroup),
        ('订阅与节点', MuseSettingPage.subsGroup),
        ('自动化', MuseSettingPage.autoConnect),
        ('分流模式', MuseSettingPage.routing),
        ('订阅修改', MuseSettingPage.overrides),
        ('关于穿云', MuseSettingPage.about),
      ]) {
        expect(museSearchSettings(q, android: true, windows: false).first.page, page, reason: q);
      }
      expect(museSearchSettings('接管方式', android: false, windows: true).first.title, '接管方式');
      expect(MuseSettingPage.routing.path, '流量 › 规则');
      expect(MuseSettingPage.activity.path, '流量 › 连接');
      expect(MuseSettingPage.network.path, '设置 › 连接与网络 › 网络');
      expect(MuseSettingPage.sync.path, '设置 › 关于 › 备份与恢复');
      expect(MuseSettingPage.autoConnect.path, '设置 › 自动化');
      for (final p in MuseSettingPage.values) {
        expect(p.path, isNot(contains('设置 › 活动')), reason: p.name);
        expect(p.path, isNot(contains('设置 › 分流规则')), reason: p.name);
        expect(p.path, isNot(contains('启动与断线')), reason: p.name);
      }
      expect(museActivityTabForSetting('流量'), MuseActivityTab.connections);
    });
  });

  group('F20 术语（只改界面文案）', () {
    test('界面不再用 代理组 / 策略组 / 订阅覆写 / 运行模式 / 出站 / 入站', () {
      final banned = RegExp(r"'[^'\n]*(代理组|策略组|订阅覆写|运行模式|编辑覆写|启用覆写|全部覆写)[^'\n]*'");
      for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('settings_index.dart') || f.path.endsWith('changelog.dart')) continue; // 旧名留在搜索关键词 / 历史说明
        final code = f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
        expect(banned.firstMatch(code)?.group(0), isNull, reason: f.path);
      }
      final conn = _src('lib/features/muse/connections/connections_page.dart');
      expect(conn, contains("kv('交给', why.outbound)"));
      expect(conn, contains("kv('来自', c.inbound)"));
      expect(conn, contains("kv('经过', c.chains"));
      expect(_src('lib/features/muse/widget/muse_common.dart'), contains("_ when isGroup => '分组'"));
      expect(_src('lib/features/muse/logic/home_tiles.dart'), contains("takeover('takeover', '接管方式')"));
      expect(_src('lib/features/muse/logic/home_tiles.dart'), contains("groups('groups', '分组')"));
    });

    test('测速按钮叫「测延迟」，下载测速叫「测网速」', () {
      expect(_src('lib/features/muse/nodes/node_list.dart'), contains(": const Text('测延迟'),"));
      expect(_src('lib/features/muse/home/muse_home_page.dart'), contains("'测延迟'"));
      expect(_src('lib/features/system_tray/notifier/system_tray_notifier.dart'), contains("MuseTrayItem('urltest', '测延迟')"));
      expect(_src('lib/features/muse/nodes/node_dialogs.dart'), contains('测网速（下载约 5 MB）'));
      expect(museLatencyTestTitle, '测延迟');
      expect(museSpeedTestTitle, '测网速');
    });

    test('存储键不变', () {
      expect(_src('lib/features/muse/data/muse_prefs.dart'), contains('"muse_log_capture"'));
      expect(_src('lib/features/muse/logic/home_tiles.dart'), contains("groups('groups'"));
      expect(_src('lib/features/muse/logic/home_tiles.dart'), contains("takeover('takeover'"));
    });
  });

  group('约束', () {
    test('改过的文件：中文、无其他应用名、无循环动画 / 轮询', () {
      for (final f in [
        'lib/features/muse/traffic/traffic_page.dart',
        'lib/features/settings/overview/settings_page.dart',
        'lib/features/muse/logic/terms.dart',
        'lib/features/muse/shell/muse_shell.dart',
      ]) {
        final s = File(f).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
        for (final banned in ['Clash', 'FlClash', 'Hiddify', 'v2ray', 'repeat(', 'Timer.periodic', 'Stream.periodic']) {
          expect(s.contains(banned), isFalse, reason: '$f: $banned');
        }
      }
    });

    test('版本 1.22.0+220：更新说明 4 条、CHANGELOG.md 2026-11-12', () {
      expect(_src('pubspec.yaml'), contains('version: 1.22.0+220'));
      final changelog = _src('lib/features/muse/data/changelog.dart');
      expect(changelog, contains("'1.22.0': ["));
      expect(changelog.indexOf("'1.22.0'"), lessThan(changelog.indexOf("'1.21.0'")));
      final md = _src('CHANGELOG.md');
      expect(md, contains('### 1.22.0 - 2026-11-12'));
      expect(md.indexOf('### 1.22.0'), lessThan(md.indexOf('### 1.21.0')));
      for (final w in ['Clash', 'Hiddify', 'FlClash']) {
        expect(changelog.substring(changelog.indexOf("'1.22.0'"), changelog.indexOf("'1.21.0'")).contains(w), isFalse, reason: w);
      }
    });
  });
}
