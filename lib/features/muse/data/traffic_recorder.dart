// 穿云 1.4.0 - records traffic per day for 统计 (from the core's session totals; saved at most
// once a minute and when the connection ends).
// 1.20.1 后台省电: on Android the stats stream is closed while the app is in the background; the first
// reading back counts the background traffic (totals difference), and a connection that ends in the
// background is topped up with one final reading of the totals (no timer, no wake-up).
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/stats_pause.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final museTrafficRecorderProvider = Provider<void>((ref) {
  final counter = MuseTrafficCounter();
  // 1.20.1: the same readings, reset only when a new connection starts (the disconnect may reset
  // [counter] before the final reading answers)
  final seen = MuseTrafficCounter();
  var samples = 0;
  var pendingUp = 0;
  var pendingDown = 0;
  var lastSave = DateTime.now();
  var disposed = false;

  // 1.20.1: the preference's value changes only once its write is done, so a second save close
  // behind the first (the disconnect, then the final reading) builds on the log still being written
  String? inFlight;
  String? inFlightBase;

  void flush() {
    if (pendingUp <= 0 && pendingDown <= 0) return;
    try {
      final current = ref.read(MusePrefs.trafficLog);
      final base = inFlight != null && current == inFlightBase ? inFlight! : current;
      final raw = MuseTrafficLog.parse(base).add(DateTime.now(), pendingUp, pendingDown).toRaw();
      inFlightBase = current;
      inFlight = raw;
      ref.read(MusePrefs.trafficLog.notifier).update(raw);
    } catch (_) {}
    pendingUp = 0;
    pendingDown = 0;
    lastSave = DateTime.now();
  }

  final timer = Timer.periodic(const Duration(minutes: 1), (_) => flush());
  ref.onDispose(() {
    disposed = true;
    timer.cancel();
    flush();
  });

  ref.listen<bool>(museRunningProvider, (prev, running) {
    if (!running) {
      flush();
      counter.reset();
    } else if (prev == false) {
      // a new session: its totals start at 0
      seen
        ..reset()
        ..delta(0, 0);
    }
  });
  ref.listen(museStatsProvider, (_, s) {
    if (!ref.read(museRunningProvider)) return;
    final up = s.uplinkTotal.toInt();
    final down = s.downlinkTotal.toInt();
    if (counter.isGap(up, down)) return;
    samples++;
    seen.delta(up, down);
    final (du, dd) = counter.delta(up, down);
    pendingUp += du;
    pendingDown += dd;
    if (DateTime.now().difference(lastSave) > const Duration(minutes: 1)) flush();
  });

  // 1.20.1: the connection ended while the stats stream was closed (app in the background) — read the
  // totals once more so the last stretch is counted. Skipped when a live reading came in meanwhile.
  ref.listen(museConnectionProvider, (prev, next) {
    if (prev?.valueOrNull is! Connected || next.valueOrNull is Connected) return;
    if (!ref.read(museStatsPausedProvider)) return;
    final base = seen.copy();
    if (!base.primed) return;
    final at = samples;
    unawaited(() async {
      final info = await ref.read(museStatsReadOnceProvider)();
      if (disposed || info == null || samples != at) return;
      final up = info.uplinkTotal.toInt();
      final down = info.downlinkTotal.toInt();
      if (base.isGap(up, down)) return;
      final (du, dd) = museFinalStatsDelta(base, up, down);
      pendingUp += du;
      pendingDown += dd;
      flush();
    }());
  });
});
