// 穿云 1.9.0 #15 / #17 - 「规则」 page (分流 + 订阅覆写) and the 覆写 editor.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/config/rules_page.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/logic/sub_override.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Profiles extends ProfilesNotifier {
  @override
  Stream<List<ProfileEntity>> build() => Stream.value([
    ProfileEntity.remote(id: 'p0', active: true, name: '订阅甲', url: 'https://sub.example.com/a', lastUpdate: DateTime(2026, 10)),
    ProfileEntity.remote(id: 'p1', active: false, name: '订阅乙', url: 'https://sub.example.com/b', lastUpdate: DateTime(2026, 10)),
  ]);
}

Future<(ProviderContainer, SharedPreferences)> _pump(WidgetTester t, {MuseRulesTab tab = MuseRulesTab.routing}) async {
  SharedPreferences.setMockInitialValues({
    'muse_sub_overrides': '{"p1":{"enabled":true,"rules":[{"match":"domain","value":"a.com","target":"direct"}],"nodes":[],"groups":[]}}',
  });
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      profilesNotifierProvider.overrideWith(_Profiles.new),
    ],
  );
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  await t.runAsync(() => c.read(translationsProvider.future));
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(home: MuseRulesPage(initialTab: tab))));
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 200));
  }
  return (c, sp);
}

void main() {
  // 1.20.2：两个标签拆成两页——「分流规则」（设置 › 网络 下面）与「订阅覆写」一览（设置搜索）
  testWidgets('分流规则（含自定义规则列表入口）与订阅覆写一览', (t) async {
    await _pump(t);
    expect(find.byKey(const ValueKey('rules_routing_page')), findsOneWidget);
    expect(find.text('分流规则'), findsOneWidget);
    expect(find.byKey(const ValueKey('rules_tabs')), findsNothing);
    expect(find.byKey(const ValueKey('routing_presets')), findsOneWidget);
    expect(find.byKey(const ValueKey('routing_rule_list')), findsOneWidget);
    await t.pumpAndSettle();
  });

  testWidgets('订阅覆写一览（设置搜索「订阅覆写」）', (t) async {
    await _pump(t, tab: MuseRulesTab.overrides);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('rules_overrides_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('override_profile_p0')), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    expect(find.text('规则 1'), findsOneWidget);
  });

  testWidgets('打开订阅覆写，表单添加规则与代理组后写入设置（只改这个订阅）', (t) async {
    final (c, sp) = await _pump(t, tab: MuseRulesTab.overrides);
    await t.tap(find.byKey(const ValueKey('override_profile_p0')));
    await t.pumpAndSettle();
    expect(find.text('订阅修改 · 订阅甲'), findsOneWidget); // 1.22.0 F20

    await t.tap(find.byKey(const ValueKey('override_add_rule')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('override_rule_value')), 'example.com');
    await t.tap(find.byKey(const ValueKey('override_rule_ok')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('override_add_group')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('override_group_name')), '香港组');
    await t.enterText(find.byKey(const ValueKey('override_group_filter')), '香港');
    await t.tap(find.byKey(const ValueKey('override_group_ok')));
    await t.pumpAndSettle();

    final all = museParseOverrides(sp.getString('muse_sub_overrides')!);
    expect(all['p0']!.rules.single.value, 'example.com');
    expect(all['p0']!.rules.single.match, MuseOverrideMatch.domainSuffix);
    expect(all['p0']!.groups.single.filter, '香港');
    expect(all['p1']!.rules.single.value, 'a.com');
    expect(find.text('example.com'), findsOneWidget);

    // 1.10.0: the same data as JSON sits in 规则 › ⋯ › 编辑覆写 JSON (no JSON entry in 设置 any more)
    expect(find.byKey(const ValueKey('override_advanced')), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rules_more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rules_more_override_json')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('override_json_pick_p0')));
    await t.pumpAndSettle();
    final field = t.widget<TextField>(find.byKey(const ValueKey('override_json_field')));
    expect(field.controller!.text, contains('"example.com"'));
    // invalid JSON is refused and changes nothing
    await t.enterText(find.byKey(const ValueKey('override_json_field')), '[1]');
    await t.tap(find.byKey(const ValueKey('override_json_apply')));
    await t.pumpAndSettle();
    expect(find.text('不是有效的订阅修改 JSON'), findsOneWidget); // 1.22.0 F20
    expect(museParseOverrides(sp.getString('muse_sub_overrides')!)['p0']!.rules.single.value, 'example.com');
  });

  // 1.20.2：订阅页不再是一个标签（并入节点页）；设置首页「分流规则」、设置搜索都打开新页
  test('旧入口都打开「规则」：设置「分流规则」、设置搜索（订阅页并入节点页）', () {
    final config = File('lib/features/muse/config/muse_config_page.dart').readAsStringSync();
    expect(config, contains('profile_rules_entry'));
    expect(config, contains('museOpenRules(context)'));
    expect(config, isNot(contains("goNamed('routingOptions')")));
    expect(config, isNot(contains('profile_override_placeholder')));
    final settings = File('lib/features/settings/overview/settings_page.dart').readAsStringSync();
    // 1.22.0：分流规则是底栏「流量」的「规则」段，设置首页不再有这一行
    expect(settings, isNot(contains("ValueKey('settings_rules')")));
    expect(settings, contains('case MuseSettingPage.routing:\n          museOpenRules(context);'));
    expect(settings, contains('museOpenRules(context, tab: MuseRulesTab.overrides)'));
    expect(settings, isNot(contains('musePushPage(context, const MuseRoutingPage())')));
    expect(museSearchSettings('覆写', android: true, windows: false).first.page, MuseSettingPage.overrides);
    expect(museSearchSettings('路由规则', android: true, windows: false).map((e) => e.page), contains(MuseSettingPage.routing));
    expect(MuseSettingPage.routing.path, '流量 › 规则'); // 1.20.2：在设置「网络」下面（1.10.0 起在 订阅 › 规则）；1.22.0：底栏「流量」
  });
}
