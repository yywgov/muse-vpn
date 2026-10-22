// 穿云 1.2.8 - 连上后探测一次 https://www.google.com/generate_204 (through the local mixed port, as
// every proxied app; straight out when it isn't listening, e.g. Android VPN mode). When it fails,
// 1.3.0: shown on the 首页 出口 IP tile (「无法访问外网」) and in 诊断; checked again after a node change.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';

import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum MuseReach { unknown, checking, ok, failed }

const museReachUrl = 'https://www.google.com/generate_204';

/// 204 (or a 200 from a captive / rewriting middlebox that still answered) counts as reachable.
MuseReach museReachVerdict(int? status) =>
    status != null && (status == 204 || status == 200) ? MuseReach.ok : MuseReach.failed;

class MuseReachNotifier extends StateNotifier<MuseReach> {
  MuseReachNotifier(this._port) : super(MuseReach.unknown);

  final int Function() _port;
  int _run = 0;

  void clear() {
    _run++;
    state = MuseReach.unknown;
  }

  Future<void> check() async {
    final run = ++_run;
    state = MuseReach.checking;
    var result = MuseReach.failed;
    // two tries: the first request after connecting may still race the route setup
    for (var i = 0; i < 2 && result != MuseReach.ok; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(seconds: 2));
      result = museReachVerdict(await _probe(_port()));
      if (run != _run) return;
    }
    if (mounted && run == _run) state = result;
  }

  static Future<int?> _probe(int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 2);
    try {
      var viaProxy = false;
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
        s.destroy();
        viaProxy = true;
      } catch (_) {}
      if (viaProxy) client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
      final req = await client.getUrl(Uri.parse(museReachUrl)).timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      unawaited(res.drain<void>().catchError((_) {}));
      return res.statusCode;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

final museReachProvider = StateNotifierProvider<MuseReachNotifier, MuseReach>((ref) {
  final notifier = MuseReachNotifier(() => ref.read(ConfigOptions.mixedPort));
  Timer? pending;
  void schedule(Duration after) {
    pending?.cancel();
    pending = Timer(after, () {
      if (ref.read(serviceRunningProvider)) notifier.check();
    });
  }

  ref.listen<bool>(serviceRunningProvider, (_, running) {
    if (running) {
      schedule(const Duration(seconds: 3));
    } else {
      pending?.cancel();
      notifier.clear();
    }
  }, fireImmediately: true);
  ref.listen<String?>(proxiesOverviewNotifierProvider.select((g) => g.valueOrNull?.selected), (prev, next) {
    if (prev != null && next != null && prev != next) schedule(const Duration(seconds: 2));
  });
  ref.onDispose(() => pending?.cancel());
  return notifier;
});
