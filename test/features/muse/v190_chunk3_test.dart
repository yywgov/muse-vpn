// 穿云 1.9.0: 订阅官网 / 续费链接 (#49) and 自动更新错开时间 (#55).
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';

void main() {
  group('#49 renew url', () {
    test('web page first, then support; only http(s) with a host', () {
      expect(museRenewUrl('https://a.example.com/buy', 'https://b.example.com'), 'https://a.example.com/buy');
      expect(museRenewUrl(null, 'https://b.example.com/help'), 'https://b.example.com/help');
      expect(museRenewUrl('', ' http://c.example.com '), 'http://c.example.com');
      expect(museRenewUrl('javascript:alert(1)', 'tg://resolve?domain=x'), isNull);
      expect(museRenewUrl('file:///etc/passwd', 'https://'), isNull);
      expect(museRenewUrl('not a url', null), isNull);
      expect(museRenewUrl(null, null), isNull);
      expect(museRenewUrl('https://x.com/${'a' * 3000}', null), isNull);
    });
    test('an unusable web page falls back to support', () {
      expect(museRenewUrl('ftp://x.com', 'https://ok.example.com'), 'https://ok.example.com');
    });
  });

  group('#55 jitter', () {
    const day = Duration(hours: 24);
    test('never shorter, at most 10 % longer', () {
      for (final id in ['1', 'abc', 'a-very-long-subscription-id-0123456789', '', '订阅']) {
        final j = museJitteredInterval(day, id);
        expect(j >= day, isTrue, reason: id);
        expect(j <= day + const Duration(hours: 2, minutes: 25), isTrue, reason: id);
      }
    });
    test('stable for one subscription, different between subscriptions', () {
      expect(museJitteredInterval(day, 'x1'), museJitteredInterval(day, 'x1'));
      final set = {for (var i = 0; i < 30; i++) museJitteredInterval(day, 'sub-$i')};
      expect(set.length, greaterThan(10));
    });
    test('zero stays zero', () {
      expect(museJitteredInterval(Duration.zero, 'x'), Duration.zero);
    });
  });
}
