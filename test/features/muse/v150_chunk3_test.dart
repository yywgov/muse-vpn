// 穿云 1.5.0 (batch 1, chunk 3): subscription fetch mode / errors / per-subscription filter / masked
// link / plain-http warning, 屏蔽 QUIC, pasted Clash / Surge rules.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/settings/sub_filter_dialog.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

Rule _r(String name, {Outbound o = Outbound.proxy, int order = 0}) =>
    Rule(name: name, outbound: o, listOrder: order, enabled: true, domainSuffixes: ['$name.com']);

void main() {
  group('#9 屏蔽 QUIC', () {
    test('off leaves the rules alone', () {
      final rules = [_r('a')];
      expect(museApplyBlockQuic(rules, block: false), same(rules));
    });
    test('on: UDP 443 blocked right after the 局域网 rule', () {
      final rules = musePinLanRule([_r('mine'), _r(museLanRuleName, o: Outbound.direct, order: 1)]);
      final out = museApplyBlockQuic(rules, block: true);
      expect(out.map((e) => e.name), [museLanRuleName, museBlockQuicRuleName, 'mine']);
      final q = out[1];
      expect(q.outbound, Outbound.block);
      expect(q.network, Network.udp);
      expect(q.portRanges, ['443']);
      expect(out.map((e) => e.listOrder), [0, 1, 2]);
    });
    test('without a 局域网 rule it goes first', () {
      expect(museApplyBlockQuic([_r('a')], block: true).first.name, museBlockQuicRuleName);
    });
  });

  group('#186 plain http', () {
    test('warns for http on the internet only', () {
      expect(museIsPlainHttpSub('http://sub.example.com/api?token=x'), isTrue);
      expect(museIsPlainHttpSub('HTTP://sub.example.com/x'), isTrue);
      expect(museIsPlainHttpSub('https://sub.example.com/x'), isFalse);
      expect(museIsPlainHttpSub('http://192.168.1.5:8080/sub'), isFalse);
      expect(museIsPlainHttpSub('http://localhost/sub'), isFalse);
      expect(museIsPlainHttpSub('vless://abc@host:443'), isFalse);
      expect(museIsPlainHttpSub('not a url ::'), isFalse);
    });
  });

  group('#45 failure text reaches the dialog', () {
    test('a String error is shown as the message', () {
      // present() needs translations only for the type; the message comes from the error itself
      const f = ProfileFailure.unexpected('HTTP 403 · 订阅链接可能已失效');
      expect(f, isA<ProfileUnexpectedFailure>());
      expect((f as ProfileUnexpectedFailure).error, 'HTTP 403 · 订阅链接可能已失效');
    });
    test('download errors map to advice', () {
      expect(museSubFetchError(status: 403), startsWith('HTTP 403'));
      expect(museSubFetchError(kind: 'connectionTimeout'), startsWith('连接超时'));
      expect(museSubFetchError(kind: 'unknown', detail: 'weird'), isEmpty);
    });
  });

  group('#41 fetch mode', () {
    test('走代理 when not connected falls back to direct; 自动 tries both', () {
      expect(museSubFetchMode(MuseSubFetch.proxy, proxyUp: false), 'direct');
      expect(museSubFetchMode(MuseSubFetch.proxy, proxyUp: true), 'proxy');
      expect(museSubFetchMode(MuseSubFetch.auto, proxyUp: true), 'both');
      expect(museSubFetchMode(MuseSubFetch.direct, proxyUp: true), 'direct');
    });
  });

  group('#43 per-subscription filter', () {
    test('looked up by profile id', () {
      final raw = museSubFiltersToRaw({'p1': const MuseSubFilter(include: '香港'), 'p2': const MuseSubFilter()});
      expect(museSubFilterOf(raw, 'p1').include, '香港');
      expect(museSubFilterOf(raw, 'p2').isEmpty, isTrue);
      expect(museSubFilterOf(raw, null).isEmpty, isTrue);
      expect(museSubFilterOf('garbage', 'p1').isEmpty, isTrue);
    });
  });

  group('#59 pasted rules', () {
    test('Clash lines convert, unknown ones are skipped', () {
      final conv = museConvertClashRules('DOMAIN-SUFFIX,google.com,Proxy\nIP-CIDR,10.0.0.0/8,DIRECT\nAND,((DOMAIN,a.com)),REJECT\nMATCH,Proxy');
      expect(conv.converted, greaterThanOrEqualTo(2));
      expect(conv.skipped, 1);
      expect(conv.rules, isNotEmpty);
    });
  });

  testWidgets('#187 subscription link masked until the eye is tapped', (tester) async {
    const url = 'https://sub.example.com/api/v1/client/subscribe?token=SECRET123';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MuseMaskedUrl(url: url, masked: museMaskSubUrl(url)))));
    expect(find.textContaining('SECRET123'), findsNothing);
    expect(find.text('https://sub.example.com/••••?••••'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('masked_url_toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('masked_url_full')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('masked_url_toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('masked_url_hidden')), findsOneWidget);
  });

  testWidgets('#43 filter dialog rejects a bad pattern and saves a good one', (tester) async {
    MuseSubFilter? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await museShowSubFilterDialog(context, const MuseSubFilter(exclude: '过期')),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('过期'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('sub_filter_include')), '香港(');
    await tester.tap(find.byKey(const ValueKey('sub_filter_save')));
    await tester.pump();
    expect(saved, isNull);
    await tester.enterText(find.byKey(const ValueKey('sub_filter_include')), '香港|日本');
    await tester.tap(find.byKey(const ValueKey('sub_filter_save')));
    await tester.pumpAndSettle();
    expect(saved?.include, '香港|日本');
    expect(saved?.exclude, '过期');
  });
}
