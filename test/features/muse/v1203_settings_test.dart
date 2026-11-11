// 穿云 1.20.3 设置整理：一级结构（外观、启动与断线、分流规则、网络、隐私与通知、活动、诊断、内核与资源、备份与恢复、关于）、
// 分流规则三组 + 页顶生效顺序 + 模式、我的规则挂回 /settings、已屏蔽网站可看可删、诊断合一、Wi‑Fi 规则同页、订阅设置、
// 节点被哪一层藏起来、分应用代理让应用规则失效的提示、旧名都还能搜到、旧路由跳到新位置。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart' show museSettingsRulesLocation;
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/muse/activity/activity_page.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/per_app_bypass.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/settings/auto_connect_page.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart' show museDiagnoseLocation, museDiagnosePath;
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/settings/wifi_mode_page.dart' show museWifiRulesPriorityText, museWifiRulesTitle;
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart' show museSettingsHomeRows;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

Future<ProviderContainer> _pump(WidgetTester tester, Widget page, Map<String, Object> initial, {Size size = const Size(412, 915)}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => prefs)]);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final theme = AppTheme(container.read(themePreferencesProvider), '');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme.lightTheme(null), darkTheme: theme.darkTheme(null), home: page),
    ),
  );
  await tester.pump();
  return container;
}

/// 1.20.2 / 1.20.3 外观原型时索引里的全部标题（及平台）；整理后每个都还要能按原名搜到。
const _oldTitles = <(String, String)>[
  ('外观', ''), ('深浅色', ''), ('纯黑', ''), ('主题', ''), ('配色', ''), ('首页风格', ''), ('首页样式', ''), ('动效', ''), ('主题色', ''),
  ('自定义主题色', ''), ('隐私', ''), ('隐私模式', ''), ('敏感页禁止截屏', 'a'), ('智能保持连接', ''), ('节点失效自动切换', ''),
  ('隐藏通知', 'a'), ('去广告', ''), ('订阅自动更新', ''), ('订阅列表', ''), ('分应用代理', 'a'), ('节点', ''), ('节点名美化', ''),
  ('隐藏重复节点', ''), ('重复判断', ''), ('只显示 / 排除', ''), ('订阅 UA', ''), ('订阅更新方式', ''), ('清除测速记录', ''),
  ('订阅覆写', ''), ('分流规则', ''), ('分流预设', ''), ('指定节点', ''), ('远程规则集', ''), ('规则测试', ''), ('自定义 hosts', ''),
  ('导入 / 导出 / 粘贴规则', ''), ('远程 DNS', ''), ('每天定时连接 / 断开', ''), ('导出 / 导入配置', ''), ('备份与同步', ''), ('统计', ''),
  ('流量统计', ''), ('高级', ''), ('负载均衡策略', ''), ('TLS 分片', ''), ('IPv6', ''), ('Fake-IP', ''), ('屏蔽 QUIC', ''), ('活动', ''),
  ('连接', ''), ('日志', ''), ('DNS 查询', ''), ('切换节点时关闭旧连接', ''), ('导入后清空剪贴板', ''), ('导出为 sing-box 格式', ''),
  ('恢复推荐 DNS', ''), ('诊断', ''), ('运行模式', 'w'), ('开机自启', 'w'), ('静默启动', 'w'), ('关闭窗口时', 'w'), ('开机自启时静默', 'w'),
  ('穿云标题栏', 'w'), ('窗口置顶', 'w'), ('按需运行', ''), ('快捷键', 'w'), ('打开即连接', 'a'), ('自动连接', ''), ('通知栏断开按钮', 'a'),
  ('在最近任务中隐藏', 'a'), ('检查更新', ''), ('内核', ''), ('内核与资源', ''), ('地理规则库', ''), ('规则集', ''), ('内核版本', ''),
  ('版本与构建号', ''), ('开源许可', ''), ('恢复范围 / 恢复策略', ''),
];

List<MuseSettingEntry> _search(String q, {bool android = true, bool windows = false}) => museSearchSettings(q, android: android, windows: windows);

void main() {
  group('设置一级结构', () {
    test('按审查清单的建议排', () {
      expect(museSettingsHomeRows(android: true, developer: false), ['外观', '启动与断线', '分流规则', '网络', '隐私与通知', '活动', '诊断', '内核与资源', '备份与恢复', '关于']);
      expect(museSettingsHomeRows(android: false, developer: true).last, '开发者选项');
      expect(museSettingsHomeRows(android: true, developer: false), isNot(contains('分应用代理'))); // 进了分流规则页
    });

    test('设置首页每一行都有入口（key 不变的沿用，新的三行新加）', () {
      final page = _src('lib/features/settings/overview/settings_page.dart');
      for (final k in ['theme_mode', 'settings_auto_connect', 'settings_rules', 'settings_network', 'settings_privacy_home', 'settings_activity', 'settings_diagnose', 'settings_resources', 'settings_backup', 'settings_about']) {
        expect(page, contains("ValueKey('$k')"), reason: k);
      }
      expect(page, isNot(contains("ValueKey('settings_per_app')")));
      expect(_src('lib/features/muse/settings/routing_pages.dart'), contains("ValueKey('settings_per_app')"));
    });
  });

  group('搜索：旧名都还在，漏的补上', () {
    test('旧索引里的每个标题仍能按原名搜到（标题完全一致的一条）', () {
      for (final (t, p) in _oldTitles) {
        final hits = _search(t, android: p != 'w', windows: p == 'w');
        expect(hits.map((e) => e.title), contains(t), reason: t);
      }
    });

    test('清单里漏掉的几项现在搜得到', () {
      for (final (q, title, page) in [
        ('规则模式', '规则 / 全局模式', MuseSettingPage.routing),
        ('全局', '规则 / 全局模式', MuseSettingPage.routing),
        ('已屏蔽', '已屏蔽的网站', MuseSettingPage.routing),
        ('来自连接', '来自连接的规则', MuseSettingPage.routing),
        ('请求头', '请求头', MuseSettingPage.subscriptions),
        ('按 Wi‑Fi 切换模式', '按 Wi‑Fi 切换模式', MuseSettingPage.wifiRules),
        ('更新后测速', '更新后测速新增节点', MuseSettingPage.subSettings),
        ('编辑首页', '编辑首页卡片', MuseSettingPage.appearance),
        ('已隐藏', '显示全部已隐藏节点', MuseSettingPage.nodes),
        ('DNS 泄漏', 'DNS 泄漏检测', MuseSettingPage.diagnose),
        ('一键诊断', '一键诊断', MuseSettingPage.diagnose),
        ('我的规则', '我的规则', MuseSettingPage.myRules),
        ('隐私与通知', '隐私与通知', MuseSettingPage.privacy),
        ('备份与恢复', '备份与恢复', MuseSettingPage.sync),
        ('启动与断线', '启动与断线', MuseSettingPage.autoConnect),
      ]) {
        final hit = _search(q).first;
        expect(hit.title, title, reason: q);
        expect(hit.page, page, reason: q);
      }
      expect(_search('不走代理的地址', android: false, windows: true).first.page, MuseSettingPage.advanced);
      expect(_search('商店应用', android: false, windows: true).first.title, '允许商店应用走代理');
    });

    test('旧页名找得到新位置', () {
      expect(_search('路由').map((e) => e.page), contains(MuseSettingPage.myRules));
      expect(_search('网络接管', android: false, windows: true).first.title, '运行模式');
      expect(_search('网络诊断').first.page, MuseSettingPage.diagnose);
      expect(_search('自动运行').first.title, '打开即连接');
      expect(_search('自定义 hosts').first.page, MuseSettingPage.network);
      expect(_search('节点失效').first.page, MuseSettingPage.autoConnect);
      expect(_search('在最近任务中隐藏').first.page, MuseSettingPage.privacy);
      expect(museDiagnoseSectionForSetting('出口与解锁'), 'exit');
      expect(museDiagnoseSectionForSetting('诊断'), isNull);
    });

    test('搜「网络」不再先出「每天定时连接 / 断开」', () {
      expect(_search('网络').map((e) => e.title), isNot(contains('每天定时连接 / 断开')));
    });

    test('设置页的每个页面类型都有打开方式', () {
      final page = _src('lib/features/settings/overview/settings_page.dart');
      for (final p in MuseSettingPage.values) {
        expect(page, contains('MuseSettingPage.${p.name}'), reason: p.name);
      }
    });
  });

  group('分流规则', () {
    test('生效顺序按实际拼接顺序写：覆写 → 已屏蔽 → 来自连接 → 自定义 → 预设 → 远程规则集', () {
      final order = ['订阅覆写', '已屏蔽', '来自连接', '自定义规则', '预设', '远程规则集'];
      var at = -1;
      for (final w in order) {
        final i = museRoutingOrderText.indexOf(w);
        expect(i, greaterThan(at), reason: w);
        at = i;
      }
      // 代码里也是这个顺序：已屏蔽包在来自连接外面（更靠前），预设 / 远程规则集排在自定义规则后面
      final repo = _src('lib/features/settings/data/config_option_repository.dart');
      expect(repo.indexOf('museApplyBlockedHosts('), lessThan(repo.indexOf('museApplyQuickRules(')));
      expect(_src('lib/features/muse/logic/rules_tools.dart'), contains('for (final r in [...own, ...presets, ...builtin])'));
    });

    test('规则测试说出命中的是哪一层', () {
      expect(museRuleDisplayName('muse:blocked-hosts'), '已屏蔽的网站');
      expect(museRuleDisplayName('muse:quick:direct'), '来自连接的规则');
      expect(museRuleDisplayName('remote:0'), '远程规则集');
      expect(museRuleDisplayName('preset:ai'), startsWith('预设：'));
      expect(museRuleDisplayName('公司'), '自定义规则：公司');
    });

    test('Wi‑Fi 规则改了模式才提示', () {
      expect(museRouteModeByWifi(applied: 'global', current: MuseRouteMode.global), isTrue);
      expect(museRouteModeByWifi(applied: 'global', current: MuseRouteMode.rule), isFalse); // 用户手动改回了
      expect(museRouteModeByWifi(applied: '', current: MuseRouteMode.global), isFalse);
    });

    testWidgets('三组 + 页顶一行 + 模式分段；改模式写原来的键', (tester) async {
      final c = await _pump(tester, const MuseRoutingPage(android: true), {}, size: const Size(412, 1400));
      expect(find.byKey(const ValueKey('routing_order')), findsOneWidget);
      for (final h in ['我的规则', '规则来源', '工具']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      for (final k in ['routing_rule_list', 'routing_node_rules', 'routing_quick_rules', 'routing_blocked_hosts', 'ad_block_level', 'routing_presets', 'routing_remote_sets', 'routing_tester', 'settings_per_app']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      // 导入导出收进 ⋯，hosts 挪到网络
      for (final k in ['routing_export', 'routing_import', 'routing_paste_rules', 'routing_hosts']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      final mine = tester.getRect(find.byKey(const ValueKey('routing_rule_list')));
      final sources = tester.getRect(find.byKey(const ValueKey('routing_presets')));
      final tools = tester.getRect(find.byKey(const ValueKey('routing_tester')));
      expect(mine.top, lessThan(sources.top));
      expect(sources.top, lessThan(tools.top));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('routing_mode_segmented')), matching: find.text('全局')));
      await tester.pump();
      expect(c.read(ConfigOptions.museRouteMode), MuseRouteMode.global);
      expect(find.textContaining('由「按 Wi‑Fi 切换模式」设定'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('被 Wi‑Fi 规则改成全局时，模式一行写明', (tester) async {
      await _pump(tester, const MuseRoutingPage(android: false), {'muse-route-mode': 'global', 'muse_wifi_mode_applied': 'global'});
      expect(find.textContaining('由「按 Wi‑Fi 切换模式」设定'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_per_app')), findsNothing); // 只在安卓
    });

    testWidgets('已屏蔽的网站：看得到、删得掉（写回 muse_blocked_hosts）', (tester) async {
      final c = await _pump(tester, Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(onPressed: () => showMuseBlockedHostsSheet(ctx), child: const Text('打开'))))), {
        'muse_blocked_hosts': '["ads.example.com","1.2.3.4"]',
      });
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('ads.example.com'), findsOneWidget);
      expect(find.text('1.2.3.4'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('blocked_host_delete_ads.example.com')));
      await tester.pumpAndSettle();
      expect(find.text('ads.example.com'), findsNothing);
      expect(c.read(MusePrefs.blockedHosts), '["1.2.3.4"]');
    });

    test('「我的规则」挂在 /settings 下，旧地址带着子路径和查询参数跳过去', () {
      expect(museSettingsRulesLocation(Uri.parse('/nodes/routing-options')), '/settings/routing-options');
      expect(museSettingsRulesLocation(Uri.parse('/nodes/routing-options/rule/3/generic-list/domain')), '/settings/routing-options/rule/3/generic-list/domain');
      expect(museSettingsRulesLocation(Uri.parse('/nodes/routing-options?routeRule=abc')), '/settings/routing-options?routeRule=abc');
      final router = _src('lib/core/router/go_router/routing_config_notifier.dart');
      expect(router, contains('...rulesChildren,'));
      expect(router, contains("name: 'routingOptions',"));
      expect(_src('lib/features/settings/overview/sections/routing_options_page.dart'), contains("title: '我的规则'"));
    });
  });

  group('诊断合一', () {
    test('一个页面（设置一级），其他入口都跳过去', () {
      expect(museDiagnosePath, '/settings/diagnose');
      expect(museDiagnoseLocation(section: 'exit'), '/settings/diagnose?section=exit');
      expect(MuseActivityTab.values.map((e) => e.title), ['连接', '日志', 'DNS', '统计']);
      final router = _src('lib/core/router/go_router/routing_config_notifier.dart');
      expect(router, contains("state.uri.queryParameters['tab'] == 'diagnose' ? museDiagnosePath : null"));
      expect(router, contains('MuseDiagnoseHubPage('));
      expect(_src('lib/features/muse/home/health_banner.dart'), contains('go(museDiagnosePath)'));
      expect(_src('lib/features/muse/home/exit_detail_sheet.dart'), contains("museDiagnoseLocation(section: 'exit')"));
      expect(_src('lib/features/muse/home/dashboard_cards.dart'), contains("ValueKey('services_open_diagnose')"));
      final diag = _src('lib/features/muse/settings/diagnose_sheet.dart');
      expect(diag, contains('MuseConnectDoctorView(embedded: true)'));
      // 出口区读首页「服务状态」同一个 provider，不再自己测 Google / ChatGPT / Netflix
      expect(diag, contains('ref.watch(museServicesProvider)'));
      expect(diag, isNot(contains("_ServiceChip(name: 'Google'")));
    });
  });

  group('启动与断线', () {
    test('保持连接两项同一组；Wi‑Fi 两个名单同一页并说明谁优先', () {
      final page = _src('lib/features/muse/settings/auto_connect_page.dart');
      final keep = page.indexOf("ValueKey('keep_alive')");
      final failover = page.indexOf("ValueKey('node_auto_failover')");
      expect(keep, greaterThan(0));
      expect(failover, greaterThan(keep));
      expect(page.substring(keep, failover), isNot(contains('MuseSection(')));
      expect(_src('lib/features/muse/settings/node_settings_page.dart'), isNot(contains("ValueKey('node_auto_failover')")));
      expect(museWifiRulesTitle, 'Wi‑Fi 规则');
      expect(museWifiRulesPriorityText, contains('「暂停连接」优先'));
      expect(museWifiRulesSummary(onDemand: true, pauseCount: 2, modeCount: 1), '暂停 2 个，切换模式 1 个');
      expect(museWifiRulesSummary(onDemand: false, pauseCount: 2, modeCount: 0), '关');
    });

    test('Windows：静默启动开着时「开机自启时静默」置灰并说明', () {
      expect(museAutostartSilentSubtitle(silentStart: true), contains('不起作用'));
      expect(museAutostartSilentSubtitle(silentStart: false), isNot(contains('不起作用')));
      expect(_src('lib/features/muse/settings/auto_connect_page.dart'), contains('onChanged: silent ? null :'));
    });
  });

  group('订阅与节点', () {
    testWidgets('节点设置只留显示相关；订阅设置四项', (tester) async {
      await _pump(tester, const MuseNodeSettingsPage(), {});
      expect(find.text('节点设置'), findsOneWidget);
      for (final k in ['node_auto_failover', 'node_sub_fetch', 'node_sub_ua', 'node_advanced_fold']) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      for (final k in ['node_beautify', 'node_hide_duplicates', 'node_dedup_mode', 'node_include', 'node_exclude', 'node_clear_cache']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await _pump(tester, const MuseSubSettingsPage(), {});
      for (final k in ['auto_update_hours', 'test_new_nodes', 'node_sub_fetch', 'node_sub_ua']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(tester.takeException(), isNull);
    });

    test('订阅弹层 ⋯：订阅设置、全部覆写；清除测速记录只剩一处', () {
      final subs = _src('lib/features/muse/nodes/subs_sheet.dart');
      expect(subs, contains("ValueKey('subs_more_settings')"));
      expect(subs, contains("ValueKey('subs_more_overrides')"));
      expect(_src('lib/features/muse/settings/developer_page.dart'), isNot(contains("ValueKey('dev_clear_latency')")));
    });

    test('节点被藏时说清是哪一层（算在第一个藏住它的层上）', () {
      final nodes = ['dup', 'g', 's', 'v', 'm', 'ok'];
      final c = museNodeHiddenCounts<String>(
        nodes,
        duplicate: (n) => n == 'dup',
        passesGlobal: (n) => n != 'g' && n != 'dup',
        passesSub: (n) => n != 's',
        passesView: (n) => n != 'v',
        manual: (n) => n == 'm' || n == 'g',
      );
      expect((c.duplicate, c.global, c.sub, c.view, c.manual), (1, 1, 1, 1, 1));
      expect(museNodeHiddenNote(c, viewLabel: '收藏'), '已隐藏 5 个：重复 1、全部订阅筛选 1、此订阅筛选 1、只看收藏 1、手动隐藏 1');
      expect(museNodeHiddenNote(const MuseNodeHiddenCounts()), isNull);
      expect(_src('lib/features/muse/nodes/node_list.dart'), contains("ValueKey('node_hidden_note')"));
    });
  });

  group('分应用代理与应用规则', () {
    test('不走代理的应用写进规则时给提示', () {
      const off = (mode: null, active: <String>{});
      const exclude = (mode: AppProxyMode.exclude, active: {'com.tencent.mm'});
      const include = (mode: AppProxyMode.include, active: {'com.android.chrome'});
      expect(museAppBypassed('com.tencent.mm', off), isFalse);
      expect(museAppBypassed('com.tencent.mm', exclude), isTrue);
      expect(museAppBypassed('com.android.chrome', exclude), isFalse);
      expect(museAppBypassed('com.android.chrome', include), isFalse);
      expect(museAppBypassed('com.tencent.mm', include), isTrue);
      expect(museBypassedNote(museBypassedPackages(['com.tencent.mm', 'org.x'], exclude)), 'com.tencent.mm 已在分应用代理中设为不走代理，这条规则对它不生效');
      expect(museBypassedNote(const []), isNull);
      expect(_src('lib/features/route_rules/widget/rule_tile.dart'), contains("ValueKey('rule_bypassed_note')"));
    });
  });

  group('隐私与通知', () {
    testWidgets('通知三项搬来；ⓘ 改成副标题', (tester) async {
      await _pump(tester, const MusePrivacyPage(android: true), {}, size: const Size(412, 1200));
      expect(find.text('隐私与通知'), findsOneWidget);
      for (final k in ['appearance_privacy', 'appearance_secure_sensitive', 'clear_clipboard_switch', 'settings_notify_stop', 'settings_hide_notification', 'settings_exclude_recents']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const ValueKey('row_info')), findsNothing);
      expect(find.text('首页的流量、IP 等数字打码'), findsOneWidget);
    });
  });

  group('约束', () {
    test('改过的文件：无循环动画、无轮询、文案没有「...」', () {
      for (final f in [
        'lib/features/muse/settings/routing_pages.dart',
        'lib/features/muse/settings/auto_connect_page.dart',
        'lib/features/muse/settings/wifi_mode_page.dart',
        'lib/features/muse/settings/node_settings_page.dart',
        'lib/features/muse/settings/privacy_settings_page.dart',
        'lib/features/muse/settings/diagnose_sheet.dart',
        'lib/features/muse/data/per_app_bypass.dart',
        'lib/features/settings/overview/settings_page.dart',
      ]) {
        final s = _src(f);
        expect(s, isNot(contains('.repeat(')), reason: f);
        expect(s, isNot(contains('Timer.periodic')), reason: f);
        expect(RegExp(r"'[^'\n]*\.\.\.[^'\n]*'").hasMatch(s.replaceAll(RegExp(r'\.\.\.[a-zA-Z\[]'), '')), isFalse, reason: f);
      }
    });

    test('持久化键不变（搬家的设置）', () {
      final muse = _src('lib/features/muse/data/muse_prefs.dart');
      for (final (name, key) in [('blockedHosts', 'muse_blocked_hosts'), ('autoFailover', 'muse_auto_failover'), ('subUserAgent', 'muse_sub_user_agent'), ('hosts', 'muse_hosts')]) {
        expect(muse, contains(name), reason: name);
        expect(muse, contains('"$key"'), reason: key);
      }
    });
  });
}
