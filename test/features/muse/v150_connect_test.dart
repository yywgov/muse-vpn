// 穿云 1.5.0 #3 / #82: the connect button as a state machine — 连接中 cancels (a connect that
// finishes afterwards is undone), 断开中 ignores taps; 准备配置 while the config is prepared.
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
    SharedPreferences.setMockInitialValues({'started_by_user': false});
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

  Future<void> emit(ConnectionStatus s) async {
    repo.status.add(s);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('a tap while connecting cancels: the core is stopped, the intent is off', () async {
    await emit(const Connecting());
    await notifier.toggleConnection();
    expect(repo.calls, ['disconnect']);
    expect(c.read(Preferences.startedByUser), isFalse);
  });

  test('a tap while disconnecting does nothing', () async {
    await emit(const Disconnecting());
    await notifier.toggleConnection();
    expect(repo.calls, isEmpty);
  });

  test('cancelled while the core starts: the connect that finishes afterwards is undone', () async {
    repo.connectGate = Completer();
    final connecting = notifier.toggleConnection();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.calls, ['connect']);
    await emit(const Connecting());
    await notifier.toggleConnection();
    expect(repo.calls, ['connect', 'disconnect']);
    repo.connectGate!.complete();
    await connecting;
    expect(repo.calls, ['connect', 'disconnect', 'disconnect']);
    expect(c.read(Preferences.startedByUser), isFalse);
  });

  test('a connect that is not cancelled is left alone', () async {
    await notifier.toggleConnection();
    expect(repo.calls, ['connect']);
    expect(c.read(Preferences.startedByUser), isTrue);
  });

  test('准备配置 is on while the config is prepared and off afterwards', () async {
    repo.connectGate = Completer();
    final seen = <bool>[];
    c.listen(museConnectPreparingProvider, (_, v) => seen.add(v));
    final connecting = notifier.toggleConnection();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(museConnectPreparingProvider), isTrue);
    expect(notifier.preparing, isTrue);
    repo.connectGate!.complete();
    await connecting;
    expect(c.read(museConnectPreparingProvider), isFalse);
    expect(seen, [true, false]);
  });

  test('a second tap while preparing cancels before anything else happens', () async {
    repo.connectGate = Completer();
    final connecting = notifier.toggleConnection();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // still 未连接 (the fake never reports Connecting), but preparing
    await notifier.toggleConnection();
    expect(c.read(Preferences.startedByUser), isFalse);
    repo.connectGate!.complete();
    await connecting;
    expect(repo.calls.last, 'disconnect');
    expect(c.read(museConnectPreparingProvider), isFalse);
  });
}
