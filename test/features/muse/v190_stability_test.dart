// 穿云 1.9.0 稳定性：兼容内核看门狗 + 网络回调（事件驱动，不轮询）、服务被销毁后限频自拉起；
// Windows recovery smoke 放宽等待 + 多一次重试；遗留 TODO 清理（mutation_state 删除、
// async_mutation 去掉代码生成并补测试、link_parsers 补测试）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/async_mutation.dart';
import 'package:hiddify/utils/link_parsers.dart';

const _kt = 'android/app/src/main/kotlin/com/hiddify/hiddify';

String _read(String p) => File(p).readAsStringSync();

String _code(String p) => _read(p)
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
    .join('\n');

void main() {
  group('兼容内核 keep-alive (Android)', () {
    final guard = _code('$_kt/bg/CompatGuard.kt');
    final svc = _code('$_kt/bg/CompatService.kt');
    final box = _code('$_kt/bg/BoxService.kt');

    test('watchdog follows the core state stream and restarts with the standard backoff', () {
      expect(guard, contains('CoreWatch.awaitUnexpectedStop'));
      expect(guard, contains('longArrayOf(2_000, 5_000, 10_000, 30_000, 60_000)'));
      // same numbers as the standard service's watchdog
      expect(box, contains('longArrayOf(2_000, 5_000, 10_000, 30_000, 60_000)'));
      expect(guard, contains('.Start()'));
      expect(guard, contains('CompatState.stoppedByUser()'));
      // gives up after the last attempt and tells the user once
      expect(svc, contains('ChuanyunAlerts.ID_DISCONNECTED'));
      expect(svc, contains('CompatState.clearLaunch()'));
    });

    test('network changes come from the system callback and reach the core', () {
      expect(guard, contains('DefaultNetworkListener.start(this@CompatGuard)'));
      expect(guard, contains('DefaultNetworkListener.stop(this@CompatGuard)'));
      expect(guard, contains('CompatCore.nativeNetworkChanged()'));
      expect(_code('$_kt/bg/CompatCore.kt'), contains('external fun nativeNetworkChanged(): Int'));
      // waiting for a network is a suspended wait woken by the callback, not a check loop
      expect(guard, contains('CompletableDeferred<Unit>()'));
      expect(guard, contains('withTimeoutOrNull(maxMillis)'));
      expect(guard.contains('hasUsableNetwork'), isFalse);
      expect(guard.contains('allNetworks'), isFalse);
    });

    test('no timers or polling: every delay is the reconnect backoff or a bounded stream retry', () {
      for (final w in ['Timer(', 'AlarmManager', 'WorkManager', 'postDelayed', 'scheduleAtFixedRate']) {
        expect(guard.contains(w), isFalse, reason: w);
      }
      final delays = RegExp(r'delay\(([^)]*)\)').allMatches(guard).map((m) => m.group(1)).toList();
      expect(delays, ['2_000', '2_000', 'wait']);
      expect(guard, contains('MAX_BROKEN_STREAMS'));
    });

    test('the guard starts with the connection and stops with it', () {
      expect(svc, contains('guard.start()'));
      final release = svc.substring(svc.indexOf('private fun releaseCore()'));
      expect(release.substring(0, release.indexOf('}')), contains('guard.stop()'));
      expect(svc.indexOf('notification.start()') < svc.indexOf('guard.start()'), isTrue);
    });

    test('destroyed while the process lives: one restart from the saved hand-over, at most once a minute', () {
      expect(svc, contains('restartAfterDestroy()'));
      expect(svc, contains('CompatState.mayAutoRestart('));
      expect(svc, contains('ContextCompat.startForegroundService(service, Intent(service, service.javaClass))'));
      final state = _code('$_kt/bg/CompatLaunch.kt');
      expect(state, contains('if (stoppedByUser() || savedLaunch() == null) return false'));
      expect(state, contains('AUTO_RESTART_GAP_MILLIS = 60_000L'));
      // killed process: still START_STICKY with the saved hand-over
      expect(svc, contains('return Service.START_STICKY'));
      expect(svc, contains('CompatState.savedLaunch()'));
    });

    test('CI checks the new JNI export; 兼容内核 source moved past 1.8.0', () {
      expect(_read('.github/workflows/muse-android.yml'), contains('nativeNetworkChanged'));
      final ref = RegExp(r'muse\.compat\.ref=([0-9a-f]{40})').firstMatch(_read('dependencies.properties'))!.group(1);
      expect(ref, isNot('6f5cc4edb940aed007b30e2ec9d1a0b6f172ffce'));
    });

    test('new files do not name upstream projects', () {
      for (final p in ['$_kt/bg/CompatGuard.kt']) {
        final s = _read(p).toLowerCase();
        for (final w in ['hiddify-app', 'flclash', 'clash verge', 'nekobox', 'v2rayng']) {
          expect(s.contains(w), isFalse, reason: '$p: $w');
        }
      }
    });
  });

  group('Windows recovery smoke', () {
    final ps = _read('tool/smoke/recovery_smoke.ps1');
    final wf = _read('.github/workflows/muse-windows.yml');

    test('three tries with a longer step limit', () {
      expect(wf, contains('retry.sh "recovery smoke" 3'));
      final i = wf.indexOf('id: smoke_recovery');
      expect(wf.substring(i, i + 200), contains('timeout-minutes: 45'));
    });

    test('checks wait for the state instead of reading it once after a fixed sleep', () {
      expect(ps, contains('function WaitState([int]\$seconds, [scriptblock]\$ok)'));
      expect(RegExp(r'WaitState 20').allMatches(ps).length, 3);
      expect(ps, contains('\$c = WaitConnected 90\nRec "stale-reconnect"'));
      expect(ps, contains('AddSeconds(60)'));
      expect(ps.contains('WaitConnected 45'), isFalse);
    });
  });

  group('TODO clean-up', () {
    test('no TODO left in lib', () {
      final left = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart') || f.path.endsWith('.freezed.dart')) continue;
        if (f.readAsStringSync().contains(RegExp(r'//\s*TODO'))) left.add(f.path);
      }
      expect(left, isEmpty);
    });

    test('MutationState is gone; AsyncMutation needs no code generation', () {
      expect(File('lib/utils/mutation_state.dart').existsSync(), isFalse);
      expect(_read('lib/utils/utils.dart').contains('mutation_state'), isFalse);
      expect(_read('lib/utils/async_mutation.dart').contains('part '), isFalse);
    });

    test('AsyncMutation states', () {
      expect(const AsyncMutation.idle(), const Idle());
      expect(const AsyncMutation.inProgress().isInProgress, isTrue);
      expect(const AsyncMutation.success().isInProgress, isFalse);
      final st = StackTrace.current;
      expect(AsyncMutation.fail('x', st), Fail('x', st));
      expect(Fail('x', st) == Fail('y', st), isFalse);
      expect(asyncMutationOf(const AsyncSnapshot<int>.nothing()), const Idle());
      expect(asyncMutationOf(const AsyncSnapshot<int>.waiting()), const InProgress());
      expect(asyncMutationOf(const AsyncSnapshot<int>.withData(ConnectionState.done, 1)), const Success());
      expect(asyncMutationOf(AsyncSnapshot<int>.withError(ConnectionState.done, 'e', st)), Fail('e', st));
    });

    testWidgets('useMutation: in progress, then one success callback; failures reach onFailure once', (tester) async {
      var ok = 0;
      final errors = <Object>[];
      late ({AsyncMutation state, ValueChanged<Future<int>> setFuture, ValueChanged<void Function(Object)> setOnFailure}) m;
      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              m = useMutation<int>(initialOnSuccess: () => ok++, initialOnFailure: errors.add);
              return Text(m.state.runtimeType.toString(), textDirection: TextDirection.ltr);
            },
          ),
        ),
      );
      expect(m.state, const Idle());
      m.setFuture(Future<int>.delayed(const Duration(milliseconds: 10), () => 1));
      await tester.pump();
      expect(m.state.isInProgress, isTrue);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(m.state, const Success());
      expect(ok, 1);
      m.setFuture(Future<int>.delayed(const Duration(milliseconds: 10), () => throw StateError('boom')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(m.state, isA<Fail>());
      expect(errors.single, isA<StateError>());
      await tester.pump();
      expect(errors.length, 1);
    });

    group('LinkParser', () {
      test('chuanyun deep links like hiddify ones', () {
        final a = LinkParser.deep('chuanyun://install-config?url=https%3A%2F%2Fsub.com%2Fx#家里');
        expect(a!.url, 'https://sub.com/x');
        expect(a.name, '家里');
        final b = LinkParser.deep('chuanyun://import/https://sub.com/x?token=1#N');
        expect(b!.url, 'https://sub.com/x?token=1');
        expect(b.name, 'N');
      });

      test('panel schemes and garbage', () {
        expect(LinkParser.deep('clash://install-config?url=https%3A%2F%2Fa.com%2Fs')!.url, 'https://a.com/s');
        expect(LinkParser.deep('sing-box://import-remote-profile?url=https%3A%2F%2Fa.com%2Fs&name=X')!.name, 'X');
        expect(LinkParser.parse('not a link'), isNull);
        expect(LinkParser.parse(''), isNull);
        expect(LinkParser.deep('clashmeta://'), isNull);
      });

      test('simple() keeps the url and reads name=', () {
        final s = LinkParser.simple('  https://a.com/s?name=Foo  ');
        expect(s!.url, 'https://a.com/s?name=Foo');
        expect(s.name, 'Foo');
        expect(LinkParser.simple('https://a.com/s')!.name, '');
        expect(LinkParser.simple('vless://uuid@host:443'), isNull);
      });

      test('share link puts the name in the fragment', () {
        expect(LinkParser.generateSubShareLink('https://a.com/s?t=1', '我的'), 'https://a.com/s?t=1#%E6%88%91%E7%9A%84');
        expect(LinkParser.generateSubShareLink('https://a.com/s#Old'), 'https://a.com/s#Old');
        expect(LinkParser.protocols, containsAll(['chuanyun', 'hiddify', 'clash', 'sing-box']));
      });

      test('safeDecodeBase64 falls back to the input', () {
        expect(safeDecodeBase64('5L2g5aW9'), '你好');
        expect(safeDecodeBase64('not base64!'), 'not base64!');
      });
    });
  });
}
