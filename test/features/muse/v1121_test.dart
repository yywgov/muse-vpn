// 穿云 1.12.1: 「意外失败 / createService - null」 regression tests.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_mobile.dart';
import 'package:hiddify/singbox/model/core_status.dart';

String _src(String p) => File(p).readAsStringSync();

String _fnBody(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  var depth = 0;
  var i = src.indexOf('{', start);
  final open = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return src.substring(open, i + 1);
}

void main() {
  const box = 'android/app/src/main/kotlin/com/hiddify/hiddify/bg/BoxService.kt';
  const handler = 'android/app/src/main/kotlin/com/hiddify/hiddify/MethodHandler.kt';

  group('后台内核在启动失败时必须关闭（17079 不得残留）', () {
    test('BoxService.stopAndAlert releases the background core and stops the service', () {
      final body = _fnBody(_src(box), 'private suspend fun stopAndAlert(');
      expect(body, contains('releaseCore()'));
      expect(body, contains('service.stopSelf()'));
      expect(body.indexOf('releaseCore()'), lessThan(body.indexOf('status.value = Status.Stopped')));
    });

    test('releaseCore closes mode 4 and never throws', () {
      final body = _fnBody(_src(box), 'fun releaseCore()');
      // 1.13.0: closed through CoreStop (own thread, at most 10 s), which closes mode 4
      expect(body, contains('CoreStop.closeWithin('));
      expect(_fnBody(_src('android/app/src/main/kotlin/com/hiddify/hiddify/bg/CoreStop.kt'), 'fun closeWithin('), contains('Mobile.close(4L)'));
      expect(body, contains('catch (e: Throwable)'));
    });

    test('in-app stop closes a leftover background core when no service is running', () {
      final s = _src(handler);
      final stop = s.substring(s.indexOf('Trigger.Stop.method ->'));
      final body = stop.substring(0, stop.indexOf('Trigger.', 10));
      expect(body, contains('Status.Stopped'));
      expect(body, contains('BoxService.releaseCore()'));
    });

    test('start errors carry the exception type, never a bare null', () {
      final s = _src(box);
      expect(s, isNot(contains('stopAndAlert(Alert.CreateService, e.message)')));
      expect(s, isNot(contains('stopAndAlert(Alert.StartService, e.message)')));
      expect(s, contains('stopAndAlert(Alert.CreateService, describeError(e))'));
      final d = _fnBody(s, 'fun describeError(');
      expect(d, contains('javaClass.simpleName'));
      expect(d, contains('内核没有给出原因'));
    });

    test('Dart asks again before giving up, with a reason', () {
      final s = _src('lib/hiddifycore/core_interface/core_interface_mobile.dart');
      expect(s, contains('if (!await stop() && !await stop()) return const CoreStatus.stopped(alert: CoreAlert.createService, message: bgPortBusyMessage);'));
      expect(bgPortBusyMessage, contains('17079'));
      expect(bgPortBusyMessage, contains('强行停止'));
    });
  });

  group('错误提示中文化', () {
    test('createService with no message is explained, not 「null」', () {
      final t = describeCoreAlert(CoreAlert.createService, null);
      expect(t, isNot(contains('null')));
      expect(t, contains('创建后台服务失败'));
      expect(t, contains('createService'));
      expect(t, contains('内核没有给出原因'));
      expect(describeCoreAlert(CoreAlert.createService, 'null'), isNot(contains('：null')));
    });

    test('a reason is kept', () {
      expect(describeCoreAlert(CoreAlert.startService, 'NullPointerException（内核没有给出原因）'), '启动内核失败（startService）：NullPointerException（内核没有给出原因）');
      expect(describeCoreAlert(CoreAlert.createService, bgPortBusyMessage), contains('17079'));
    });

    test('the failure the user sees uses it', () {
      const f = CoreStatus.stopped(alert: CoreAlert.createService);
      expect(f.getCoreAlert().toString(), isNot(contains('createService - null')));
      expect(f.getCoreAlert().toString(), contains('创建后台服务失败'));
    });
  });

  group('e2e 覆盖用户路径', () {
    test('e2e reproduces a failed widget/tile start, then connects from the home button', () {
      final s = _src('test_driver/muse_e2e_test.dart');
      expect(s, contains('stale-bg-core'));
      expect(s, contains('createService'));
      expect(s, contains('tapHomeConnect'));
    });
  });

  group('版本 1.12.1', () {
    test('pubspec and changelog', () {
      // 1.13.0: later versions follow; 1.12.1 keeps its entry
      expect(int.parse(RegExp(r'version: [\d.]+\+(\d+)').firstMatch(_src('pubspec.yaml'))!.group(1)!), greaterThanOrEqualTo(201));
      expect(museChangelog.keys, contains('1.12.1'));
      expect(museChangelog['1.12.1']!.join(), contains('createService'));
      expect(_src('CHANGELOG.md'), contains('### 1.12.1'));
    });
  });
}
