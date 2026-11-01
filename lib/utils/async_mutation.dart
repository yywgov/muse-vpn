import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// State of a one-off async action started from a widget (select a profile, …).
///
/// 穿云 1.9.0: plain sealed classes instead of generated ones (no code generation needed), with
/// tests in test/utils/async_mutation_test.dart.
sealed class AsyncMutation {
  const AsyncMutation();

  const factory AsyncMutation.idle() = Idle;
  const factory AsyncMutation.inProgress() = InProgress;
  const factory AsyncMutation.fail(Object error, StackTrace stackTrace) = Fail;
  const factory AsyncMutation.success() = Success;

  bool get isInProgress => this is InProgress;
}

final class Idle extends AsyncMutation {
  const Idle();

  @override
  bool operator ==(Object other) => other is Idle;

  @override
  int get hashCode => (Idle).hashCode;
}

final class InProgress extends AsyncMutation {
  const InProgress();

  @override
  bool operator ==(Object other) => other is InProgress;

  @override
  int get hashCode => (InProgress).hashCode;
}

final class Fail extends AsyncMutation {
  const Fail(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  bool operator ==(Object other) => other is Fail && other.error == error && other.stackTrace == stackTrace;

  @override
  int get hashCode => Object.hash(error, stackTrace);
}

final class Success extends AsyncMutation {
  const Success();

  @override
  bool operator ==(Object other) => other is Success;

  @override
  int get hashCode => (Success).hashCode;
}

/// Maps a future's snapshot to [AsyncMutation].
AsyncMutation asyncMutationOf(AsyncSnapshot<Object?> snapshot) => switch (snapshot.connectionState) {
  ConnectionState.none => const Idle(),
  ConnectionState.waiting => const InProgress(),
  _ => snapshot.hasError ? Fail(snapshot.error!, snapshot.stackTrace ?? StackTrace.empty) : const Success(),
};

/// Runs one async action at a time from a hook widget and reports its state. The failure /
/// success callback runs once per result, after the frame (so it may show a snackbar).
({AsyncMutation state, ValueChanged<Future<T>> setFuture, ValueChanged<void Function(Object error)> setOnFailure})
useMutation<T>({void Function(Object error)? initialOnFailure, void Function()? initialOnSuccess}) {
  final mutationUpdate = useState<Future<T>?>(null);
  final mutationState = useFuture(mutationUpdate.value);
  final failureCallBack = useValueNotifier<void Function(Object error)?>(initialOnFailure);
  final successCallBack = useValueNotifier<void Function()?>(initialOnSuccess);

  final mapped = useMemoized(() => asyncMutationOf(mutationState), [mutationState]);

  // one-off callback per result
  useMemoized(() {
    if (mapped case Fail(:final error)) {
      // if the callback builds a widget (a snackbar for example) this avoids build-phase exceptions
      WidgetsBinding.instance.addPostFrameCallback((_) => failureCallBack.value?.call(error));
    }
    if (mapped case Success()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => successCallBack.value?.call());
    }
  }, [mapped, failureCallBack.value, successCallBack.value]);

  return (
    state: mapped,
    setFuture: (future) => mutationUpdate.value = future,
    setOnFailure: (onFailure) => failureCallBack.value = onFailure,
  );
}
