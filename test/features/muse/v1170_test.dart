// 穿云 1.17.0 (批5) tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _signal = StateProvider<int>((_) => 0);
final _other = Provider<int>((_) => 42);

class _Outdated extends Notifier<int> {
  @override
  int build() {
    ref.watch(_signal);
    return 0;
  }

  /// what ConnectionNotifier did before 1.17.0: the core start bumps a watched signal, then reads
  int bumpThenRefRead() {
    ref.read(_signal.notifier).state++;
    return ref.read(_other);
  }

  int bumpThenContainerRead() {
    ref.read(_signal.notifier).state++;
    return ref.container.read(_other);
  }
}

final _outdated = NotifierProvider<_Outdated, int>(_Outdated.new);

void main() {
  group('上次异常 riverpod _didChangeDependency', () {
    test('a ref.read after a watched dependency changed trips the debug assertion (the root cause)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(_outdated);
      expect(
        () => c.read(_outdated.notifier).bumpThenRefRead(),
        throwsA(isA<AssertionError>().having((e) => '$e', 'message', contains('_didChangeDependency'))),
      );
    });

    test('reading through the container does not', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(_outdated);
      expect(c.read(_outdated.notifier).bumpThenContainerRead(), 42);
    });

    test('ConnectionNotifier never calls ref.read outside build', () {
      final s = File('lib/features/connection/notifier/connection_notifier.dart').readAsStringSync();
      final start = s.indexOf('class ConnectionNotifier');
      final end = s.indexOf('final museConnectPreparingProvider');
      final body = s.substring(start, end);
      expect(RegExp(r'\bref\s*\.\s*read\(').hasMatch(body), isFalse);
      expect(body, contains('T _read<T>(ProviderListenable<T> provider) => ref.container.read(provider);'));
    });

    test('e2e fails on a riverpod assertion in the crash log', () {
      final s = File('test_driver/muse_e2e_test.dart').readAsStringSync();
      expect(s, contains("cmd('crashLog')"));
      expect(s, contains("crashLog.contains('package:riverpod/')"));
    });
  });
}
