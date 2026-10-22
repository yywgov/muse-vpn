// 穿云 1.2.3 - 出口检测 (1.3.0: shown on the 首页 出口 IP tile and in 诊断): the IP and region traffic leaves from and whether Google,
// ChatGPT and Netflix work from there. Checked through the local mixed port (so it sees exactly
// what proxied apps see), once after connecting, after each node change, and on tap.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseExitResult {
  const MuseExitResult({
    this.info,
    this.infoFailed = false,
    this.google = MuseServiceState.checking,
    this.chatGpt = MuseServiceState.checking,
    this.netflix = MuseServiceState.checking,
  });

  final MuseExitInfo? info;
  final bool infoFailed;
  final MuseServiceState google;
  final MuseServiceState chatGpt;
  final MuseServiceState netflix;

  bool get busy =>
      (info == null && !infoFailed) ||
      google == MuseServiceState.checking ||
      chatGpt == MuseServiceState.checking ||
      netflix == MuseServiceState.checking;

  MuseExitResult copyWith({
    MuseExitInfo? info,
    bool? infoFailed,
    MuseServiceState? google,
    MuseServiceState? chatGpt,
    MuseServiceState? netflix,
  }) => MuseExitResult(
    info: info ?? this.info,
    infoFailed: infoFailed ?? this.infoFailed,
    google: google ?? this.google,
    chatGpt: chatGpt ?? this.chatGpt,
    netflix: netflix ?? this.netflix,
  );
}

class MuseExitNotifier extends StateNotifier<MuseExitResult?> {
  MuseExitNotifier(this._port) : super(null);

  final int Function() _port;
  int _run = 0;

  void clear() {
    _run++;
    state = null;
  }

  Future<void> check() async {
    final run = ++_run;
    state = const MuseExitResult();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 2)
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
    final port = _port();
    // through the local mixed port, as every proxied app; if it is not listening, straight out
    // (on Android the VPN carries the app's own traffic anyway)
    final viaProxy = await _portOpen(port);
    if (viaProxy) client.findProxy = (_) => 'PROXY 127.0.0.1:$port';

    void set(MuseExitResult Function(MuseExitResult s) f) {
      final s = state;
      if (run == _run && mounted && s != null) state = f(s);
    }

    try {
      await Future.wait([
        () async {
          final r = await _get(client, 'https://www.cloudflare.com/cdn-cgi/trace');
          final info = r == null ? null : museParseCfTrace(r.$2);
          set((s) => info == null ? s.copyWith(infoFailed: true) : s.copyWith(info: info));
        }(),
        () async {
          final r = await _get(client, 'https://www.google.com/generate_204', readBody: false);
          set((s) => s.copyWith(google: museGoogleVerdict(r?.$1)));
        }(),
        () async {
          final r = await _get(client, 'https://api.openai.com/compliance/cookie_requirements');
          set((s) => s.copyWith(chatGpt: museChatGptVerdict(r?.$1, r?.$2 ?? '')));
        }(),
        () async {
          final results = await Future.wait([
            _get(client, 'https://www.netflix.com/title/70143836', readBody: false),
            _get(client, 'https://www.netflix.com/title/81280792', readBody: false),
          ]);
          set((s) => s.copyWith(netflix: museNetflixVerdict(results[0]?.$1, results[1]?.$1)));
        }(),
      ]);
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _portOpen(int port) async {
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// (status, body) or null when nothing answered in time.
  static Future<(int, String)?> _get(HttpClient client, String url, {bool readBody = true}) async {
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      req.followRedirects = true;
      req.maxRedirects = 5;
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (!readBody) {
        unawaited(res.drain<void>().catchError((_) {}));
        return (res.statusCode, '');
      }
      final body = await res
          .transform(utf8.decoder)
          .fold<String>('', (a, b) => a.length > 8192 ? a : a + b)
          .timeout(const Duration(seconds: 10));
      return (res.statusCode, body);
    } catch (_) {
      return null;
    }
  }
}

final museExitProvider = StateNotifierProvider<MuseExitNotifier, MuseExitResult?>((ref) {
  final notifier = MuseExitNotifier(() => ref.read(ConfigOptions.mixedPort));
  Timer? pending;
  void schedule(Duration after) {
    pending?.cancel();
    pending = Timer(after, () {
      if (ref.read(serviceRunningProvider) && ref.read(Preferences.museExitCheck)) notifier.check();
    });
  }

  ref.listen<bool>(serviceRunningProvider, (_, running) {
    if (running) {
      // give the first url test / route setup a moment
      schedule(const Duration(seconds: 3));
    } else {
      pending?.cancel();
      notifier.clear();
    }
  }, fireImmediately: true);
  ref.listen<String?>(proxiesOverviewNotifierProvider.select((g) => g.valueOrNull?.selected), (prev, next) {
    if (prev != null && next != null && prev != next) schedule(const Duration(seconds: 2));
  });
  ref.listen(ConfigOptions.museRouteMode, (_, _) => schedule(const Duration(seconds: 3)));
  ref.listen<bool>(Preferences.museExitCheck, (_, on) {
    if (on) {
      schedule(const Duration(milliseconds: 100));
    } else {
      pending?.cancel();
      notifier.clear();
    }
  });
  ref.onDispose(() => pending?.cancel());
  return notifier;
});
