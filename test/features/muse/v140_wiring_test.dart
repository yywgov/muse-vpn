// 穿云 1.4.0: how the new settings reach the core (hosts extras, presets with the route mode),
// rule names for people, and the QR view.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/core_extras.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/widget/qr_view.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

void main() {
  test('hosts go to the core only when set', () {
    expect(museHostsExtras(const {}), isEmpty);
    expect(museHostsExtras(museParseHosts('1.2.3.4 a.example.com\n# x\nbad line')), {
      'muse-hosts': {'a.example.com': '1.2.3.4'},
    });
  });

  test('全局 drops direct presets but keeps proxy / block ones', () {
    final rules = museApplyPresets(
      [Rule(name: 'builtin:bypassLan', outbound: Outbound.direct, enabled: true)],
      {'ai': Outbound.proxy, 'banks': Outbound.direct, 'privacy': Outbound.block},
    );
    final global = MuseRouteMode.global.applyTo(rules).map((r) => r.name).toList();
    expect(global, containsAll(['preset:ai', 'preset:privacy', 'builtin:bypassLan']));
    expect(global, isNot(contains('preset:banks')));
    final rule = MuseRouteMode.rule.applyTo(rules).map((r) => r.name).toList();
    expect(rule.indexOf('preset:ai'), lessThan(rule.indexOf('builtin:bypassLan')));
  });

  test('rule names for people', () {
    expect(museRuleDisplayName('preset:ai'), startsWith('预设：AI'));
    expect(museRuleDisplayName('builtin:bypassLan'), '局域网直连');
    expect(museRuleDisplayName('我的规则'), '我的规则');
  });

  testWidgets('QR view draws a code', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: MuseQrView('chuanyun://import?url=https%3A%2F%2Fexample.com%2Fsub'))));
    expect(find.byKey(const ValueKey('muse_qr')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
