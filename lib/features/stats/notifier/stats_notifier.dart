import 'dart:async';

import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/stats_pause.dart';
import 'package:hiddify/features/stats/data/stats_data_providers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'stats_notifier.g.dart';

/// 穿云 1.2: speeds keep updating for the whole session. The core's stats stream used to end
/// (or fail once, right after connecting) and this provider then showed ↑0B/s ↓0B/s until the
/// next disconnect. Now a stream that ends or fails is opened again after a short pause, for as
/// long as the tunnel is up.
@riverpod
class StatsNotifier extends _$StatsNotifier with AppLogger {
  @override
  Stream<SystemInfo> build() {
    ref.disposeDelay(const Duration(seconds: 10));
    final serviceRunning = ref.watch(serviceRunningProvider);
    if (!serviceRunning) return Stream.value(SystemInfo.create());
    // 1.20.1 后台省电: an Android app in the background closes the per-second stream and keeps the last
    // reading (nothing is emitted until it comes back; the totals then catch up)
    if (ref.watch(museStatsPausedProvider)) {
      loggy.debug("app in the background: stats stream closed");
      final held = StreamController<SystemInfo>();
      ref.onDispose(held.close);
      return held.stream;
    }
    final repository = ref.watch(statsRepositoryProvider);
    var disposed = false;
    ref.onDispose(() => disposed = true);
    return museResilientStats(
      () => repository.watchStats().map((event) => event.getOrElse((_) => SystemInfo.create())),
      isActive: () => !disposed,
      onRetry: (attempt) => loggy.debug("stats stream ended, reopening (#$attempt)"),
    );
  }
}

/// Re-subscribes to [open] whenever its stream ends or fails, while [isActive].
/// A failed sample reads as zero speed rather than an error.
Stream<SystemInfo> museResilientStats(
  Stream<SystemInfo> Function() open, {
  required bool Function() isActive,
  Duration retryDelay = const Duration(seconds: 1),
  void Function(int attempt)? onRetry,
}) async* {
  var attempt = 0;
  while (isActive()) {
    try {
      await for (final info in open()) {
        if (!isActive()) return;
        yield info;
      }
    } catch (_) {
      // reopen below
    }
    if (!isActive()) return;
    attempt++;
    onRetry?.call(attempt);
    yield SystemInfo.create();
    await Future<void>.delayed(retryDelay);
  }
}
