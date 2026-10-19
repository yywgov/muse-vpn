// 穿云 1.2.2: the connection keeper's recovery vs. the user's own connect / disconnect.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo implements ConnectionRepository {
  final calls = <String>[];
  Completer<void>? connectGate;
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
        await connectGate?.future;
        return right(unit);
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Active extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() =>
      Stream.value(ProfileEntity.local(id: 'p', active: true, name: 'p', lastUpdate: DateTime(2026)));
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer c;
  late ConnectionNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'started_by_user': true});
    final prefs = await SharedPreferences.getInstance();
    repo = _FakeRepo();
    c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        connectionRepositoryProvider.overrideWithValue(repo),
        activeProfileProvider.overrideWith(_Active.new),
      ],
    );
    await c.read(sharedPreferencesProvider.future);
    await c.read(activeProfileProvider.future);
    c.listen(connectionNotifierProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    notifier = c.read(connectionNotifierProvider.notifier);
  });
  tearDown(() => c.dispose());

  Future<void> userDisconnects() async {
    notifier.intentGeneration++;
    await c.read(Preferences.startedByUser.notifier).update(false);
  }

  test('a normal recovery stops and starts the core', () async {
    final ok = await notifier.recoverConnection(generation: notifier.intentGeneration);
    expect(ok, isTrue);
    expect(repo.calls, ['disconnect', 'connect']);
  });

  test('the user taps 断开 while the recovery connect runs: the core is stopped again', () async {
    repo.connectGate = Completer();
    final attempt = notifier.recoverConnection(generation: notifier.intentGeneration);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.calls, ['disconnect', 'connect']);
    await userDisconnects();
    repo.connectGate!.complete();
    expect(await attempt, isFalse);
    expect(repo.calls, ['disconnect', 'connect', 'disconnect']);
  });

  test('a second call while one runs joins it (no overlapping connect)', () async {
    repo.connectGate = Completer();
    final g = notifier.intentGeneration;
    final first = notifier.recoverConnection(generation: g);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notifier.recoveryInFlight, isTrue);
    final second = notifier.recoverConnection(generation: g);
    repo.connectGate!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(repo.calls.where((e) => e == 'connect').length, 1);
    expect(notifier.recoveryInFlight, isFalse);
  });

  test('a recovery from before the user\'s own connect does nothing', () async {
    final old = notifier.intentGeneration;
    notifier.intentGeneration++; // the user connected by hand meanwhile (still wants it on)
    expect(await notifier.recoverConnection(generation: old), isFalse);
    expect(repo.calls, isEmpty);
  });

  test('the user disconnected before the recovery started: nothing happens', () async {
    final g = notifier.intentGeneration;
    await c.read(Preferences.startedByUser.notifier).update(false);
    expect(await notifier.recoverConnection(generation: g), isFalse);
    expect(repo.calls, isEmpty);
  });
}
