// 穿云 1.19.3: 启动恢复连接遇到一次连接 / gRPC 错误时，重建通道后重试一次（单次 400 ms 退避），
// 仍失败才把 started_by_user 置 false；每条失败路径都释放内核；用户主动连接 / 断开的路径不重试。
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/startup_restore.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reset = 'Stream error: ... HTTP/2 error: Connection error: Connection is being forcefully terminated. (errorCode: 1)';
const _transient = ConnectionFailure.unexpected(_reset);

class _FakeRepo implements ConnectionRepository {
  final calls = <String>[];

  /// results of the next connect calls (right when the list runs out)
  final results = <ConnectionFailure?>[];
  bool coreAnswers = true;
  Completer<void>? reopenGate;
  final status = StreamController<ConnectionStatus>.broadcast();

  @override
  SingboxConfigOption? get configOptionsSnapshot => null;

  @override
  TaskEither<ConnectionFailure, Unit> setup() => TaskEither.right(unit);

  @override
  Stream<ConnectionStatus> watchConnectionStatus() async* {
    yield const Disconnected();
    yield* status.stream;
  }

  @override
  Stream<bool> watchHotReloading() => const Stream.empty();

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      TaskEither(() async {
        calls.add('connect');
        final f = results.isEmpty ? null : results.removeAt(0);
        return f == null ? right(unit) : left(f);
      });

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => TaskEither(() async {
    calls.add('disconnect');
    return right(unit);
  });

  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      TaskEither(() async {
        calls.add('reconnect');
        return right(unit);
      });

  @override
  Future<bool> reopenCoreChannel() async {
    calls.add('reopen');
    await reopenGate?.future;
    return coreAnswers;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Active extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() =>
      Stream.value(ProfileEntity.local(id: 'p', active: true, name: 'p', lastUpdate: DateTime(2026)));
}

class _Dialogs extends DialogNotifier {
  _Dialogs(this.log);
  final List<String> log;
  @override
  Future<void> showCustomAlertFromErr(({String type, String? message}) err) async => log.add('${err.message}');
}

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('museIsTransientCoreFailure', () {
    test('connection / gRPC transport errors are transient', () {
      expect(museIsTransientCoreFailure(_transient), isTrue);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected('failed to start background core')), isTrue);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected('background core is not started yet!')), isTrue);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected(GrpcError.unavailable('x'))), isTrue);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected(GrpcError.unknown('HTTP/2 error'))), isTrue);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected('The http/2 connection is no longer active')), isTrue);
    });

    test('config, permission and real core refusals are not', () {
      expect(museIsTransientCoreFailure(const ConnectionFailure.invalidConfig('bad')), isFalse);
      expect(museIsTransientCoreFailure(const ConnectionFailure.invalidConfigOption('port')), isFalse);
      expect(museIsTransientCoreFailure(const ConnectionFailure.missingPrivilege()), isFalse);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected()), isFalse);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected('内核启动失败（ERROR）：listen tcp: bind')), isFalse);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected(GrpcError.invalidArgument('x'))), isFalse);
      expect(museIsTransientCoreFailure(const ConnectionFailure.unexpected(GrpcError.permissionDenied('x'))), isFalse);
    });
  });

  group('museRestoreConnect', () {
    late List<String> log;
    late List<Either<String, Unit>> results;
    var wanted = true;
    var answers = true;
    final waits = <Duration>[];

    Future<Either<String, Unit>> run() => museRestoreConnect<String>(
      attempt: () async {
        log.add('attempt');
        return results.removeAt(0);
      },
      isTransient: (f) => f == 'reset',
      reopenChannel: () async {
        log.add('reopen');
        return answers;
      },
      release: () async => log.add('release'),
      stillWanted: () => wanted,
      wait: (d) async {
        waits.add(d);
        log.add('wait');
      },
    );

    setUp(() {
      log = [];
      wanted = true;
      answers = true;
      waits.clear();
    });

    test('success the first time: nothing else', () async {
      results = [right(unit)];
      expect((await run()).isRight(), isTrue);
      expect(log, ['attempt']);
    });

    test('one transient failure, then success: release → short wait → new channel → retry', () async {
      results = [left('reset'), right(unit)];
      expect((await run()).isRight(), isTrue);
      expect(log, ['attempt', 'release', 'wait', 'reopen', 'attempt']);
      expect(waits, [museRestoreRetryDelay]);
      expect(museRestoreRetryDelay.inMilliseconds, inInclusiveRange(300, 500));
    });

    test('two transient failures: fails, released after each, retried only once', () async {
      results = [left('reset'), left('reset'), right(unit)];
      expect((await run()).getLeft().toNullable(), 'reset');
      expect(log, ['attempt', 'release', 'wait', 'reopen', 'attempt', 'release']);
      expect(results, hasLength(1), reason: 'no third attempt');
      expect(museRestoreMaxAttempts, 2);
    });

    test('a non-transient failure is not retried but still releases the core', () async {
      results = [left('bad config')];
      expect((await run()).isLeft(), isTrue);
      expect(log, ['attempt', 'release']);
    });

    test('the core does not answer on a new channel: no retry', () async {
      answers = false;
      results = [left('reset'), right(unit)];
      expect((await run()).isLeft(), isTrue);
      expect(log, ['attempt', 'release', 'wait', 'reopen']);
    });

    test('the user no longer wants it (disconnected / cancelled): no retry, no extra release', () async {
      wanted = false;
      results = [left('reset'), right(unit)];
      expect((await run()).isLeft(), isTrue);
      expect(log, ['attempt']);
    });
  });

  group('restoreConnectionOnStartup', () {
    late _FakeRepo repo;
    late ProviderContainer c;
    late ConnectionNotifier notifier;
    late List<String> dialogs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'started_by_user': true});
      final prefs = await SharedPreferences.getInstance();
      repo = _FakeRepo();
      dialogs = [];
      c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => Future.value(prefs)),
          connectionRepositoryProvider.overrideWithValue(repo),
          activeProfileProvider.overrideWith(_Active.new),
          dialogNotifierProvider.overrideWith(() => _Dialogs(dialogs)),
          translationsProvider.overrideWith((ref) => AppLocale.zhCn.build()),
        ],
      );
      await c.read(sharedPreferencesProvider.future);
      await c.read(activeProfileProvider.future);
      await c.read(translationsProvider.future);
      c.listen(connectionNotifierProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      notifier = c.read(connectionNotifierProvider.notifier);
    });
    tearDown(() => c.dispose());

    // the connect runs behind SingleCall (not awaited by its callers): wait past the 400 ms retry
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 800));

    test('one connection reset, then the retry works: intent kept, no error shown', () async {
      repo.results.add(_transient);
      await notifier.restoreConnectionOnStartup();
      await settle();
      expect(repo.calls, ['connect', 'disconnect', 'reopen', 'connect']);
      expect(c.read(Preferences.startedByUser), isTrue);
      expect(dialogs, isEmpty);
      expect(notifier.lastIntentionalStopAt, isNotNull, reason: 'the release is our own stop (keeper stays out)');
    });

    test('two failures in a row: started_by_user = false, the core is released', () async {
      repo.results.addAll([_transient, _transient]);
      await notifier.restoreConnectionOnStartup();
      await settle();
      expect(repo.calls, ['connect', 'disconnect', 'reopen', 'connect', 'disconnect']);
      expect(c.read(Preferences.startedByUser), isFalse);
      expect(dialogs, hasLength(1));
    });

    test('the core does not answer on a new channel: fails without a second connect', () async {
      repo.results.add(_transient);
      repo.coreAnswers = false;
      await notifier.restoreConnectionOnStartup();
      await settle();
      expect(repo.calls, ['connect', 'disconnect', 'reopen']);
      expect(c.read(Preferences.startedByUser), isFalse);
    });

    test('a config error is not retried (released, intent off as before)', () async {
      repo.results.add(const ConnectionFailure.invalidConfig('bad'));
      await notifier.restoreConnectionOnStartup();
      await settle();
      expect(repo.calls, ['connect', 'disconnect']);
      expect(c.read(Preferences.startedByUser), isFalse);
    });

    test('the user taps 断开 during the retry wait: no retry, no error, intent stays off', () async {
      repo.results.add(_transient);
      repo.reopenGate = Completer();
      final restoring = notifier.restoreConnectionOnStartup();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      notifier.intentGeneration++; // what toggleConnection / 托盘断开 do
      await c.read(Preferences.startedByUser.notifier).update(false);
      repo.reopenGate!.complete();
      await restoring;
      await settle();
      expect(repo.calls.where((e) => e == 'connect'), hasLength(1));
      expect(c.read(Preferences.startedByUser), isFalse);
      expect(dialogs, isEmpty);
    });

    test('a connect the user starts is not retried', () async {
      await c.read(Preferences.startedByUser.notifier).update(false);
      repo.results.add(_transient);
      await notifier.toggleConnection();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.calls, ['connect']);
      expect(c.read(Preferences.startedByUser), isFalse);
      expect(dialogs, hasLength(1));
    });

    test("the user's own disconnect is unchanged (one stop, no reopen)", () async {
      repo.status.add(const Connected());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.toggleConnection();
      expect(repo.calls, ['disconnect']);
      expect(c.read(Preferences.startedByUser), isFalse);
    });
  });

  test('wiring: only the start-up restore retries, without timers or polling', () {
    final n = _src('lib/features/connection/notifier/connection_notifier.dart');
    expect(n, contains('_connect(restoring: true)'));
    expect(RegExp('restoring: true').allMatches(n), hasLength(1));
    final s = _src('lib/features/muse/logic/startup_restore.dart');
    expect(s, isNot(contains('Timer')));
    expect(s, isNot(contains('while (')));
    expect(s, isNot(contains('for (')));
    final d = _src('lib/hiddifycore/core_interface/core_interface_desktop.dart');
    expect(d, contains('Future<void> resetChannel()'));
    final svc = _src('lib/hiddifycore/hiddify_core_service.dart');
    expect(svc, contains('Future<bool> reopenChannel()'));
  });
}
