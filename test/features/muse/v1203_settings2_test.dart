// 穿云 1.20.3 设置整理第 2 轮：我的规则页换成穿云统一组件（加号在标题栏、无浮动按钮）；分流规则「我的规则」组行顺序
// 与页顶生效顺序一致；开关关闭统一写「关」；重复判断说明缩短；诊断没连接时不说「一切正常」、代理方式标签不折行；
// 浅主题色下开关滑块不再是纯黑。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/muse/logic/diagnosis.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/settings/overview/sections/routing_options_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Dirs extends AppDirectories {
  @override
  Future<Directories> build() async => (baseDir: Directory.systemTemp.createTempSync('cy_rules'), workingDir: Directory.systemTemp, tempDir: Directory.systemTemp);
}

String _src(String p) => File(p).readAsStringSync();

Future<ProviderContainer> _pump(WidgetTester tester, Widget page, Map<String, Object> initial, {Size size = const Size(412, 915)}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => prefs), appDirectoriesProvider.overrideWith(_Dirs.new)]);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sharedPreferencesProvider.future));
  await tester.runAsync(() => container.read(translationsProvider.future));
  await tester.runAsync(() => container.read(appDirectoriesProvider.future));
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

void main() {
  group('我的规则页', () {
    testWidgets('穿云页面：标题栏有加号与 ⋯，没有浮动按钮；规则在一张分组卡片里', (tester) async {
      await _pump(tester, const RoutingOptionsPage(routeRule: null), {});
      expect(find.byKey(const ValueKey('muse_page_title')), findsOneWidget);
      expect(find.text('我的规则'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey('my_rules_add')), findsOneWidget);
      expect(find.byKey(const ValueKey('my_rules_more')), findsOneWidget);
      expect(find.byKey(const ValueKey('my_rules_list')), findsOneWidget);
      expect(find.byKey(const ValueKey('lan_rule_locked')), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);
      // 加号在标题栏右侧（和 ⋯ 同一行）
      final add = tester.getRect(find.byKey(const ValueKey('my_rules_add')));
      final title = tester.getRect(find.byKey(const ValueKey('muse_page_title')));
      expect((add.center.dy - title.center.dy).abs(), lessThan(8));
      expect(tester.takeException(), isNull);
    });
  });

  group('分流规则', () {
    testWidgets('「我的规则」组行顺序 = 生效顺序：已屏蔽 → 来自连接 → 自定义规则，指定节点在最后', (tester) async {
      await _pump(tester, const MuseRoutingPage(android: true), {}, size: const Size(412, 1400));
      double top(String k) => tester.getRect(find.byKey(ValueKey(k))).top;
      expect(top('routing_blocked_hosts'), lessThan(top('routing_quick_rules')));
      expect(top('routing_quick_rules'), lessThan(top('routing_rule_list')));
      expect(top('routing_rule_list'), lessThan(top('routing_node_rules')));
      // 页顶写的顺序也一样
      final t = museRoutingOrderText;
      expect(t.indexOf('已屏蔽'), lessThan(t.indexOf('来自连接')));
      expect(t.indexOf('来自连接'), lessThan(t.indexOf('自定义规则')));
      // 内置规则排在预设 / 远程规则集之后（rules_tools: own → presets → builtin）
      expect(t.indexOf('远程规则集'), lessThan(t.indexOf('内置规则')));
    });

    testWidgets('预设没开时写「关」', (tester) async {
      await _pump(tester, const MuseRoutingPage(android: true), {}, size: const Size(412, 1400));
      expect(find.descendant(of: find.byKey(const ValueKey('routing_presets')), matching: find.text('关')), findsOneWidget);
    });
  });

  group('开关关闭统一写「关」', () {
    test('各处关闭状态的文字', () {
      expect(museMinuteLabel(-1), '关');
      expect(museAutoUpdateLabel(0), '关');
      expect(MuseIpv6Policy.off.title, '关');
      expect(MuseMotionChoice.off.title, '关');
    });

    test('文案扫描：设置里不再用「关闭 / 未开启」表示关着的状态', () {
      final bad = RegExp(r"""\? '关闭'|\? '未开启'|\('off', '关闭'\)|'未开启'""");
      for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        expect(bad.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });
  });

  test('节点设置「重复判断」说明一行写得下（≤ 10 字）', () {
    final m = RegExp(r"subtitle: hideDup \? null : '([^']+)'").firstMatch(_src('lib/features/muse/settings/node_settings_page.dart'));
    expect(m, isNotNull);
    expect(m!.group(1)!.length, lessThanOrEqualTo(10));
  });

  group('诊断', () {
    test('没连接：不说「一切正常」，说连上后再检查', () {
      final items = [
        museDiagNetwork(directOk: true),
        museDiagDns(domesticOk: true, foreignOk: true),
        museDiagNode(connected: false, delay: 0),
        museDiagRouting(connected: false, android: true, tun: false),
        museDiagInternet(connected: false, ok: false),
      ];
      expect(museDiagConclusion(items), museDiagNotConnectedConclusion);
      expect(museDiagConclusion(items), isNot('一切正常'));
    });

    test('连上且全部通过才说「一切正常」；有项目没查时如实说', () {
      final ok = [
        museDiagNetwork(directOk: true),
        museDiagNode(connected: true, delay: 80),
        museDiagRouting(connected: true, android: true, tun: false),
        museDiagInternet(connected: true, ok: true),
      ];
      expect(museDiagConclusion(ok), '一切正常');
      expect(museDiagConclusion([...ok, museDiagClock(null)]), '没发现问题，有的项目没能检查');
    });

    test('代理方式标签短到不折行；修复建议仍认得它', () {
      expect(museDiagRoutingTitle.length, lessThanOrEqualTo(5));
      final items = [
        museDiagNetwork(directOk: true),
        museDiagNode(connected: true, delay: 80),
        museDiagRouting(connected: true, android: false, tun: false, systemProxyOurs: false),
        museDiagInternet(connected: true, ok: true),
      ];
      expect(items[2].title, museDiagRoutingTitle);
      expect(museDiagActions(items, connected: true), contains(MuseDiagAction.reconnect));
    });
  });

  group('开关滑块', () {
    test('浅主题色（onPrimary 为黑）时滑块用同色相深色，不是纯黑，且对比度够', () {
      const qingbi = Color(0xFF48C0A3);
      final thumb = museSwitchThumbOn(qingbi, museOnExact(qingbi));
      expect(thumb, isNot(const Color(0xFF000000)));
      expect(museContrast(thumb, qingbi), greaterThanOrEqualTo(3.0));
    });

    test('onPrimary 为白时照旧', () {
      const deep = Color(0xFF1F4E9A);
      expect(museSwitchThumbOn(deep, museOnExact(deep)), const Color(0xFFFFFFFF));
    });
  });
}
