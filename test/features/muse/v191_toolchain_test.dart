// 穿云 1.9.1 安全：Flutter 3.47.8 / Dart 3.13.7 起 dart:io 拒绝泄露的 eMudhra 中间 CA（GHSA-frr6-h895-5pxp，
// Android / Windows 受影响：订阅拉取、应用内更新都走 dart:io）；兼容内核按 muse-core 的 go.mod 构建，
// 需 Go 1.26.10+（crypto/x509 同一批中间 CA，CVE-2026-111943）。构建工具链退回旧版时这里失败。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<int> _ver(String s) {
  final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(s)!;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

bool _atLeast(String v, String min) {
  final a = _ver(v), b = _ver(min);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return true;
}

void main() {
  test('version compare', () {
    expect(_atLeast('3.47.8', '3.47.8'), isTrue);
    expect(_atLeast('3.47.7', '3.47.8'), isFalse);
    expect(_atLeast('3.38.5', '3.47.8'), isFalse);
    expect(_atLeast('3.50.0', '3.47.8'), isTrue);
    expect(_atLeast('3.13.7 (stable)', '3.13.7'), isTrue);
  });

  test('tests run on a patched Dart SDK (3.13.7+)', () {
    expect(_atLeast(Platform.version, '3.13.7'), isTrue, reason: Platform.version);
  });

  test('every CI workflow pins Flutter 3.47.8+', () {
    final files = Directory('.github/workflows').listSync().whereType<File>().where((f) => f.path.endsWith('.yml'));
    var pins = 0;
    for (final f in files) {
      for (final m in RegExp(r"(?<![A-Z_])FLUTTER_VERSION:\s*'([\d.]+)'").allMatches(f.readAsStringSync())) {
        pins++;
        expect(_atLeast(m.group(1)!, '3.47.8'), isTrue, reason: '${f.path}: ${m.group(1)}');
      }
    }
    expect(pins, greaterThanOrEqualTo(3));
  });

  test('pubspec requires Flutter 3.47.8+', () {
    final m = RegExp(r'^\s+flutter:\s*\^([\d.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull);
    expect(_atLeast(m!.group(1)!, '3.47.8'), isTrue);
  });

  test('兼容内核 is built with the Go version muse-core go.mod asks for', () {
    for (final wf in ['muse-android.yml', 'muse-windows.yml']) {
      expect(File('.github/workflows/$wf').readAsStringSync(), contains('go-version-file: core/mihomo/go.mod'));
    }
  });
}
