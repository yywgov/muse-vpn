// 穿云 1.2.9
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';

void main() {
  // what the core reports as the type of a node sing-box could not start (old edgetunnel ECH links)
  const echType =
      'Invalid initialize outbound/vless[🇺🇸美国|CF官方优选1 § 0]: invalid ECH configs pem';

  group('invalid node subtitle', () {
    test('short Chinese reason instead of the upper-cased core error', () {
      expect(museIsInvalidNodeType(echType), isTrue);
      expect(museInvalidNodeSubtitle(echType), '节点配置不兼容：ECH 参数');
      expect(museProtocolLabel(echType), '不兼容');
      expect(museProtocolName('vless'), 'VLESS');
      expect(museIsInvalidNodeType('vless'), isFalse);
    });
    test('full error kept for the detail sheet (copyable)', () {
      expect(museInvalidNodeError(echType), 'initialize outbound/vless[🇺🇸美国|CF官方优选1 § 0]: invalid ECH configs pem');
      expect(museInvalidNodeError('vless'), '');
      expect(museInvalidNodeError('Invalid'), '未知错误');
    });
    test('reasons', () {
      String r(String cause) => museInvalidNodeReason('Invalid initialize outbound/vless[a]: $cause');
      expect(r('unknown uTLS fingerprint: bogus'), '指纹 fp');
      expect(r('Reality is conflict with ECH'), 'ECH 参数');
      expect(r('parse encryption: invalid encryption string: missing components'), '加密方式');
      expect(r('unknown packet encoding: x'), '包编码');
      expect(r('naive outbound is not included in this build, rebuild with -tags with_naive_outbound'), '协议不受支持');
      expect(r('unknown transport type: splithttp'), 'XHTTP 传输');
      expect(r('something new'), '参数不受支持');
      // a tag containing a keyword does not decide the reason
      expect(museInvalidNodeReason('Invalid initialize outbound/vless[ech-node]: unknown uTLS fingerprint: x'), '指纹 fp');
    });
  });

  test('changelog has 1.2.9', () {
    expect(museChangelog['1.2.9'], isNotEmpty);
  });
}
