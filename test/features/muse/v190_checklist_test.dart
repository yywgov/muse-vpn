// 穿云 1.9.0 #4: 真机测试清单 docs/device-test-checklist.md 存在、可勾选、覆盖约定的项目。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final text = File('docs/device-test-checklist.md').readAsStringSync();

  test('#4 checklist has both platforms and unchecked boxes', () {
    expect(text, contains('## Android'));
    expect(text, contains('## Windows'));
    expect(RegExp(r'^- \[ \] ', multiLine: true).allMatches(text).length, greaterThan(40));
    expect(text, isNot(contains('- [x]')));
  });

  test('#4 covers every agreed area on both platforms', () {
    final android = text.substring(text.indexOf('## Android'), text.indexOf('## Windows'));
    final windows = text.substring(text.indexOf('## Windows'));
    for (final s in ['标准内核', '兼容内核', '断网重连', '杀后台恢复', '分应用代理', '活动页', '数据流停止', 'DNS 页', '新设置页', '覆写', '首次引导']) {
      expect(android, contains(s), reason: 'Android $s');
    }
    for (final s in ['标准内核', '兼容内核', '断网重连', '杀后台恢复', '活动页', '数据流停止', 'DNS 页', '新设置页', '覆写', '首次引导', '开机自启时静默']) {
      expect(windows, contains(s), reason: 'Windows $s');
    }
  });

  test('#4 no upstream project names', () {
    expect(text.toLowerCase(), isNot(anyOf(contains('hiddify'), contains('flclash'), contains('clash meta'))));
  });
}
