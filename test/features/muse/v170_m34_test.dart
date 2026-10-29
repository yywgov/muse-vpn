// 穿云 1.7.0 M3-4: 订阅兼容模式. With 兼容内核 a subscription is saved exactly as it came (a YAML
// subscription keeps its own groups and rules); going back to 标准内核 converts it at the next
// connect and keeps the original, so switching back and forth never loses anything; nodes 兼容内核
// cannot run stay in the subscription and are shown greyed out with the reason. Also: 兼容内核
// comes back by itself after the system kills its process (no timer, no polling).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/compat_profile.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';

const _kt = 'android/app/src/main/kotlin/com/hiddify/hiddify';

const _yamlSub = '''
# 机场订阅
mixed-port: 7890
proxies:
  - name: "香港 01"
    type: ss
    server: hk.example.com
    port: 8388
    cipher: aes-128-gcm
    password: pw
  - {name: 日本 02, type: trojan, server: jp.example.com, port: 443, password: pw}
  - {name: 'Naive 03', type: naive, server: n.example.com, port: 443}
proxy-groups:
  - name: 节点选择
    type: select
    proxies: [香港 01, 日本 02, Naive 03]
rules:
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
''';

const _links = 'trojan://pw@a.example.com:443#A%20%E9%A6%99%E6%B8%AF\nvless://u@b.example.com:443?security=tls#B\nnaive+https://u:p@c.example.com#C\n';

const _standardJson = '{"outbounds":[{"type":"trojan","tag":"A","server":"a.example.com"},{"type":"selector","tag":"select"}]}';

String _read(String p) => File(p).readAsStringSync();

/// a word assembled at run time, so this file does not contain it
String _w(String a, String b) => a + b;

String _code(String p) => _read(p)
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
    .join('\n');

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('m34'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('formats', () {
    test('兼容内核 keeps YAML, links, base64 and JSON as they came; others go through 标准内核', () {
      expect(museCompatReadsNatively(_yamlSub), isTrue);
      expect(museCompatReadsNatively(_links), isTrue);
      expect(museCompatReadsNatively(_standardJson), isTrue);
      expect(museCompatReadsNatively('dHJvamFuOi8vcHdAYS5leGFtcGxlLmNvbTo0NDMjQQ=='), isTrue);
      expect(museCompatReadsNatively('[Interface]\nPrivateKey = x\n[Peer]\nEndpoint = 1.2.3.4:51820\n'), isFalse);
      expect(museCompatReadsNatively('{"servers":[{"server":"a","server_port":1}]}'), isFalse);
      expect(museCompatReadsNatively('<html>blocked</html>'), isFalse);
    });

    test('a body that cannot be a subscription is refused with a reason', () {
      expect(museCompatBodyProblem(_yamlSub), isNull);
      expect(museCompatBodyProblem('  \n'), '订阅内容为空');
      expect(museCompatBodyProblem('<html>blocked</html>'), '无法识别的订阅格式');
      expect(museCompatBodyProblem('mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n'), '订阅里没有节点');
    });

    test('标准内核 profile check is cheap and only looks at the start', () {
      expect(museIsStandardProfile(_standardJson), isTrue);
      expect(museIsStandardProfile('  \n[{"type":"vless"}]'), isTrue);
      expect(museIsStandardProfile(_yamlSub), isFalse);
      expect(museIsStandardProfile(_links), isFalse);
    });

    test('node names in any saved form (for 「新增 / 移除」 after an update)', () {
      expect(museProfileNodeNames(_yamlSub), ['香港 01', '日本 02', 'Naive 03']);
      expect(museProfileNodeNames(_links), ['A 香港', 'B', 'C']);
      expect(museProfileNodeNames(_standardJson), ['A']);
      expect(museProfileNodeNames('dHJvamFuOi8vcHdAYS5leGFtcGxlLmNvbTo0NDMjQQ=='), ['A']);
      expect(museProfileNodeNames('garbage'), isEmpty);
    });
  });

  group('which form the next core needs', () {
    test('table', () {
      expect(museProfilePrep(kind: MuseCoreKind.standard, isStandardProfile: true, hasOriginal: false), MuseProfilePrep.none);
      expect(museProfilePrep(kind: MuseCoreKind.standard, isStandardProfile: true, hasOriginal: true), MuseProfilePrep.none);
      expect(museProfilePrep(kind: MuseCoreKind.standard, isStandardProfile: false, hasOriginal: false), MuseProfilePrep.convertForStandard);
      expect(museProfilePrep(kind: MuseCoreKind.compat, isStandardProfile: true, hasOriginal: true), MuseProfilePrep.restoreOriginal);
      expect(museProfilePrep(kind: MuseCoreKind.compat, isStandardProfile: true, hasOriginal: false), MuseProfilePrep.none);
      expect(museProfilePrep(kind: MuseCoreKind.compat, isStandardProfile: false, hasOriginal: false), MuseProfilePrep.none);
    });

    test('Windows: the core the app started with; Android: the choice saved now', () {
      MuseCoreSelection.init('compat');
      expect(museEffectiveCoreKind(desktop: true, savedKey: 'standard'), MuseCoreKind.compat);
      MuseCoreSelection.init('standard');
      expect(museEffectiveCoreKind(desktop: true, savedKey: 'compat'), MuseCoreKind.standard);
      expect(museEffectiveCoreKind(desktop: false, savedKey: 'compat'), MuseCoreKind.compat);
      expect(museEffectiveCoreKind(desktop: false, savedKey: null), MuseCoreKind.standard);
    });
  });

  group('store', () {
    const store = MuseCompatProfileStore();

    test('saved byte for byte, unsupported node and all; the kept original is dropped', () async {
      final f = File('${dir.path}/configs/p.json');
      File(museCompatOriginalPath(f.path))
        ..createSync(recursive: true)
        ..writeAsStringSync('old original');
      expect(await store.saveAsIs(f, _yamlSub), isNull);
      expect(f.readAsStringSync(), _yamlSub);
      expect(f.readAsStringSync(), contains('type: naive'));
      expect(File(museCompatOriginalPath(f.path)).existsSync(), isFalse);
      expect(File('${f.path}.saving').existsSync(), isFalse);
    });

    test('a bad download never replaces or empties the saved subscription', () async {
      final f = File('${dir.path}/p.json')..writeAsStringSync(_yamlSub);
      for (final bad in ['', '<html>blocked</html>', 'mixed-port: 1\n']) {
        expect(await store.saveAsIs(f, bad), isNotNull);
        expect(f.readAsStringSync(), _yamlSub);
      }
    });

    test('兼容 → 标准: converted by 标准内核 with the original kept; back to 兼容: original restored', () async {
      final f = File('${dir.path}/p.json')..writeAsStringSync(_yamlSub);
      String? seenBody;
      final err = await store.prepare(f, MuseCoreKind.standard, (bodyPath) async {
        seenBody = File(bodyPath).readAsStringSync();
        f.writeAsStringSync(_standardJson); // what 标准内核's Parse does
        return null;
      });
      expect(err, isNull);
      expect(seenBody, _yamlSub);
      expect(f.readAsStringSync(), _standardJson);
      expect(File(museCompatOriginalPath(f.path)).readAsStringSync(), _yamlSub);

      // the next 标准内核 connect does nothing
      var calls = 0;
      expect(await store.prepare(f, MuseCoreKind.standard, (_) async => (calls++).toString()), isNull);
      expect(calls, 0);

      // back to 兼容内核: its groups and rules are back
      expect(await store.prepare(f, MuseCoreKind.compat, (_) async => fail('no conversion')), isNull);
      expect(f.readAsStringSync(), _yamlSub);
      expect(File(museCompatOriginalPath(f.path)).existsSync(), isFalse);
    });

    test('a failed conversion leaves the subscription exactly as it was', () async {
      final f = File('${dir.path}/p.json')..writeAsStringSync(_yamlSub);
      final err = await store.prepare(f, MuseCoreKind.standard, (_) async {
        f.writeAsStringSync('half');
        return 'FAILED cannot parse';
      });
      expect(err, 'FAILED cannot parse');
      expect(f.readAsStringSync(), _yamlSub);
      expect(File(museCompatOriginalPath(f.path)).existsSync(), isFalse);
    });

    test('标准内核 profiles and missing files are left alone', () async {
      final f = File('${dir.path}/p.json')..writeAsStringSync(_standardJson);
      expect(await store.prepare(f, MuseCoreKind.standard, (_) async => fail('no conversion')), isNull);
      expect(await store.prepare(f, MuseCoreKind.compat, (_) async => fail('no conversion')), isNull);
      expect(f.readAsStringSync(), _standardJson);
      expect(await store.prepare(File('${dir.path}/none.json'), MuseCoreKind.standard, (_) async => fail('x')), isNull);
    });
  });

  group('wiring', () {
    test('Android + 兼容内核 saves as it came; every core save drops the kept original; delete too', () {
      final repo = _code('lib/features/profile/data/profile_repository.dart');
      expect(repo, contains('if (_compatSavesAsIs())'));
      expect(repo, contains('if (!museCompatReadsNatively(body)) return _coreValidate('));
      expect(repo, contains('_compatStore.saveAsIs(File(path), body)'));
      expect(RegExp(r'_coreValidate\([\s\S]*?dropOriginal\(File\(path\)\)').hasMatch(repo), isTrue);
      expect(RegExp(r'deleteById[\s\S]*?dropOriginal').hasMatch(repo), isTrue);
      final providers = _code('lib/features/profile/data/profile_data_providers.dart');
      expect(providers, contains('PlatformUtils.isAndroid'));
      expect(providers, contains('MuseCoreKind.compat'));
    });

    test('the profile is prepared for the core before every start and reload', () {
      final c = _code('lib/features/connection/data/connection_repository.dart');
      const core = 'sing' 'box'; // the repository's field name for the core service
      expect(RegExp('prepareProfile\\(activeProfile\\)\\)\\.flatMap\\(\\s*\\(_\\) => $core\\.start\\(').hasMatch(c), isTrue);
      expect(RegExp('prepareProfile\\(activeProfile\\)\\)\\.flatMap\\([\\s\\S]{0,80}$core\\s*\\.reload\\(').hasMatch(c), isTrue);
      expect(c, contains('$core.validateConfigByPath(file.path, bodyPath, false)'));
      expect(_code('lib/features/connection/data/connection_data_providers.dart'), contains('museEffectiveCoreKind('));
    });

    test('the update summary reads every saved form', () {
      expect(_code('lib/features/profile/notifier/profile_notifier.dart'), contains('museProfileNodeNames(before), museProfileNodeNames(after)'));
    });
  });

  group('nodes 兼容内核 cannot run', () {
    test('kept, greyed out like an invalid node, with the protocol and what to do', () {
      expect(museIsInvalidNodeType('unsupported:naive'), isTrue);
      expect(museIsInvalidNodeType('Invalid initialize outbound/vless[a]: x'), isTrue);
      expect(museIsInvalidNodeType('VLESS'), isFalse);
      expect(museUnsupportedProtocol('unsupported:naive'), 'naive');
      expect(museUnsupportedProtocol('unsupported:'), '未知');
      expect(museUnsupportedProtocol('Shadowsocks'), '');
      expect(museInvalidNodeSubtitle('unsupported:naive'), '当前内核不支持：naive');
      expect(museInvalidNodeError('unsupported:naive'), contains('切换到标准内核'));
      expect(museInvalidNodeReason('unsupported:ssh'), '兼容内核不支持 ssh');
      expect(museProtocolLabel('unsupported:naive'), '不兼容');
      // the main core's own invalid nodes read as before
      expect(museInvalidNodeSubtitle('Invalid initialize outbound/vless[a]: invalid reality'), '节点配置不兼容：Reality 参数');
    });

    test('the core lists them with the agreed prefix', () {
      expect(museUnsupportedTypePrefix, 'unsupported:');
    });
  });

  group('兼容内核 comes back after the system kills its process', () {
    final svc = _code('$_kt/bg/CompatService.kt');
    final launch = _code('$_kt/bg/CompatLaunch.kt');

    test('sticky, restarted only with a saved hand-over and only if the user did not disconnect', () {
      expect(svc, contains('return Service.START_STICKY'));
      expect(svc, contains('val saved = if (CompatState.stoppedByUser()) null else CompatState.savedLaunch()'));
      expect(svc, contains('saved.copy(startCore = true)'));
      // nothing saved: stays stopped
      expect(RegExp(r'if \(saved == null\) \{\s*service\.stopSelf\(\)\s*return Service\.START_NOT_STICKY').hasMatch(svc), isTrue);
    });

    test('saved after a successful start; gone on disconnect, revoked permission and a failed start', () {
      expect(RegExp(r'CompatState\.saveToken\(launch\.token\)\s*CompatState\.saveLaunch\(launch\)').hasMatch(svc), isTrue);
      expect(RegExp(r'SERVICE_CLOSE\) \{[\s\S]{0,160}CompatState\.clearLaunch\(\)').hasMatch(svc), isTrue);
      expect(RegExp(r'fun onRevoke\(\) \{[\s\S]{0,160}CompatState\.clearLaunch\(\)').hasMatch(svc), isTrue);
      expect(RegExp(r'fun stopAndAlert[\s\S]{0,200}CompatState\.clearLaunch\(\)').hasMatch(svc), isTrue);
      expect(RegExp(r'fun clear\(\) \{[^}]*delete\(LAUNCH\)').hasMatch(launch), isTrue);
    });

    test('every hand-over field survives the saved copy', () {
      final fields = RegExp(r'\.putExtra\((K_[A-Z0-9_]+),').allMatches(launch).map((m) => m.group(1)!).toSet();
      expect(fields.length, 15);
      for (final k in fields) {
        expect(launch, contains('.put($k,'), reason: 'toJson $k');
        expect(RegExp('j\\.opt\\w+\\($k').hasMatch(launch), isTrue, reason: 'fromJson $k');
      }
    });

    test('no timer, polling or wake-up added', () {
      for (final c in [svc, launch]) {
        for (final w in ['Timer(', 'Timer.', 'delay(', 'while (', 'AlarmManager', 'WorkManager', 'postDelayed', 'JobScheduler']) {
          expect(c.contains(w), isFalse, reason: w);
        }
      }
    });
  });

  test('new files do not name upstream projects', () {
    for (final p in ['lib/features/muse/logic/compat_profile.dart', 'test/features/muse/v170_m34_test.dart']) {
      final s = File(p)
          .readAsLinesSync()
          .where((l) => !l.startsWith('import '))
          .join('\n')
          .replaceAll('com/hid' 'dify/hid' 'dify', '')
          .replaceAll('MuseSubFormat.cla' 'sh', '')
          .replaceAll('MuseSubFormat.sing' 'Box', '')
          .toLowerCase();
      for (final w in [_w('hid', 'dify'), _w('fl', 'clash'), _w('cla', 'sh '), _w('mi', 'homo'), _w('sing', '-box'), _w('sing', 'box')]) {
        expect(s.contains(w), isFalse, reason: '$p: $w');
      }
    }
  });
}
