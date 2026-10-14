// 穿云 1.2 - 内核看门狗: while connected, ping the core over gRPC; when it stops answering
// (crash or hang) restart the connection. Shown as an icon on 首页 while it recovers.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hiddify/utils/platform_utils.dart';

import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// true while the watchdog is restarting a core that stopped answering
final museWatchdogRecoveringProvider = StateProvider<bool>((ref) => false);

const museWatchdogInterval = Duration(seconds: 15);

final museCoreWatchdogProvider = Provider<void>((ref) {
  if (!ref.watch(serviceRunningProvider)) return;
  final counter = MuseWatchdogCounter();
  var busy = false;
  final timer = Timer.periodic(museWatchdogInterval, (_) async {
    if (busy) return;
    // Android: only while the app is in front. In the background the Dart side may be throttled,
    // and the VPN service's own CoreWatch already restarts a core that stops by itself.
    if (PlatformUtils.isAndroid && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      counter.record(ok: true);
      return;
    }
    busy = true;
    try {
      final ok = await ref.read(hiddifyCoreServiceProvider).ping();
      if (ok && ref.read(museWatchdogRecoveringProvider)) {
        ref.read(museWatchdogRecoveringProvider.notifier).state = false;
      }
      if (counter.record(ok: ok)) {
        ref.read(museWatchdogRecoveringProvider.notifier).state = true;
        ChuanyunPlatform.recordDisconnect("内核无响应，自动重启");
        await ref.read(connectionNotifierProvider.notifier).restartAfterWatchdog();
      }
    } catch (_) {
      // next tick
    } finally {
      busy = false;
    }
  });
  ref.onDispose(timer.cancel);
});
