// 穿云 1.9.0 #13: Windows 兼容内核 reads SIP008 and WireGuard .conf subscriptions itself (same as
// Android, where 标准内核 converts them first): the body is kept as it came, the update summary
// lists its nodes (named the way 兼容内核 names them), and switching back to 标准内核 converts it
// like any other subscription body instead of handing the SIP008 JSON to 标准内核 as its profile.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/compat_profile.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';

const _sip008 = '''
{"version":1,"servers":[
 {"id":"a","remarks":"香港","server":"hk.example.com","server_port":8388,"password":"p","method":"aes-128-gcm"},
 {"id":"b","remarks":"香港","server":"hk2.example.com","server_port":8388,"password":"p","method":"aes-128-gcm"},
 {"id":"c","server":"jp.example.com","server_port":"443","password":"p","method":"chacha20-ietf-poly1305"}
]}''';

const _wg = '''
[Interface]
PrivateKey = cHJpdmF0ZQ==
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = cHVibGlj
Endpoint = wg.example.com:51820
AllowedIPs = 0.0.0.0/0
''';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('v190_13_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a SIP008 document is a subscription body, not 标准内核\'s profile', () {
    expect(museIsStandardProfile(_sip008), isFalse);
    expect(museIsStandardProfile('{"outbounds":[{"type":"direct","tag":"d"}]}'), isTrue);
    // a sing-box profile that happens to say "servers" (DNS) stays a profile
    expect(museIsStandardProfile('{"dns":{"servers":[{"tag":"a","address":"1.1.1.1"}]},"outbounds":[]}'), isTrue);
    expect(museIsStandardProfile(_wg), isFalse);
  });

  test('SIP008 node names match 兼容内核 (remarks, else server; repeats -01)', () {
    expect(museProfileNodeNames(_sip008), ['香港', '香港-01', 'jp.example.com']);
    expect(museSip008NodeNames('not json'), isEmpty);
  });

  test('WireGuard .conf: one node, named by comment, else by endpoint host', () {
    expect(museProfileNodeNames(_wg), ['WireGuard wg.example.com']);
    expect(museWireGuardNodeName('# Name = 家里\n$_wg'), '家里');
    expect(museWireGuardNodeName(_wg.replaceFirst('wg.example.com:51820', '[2001:db8::1]:51820')), 'WireGuard 2001:db8::1');
    expect(museWireGuardNodeName('[Interface]\nPrivateKey = x\n[Peer]\n'), 'WireGuard');
  });

  test('Windows 兼容 → 标准: a kept SIP008 / WireGuard body is converted and the original kept', () async {
    const store = MuseCompatProfileStore();
    for (final body in [_sip008, _wg]) {
      final f = File('${dir.path}/p.json')..writeAsStringSync(body);
      String? seen;
      final err = await store.prepare(f, MuseCoreKind.standard, (path) async {
        seen = File(path).readAsStringSync();
        f.writeAsStringSync('{"outbounds":[]}');
        return null;
      });
      expect(err, isNull);
      expect(seen, body);
      expect(File(museCompatOriginalPath(f.path)).readAsStringSync(), body);
      // back to 兼容: the body as it came
      expect(await store.prepare(f, MuseCoreKind.compat, (_) async => 'unused'), isNull);
      expect(f.readAsStringSync(), body);
    }
  });

  test('Windows: the pinned 兼容内核 reads SIP008 / WireGuard (core 1.9.0); Android still converts first', () {
    final deps = File('dependencies.properties').readAsStringSync();
    final ref = RegExp(r'^muse\.compat\.ref=([0-9a-f]{40})$', multiLine: true).firstMatch(deps)?.group(1);
    expect(ref, isNotNull);
    // a10bf32 (rel-1.9.0) is the first 兼容内核 commit with SIP008 / WireGuard .conf
    expect(museCompatReadsNatively(_sip008), isFalse);
    expect(museCompatReadsNatively(_wg), isFalse);
    final repo = File('lib/features/profile/data/profile_repository.dart').readAsStringSync();
    expect(repo, contains('if (!museCompatReadsNatively(body)) return _coreValidate('));
  });
}
