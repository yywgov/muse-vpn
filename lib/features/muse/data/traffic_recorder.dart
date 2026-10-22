// 穿云 1.4.0 - records traffic per day for 统计 (from the core's session totals; saved at most
// once a minute and when the connection ends).
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final museTrafficRecorderProvider = Provider<void>((ref) {
  final counter = MuseTrafficCounter();
  var pendingUp = 0;
  var pendingDown = 0;
  var lastSave = DateTime.now();

  void flush() {
    if (pendingUp <= 0 && pendingDown <= 0) return;
    try {
      final log = MuseTrafficLog.parse(ref.read(MusePrefs.trafficLog)).add(DateTime.now(), pendingUp, pendingDown);
      ref.read(MusePrefs.trafficLog.notifier).update(log.toRaw());
    } catch (_) {}
    pendingUp = 0;
    pendingDown = 0;
    lastSave = DateTime.now();
  }

  final timer = Timer.periodic(const Duration(minutes: 1), (_) => flush());
  ref.onDispose(() {
    timer.cancel();
    flush();
  });

  ref.listen<bool>(museRunningProvider, (_, running) {
    if (!running) {
      flush();
      counter.reset();
    }
  });
  ref.listen(museStatsProvider, (_, s) {
    if (!ref.read(museRunningProvider)) return;
    final (du, dd) = counter.delta(s.uplinkTotal.toInt(), s.downlinkTotal.toInt());
    pendingUp += du;
    pendingDown += dd;
    if (DateTime.now().difference(lastSave) > const Duration(minutes: 1)) flush();
  });
});
