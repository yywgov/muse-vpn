// 穿云 1.2.3 - 出口检测 (1.3.0: shown on the 首页 出口 IP tile and in 诊断): the IP and region traffic leaves from and whether Google,
// ChatGPT and Netflix work from there. Checked through the local mixed port (so it sees exactly
// what proxied apps see). 1.5.3: results are cached per node / subscription / network.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
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
    this.refreshing = false,
  });

  final MuseExitInfo? info;
  final bool infoFailed;
  final MuseServiceState google;
  final MuseServiceState chatGpt;
  final MuseServiceState netflix;

  /// 1.5.3: a check is running while the last result stays on screen
  final bool refreshing;

  bool get busy =>
      refreshing ||
      (info == null && !infoFailed) ||
      google == MuseServiceState.checking ||
      chatGpt == MuseServiceState.checking ||
      netflix == MuseServiceState.checking;

  MuseExitResult copyWith({
    MuseExitInfo? info,
    bool clearInfo = false,
    bool? infoFailed,
    MuseServiceState? google,
    MuseServiceState? chatGpt,
    MuseServiceState? netflix,
    bool? refreshing,
  }) => MuseExitResult(
    info: clearInfo ? null : (info ?? this.info),
    infoFailed: infoFailed ?? this.infoFailed,
    google: google ?? this.google,
    chatGpt: chatGpt ?? this.chatGpt,
    netflix: netflix ?? this.netflix,
    refreshing: refreshing ?? this.refreshing,
  );

  static MuseExitResult fromCached(MuseExitCached c, {bool refreshing = false}) => MuseExitResult(
    info: MuseExitInfo(ip: c.ip, country: c.country),
    google: c.google,
    chatGpt: c.chatGpt,
    netflix: c.netflix,
    refreshing: refreshing,
  );
}

/// 1.5.3: 出口 results are kept per (subscription, node, route mode, network) and shown at once;
/// asked again only when that key changes, the result is older than [museExitMaxAge], the
/// connection was (re)started, or the user taps 刷新. The old value stays while checking.
class MuseExitNotifier extends StateNotifier<MuseExitResult?> {
  MuseExitNotifier(
    this._port, {
    String Function()? keyBase,
    Future<String> Function()? network,
    String Function()? loadCache,
    void Function(String raw)? saveCache,
    DateTime Function()? now,
    Future<MuseExitResult> Function(MuseExitResult start, void Function(MuseExitResult Function(MuseExitResult)) set)? fetch,
  }) : _keyBase = keyBase ?? (() => ''),
       _network = network ?? museLocalNetwork,
       _loadCache = loadCache ?? (() => ''),
       _saveCache = saveCache ?? ((_) {}),
       _now = now ?? DateTime.now,
       _fetchOverride = fetch,
       super(null);

  final int Function() _port;
  final String Function() _keyBase;
  final Future<String> Function() _network;
  final String Function() _loadCache;
  final void Function(String raw) _saveCache;
  final DateTime Function() _now;
  final Future<MuseExitResult> Function(MuseExitResult start, void Function(MuseExitResult Function(MuseExitResult)) set)?
  _fetchOverride;
  int _run = 0;
  Future<void>? _inFlight;
  String? _inFlightKey;

  void clear() {
    _run++;
    _inFlight = null;
    _inFlightKey = null;
    state = null;
  }

  Future<String> _key() async {
    String net;
    try {
      net = await _network().timeout(const Duration(seconds: 2));
    } catch (_) {
      net = '';
    }
    return '${_keyBase()}\u0001$net';
  }

  /// Shows the saved result for the current key at once (no request).
  Future<void> showCached() async {
    final key = await _key();
    final c = MuseExitCache.parse(_loadCache()).of(key);
    if (c != null && mounted && (state == null || !state!.refreshing)) state = MuseExitResult.fromCached(c);
  }

  /// Checks only when nothing fresh is saved for the current key ([force]: always).
  Future<void> ensure({bool force = false}) async {
    final key = await _key();
    if (!mounted) return;
    final c = MuseExitCache.parse(_loadCache()).of(key);
    if (!force && c != null && c.freshAt(_now())) {
      if (_inFlightKey != key) state = MuseExitResult.fromCached(c);
      return;
    }
    if (_inFlight != null && _inFlightKey == key) return _inFlight;
    final f = _check(key, c);
    _inFlight = f;
    _inFlightKey = key;
    try {
      await f;
    } finally {
      if (identical(_inFlight, f)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    }
  }

  /// 刷新: always asks again (the old value stays on screen meanwhile).
  Future<void> check() => ensure(force: true);

  Future<void> _check(String key, MuseExitCached? cached) async {
    final run = ++_run;
    // keep showing what we have (this key's saved result, else the last one on screen)
    final shown = cached != null ? MuseExitResult.fromCached(cached) : state;
    state = shown == null || shown.info == null ? const MuseExitResult(refreshing: true) : shown.copyWith(refreshing: true, infoFailed: false);
    void set(MuseExitResult Function(MuseExitResult s) f) {
      final s = state;
      if (run == _run && mounted && s != null) state = f(s);
    }

    final MuseExitResult got;
    try {
      got = await (_fetchOverride ?? _fetch)(state!, set);
    } catch (_) {
      set((s) => s.copyWith(refreshing: false));
      return;
    }
    if (run != _run || !mounted) return;
    state = got.copyWith(refreshing: false);
    final info = got.info;
    if (info != null && !got.infoFailed) {
      final next = MuseExitCache.parse(_loadCache()).put(
        MuseExitCached(
          key: key,
          ip: info.ip,
          country: info.country,
          at: _now(),
          google: got.google,
          chatGpt: got.chatGpt,
          netflix: got.netflix,
        ),
      );
      _saveCache(next.toRaw());
    }
  }

  Future<MuseExitResult> _fetch(MuseExitResult start, void Function(MuseExitResult Function(MuseExitResult)) set) async {
    var result = start;
    void upd(MuseExitResult Function(MuseExitResult s) f) {
      result = f(result);
      set(f);
    }

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

    try {
      await Future.wait([
        () async {
          final r = await _get(client, 'https://www.cloudflare.com/cdn-cgi/trace');
          final info = r == null ? null : museParseCfTrace(r.$2);
          upd((s) => info == null ? s.copyWith(clearInfo: true, infoFailed: true) : s.copyWith(info: info, infoFailed: false));
        }(),
        () async {
          final r = await _get(client, 'https://www.google.com/generate_204', readBody: false);
          upd((s) => s.copyWith(google: museGoogleVerdict(r?.$1)));
        }(),
        () async {
          final r = await _get(client, 'https://api.openai.com/compliance/cookie_requirements');
          upd((s) => s.copyWith(chatGpt: museChatGptVerdict(r?.$1, r?.$2 ?? '')));
        }(),
        () async {
          final results = await Future.wait([
            _get(client, 'https://www.netflix.com/title/70143836', readBody: false),
            _get(client, 'https://www.netflix.com/title/81280792', readBody: false),
          ]);
          upd((s) => s.copyWith(netflix: museNetflixVerdict(results[0]?.$1, results[1]?.$1)));
        }(),
      ]);
    } finally {
      client.close(force: true);
    }
    return result;
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

/// 1.5.3: the local network for the cache key (addresses of the real interfaces).
Future<String> museLocalNetwork() async {
  final ifs = await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false);
  return museNetworkFingerprint([
    for (final i in ifs)
      for (final a in i.addresses) (i.name, a.address),
  ]);
}

final museExitProvider = StateNotifierProvider<MuseExitNotifier, MuseExitResult?>((ref) {
  final notifier = MuseExitNotifier(
    () => ref.read(ConfigOptions.mixedPort),
    keyBase: () => museExitKey(
      profileId: ref.read(activeProfileProvider).valueOrNull?.id ?? '',
      node: ref.read(proxiesOverviewNotifierProvider).valueOrNull?.selected ?? '',
      routeMode: '${ref.read(ConfigOptions.museRouteMode)}',
      network: '',
    ),
    loadCache: () => ref.read(MusePrefs.exitCache),
    saveCache: (raw) => ref.read(MusePrefs.exitCache.notifier).update(raw),
  );
  Timer? pending;
  bool on() => ref.read(serviceRunningProvider) && ref.read(Preferences.museExitCheck);
  void schedule(Duration after, {bool force = false}) {
    pending?.cancel();
    pending = Timer(after, () {
      if (on()) unawaited(notifier.ensure(force: force).catchError((_) {}));
    });
  }

  ref.listen<bool>(serviceRunningProvider, (_, running) {
    if (running) {
      // the saved result at once; a fresh check once the first url test / routes are set up
      if (ref.read(Preferences.museExitCheck)) unawaited(notifier.showCached().catchError((_) {}));
      schedule(const Duration(seconds: 3), force: true);
    } else {
      pending?.cancel();
      notifier.clear();
    }
  }, fireImmediately: true);
  // node / subscription / route mode changed: the saved result for the new key, else a check
  ref.listen<String?>(proxiesOverviewNotifierProvider.select((g) => g.valueOrNull?.selected), (prev, next) {
    if (prev != null && next != null && prev != next) schedule(const Duration(seconds: 2));
  });
  ref.listen<String?>(activeProfileProvider.select((p) => p.valueOrNull?.id), (prev, next) {
    if (prev != next) schedule(const Duration(seconds: 3));
  });
  ref.listen(ConfigOptions.museRouteMode, (_, _) => schedule(const Duration(seconds: 3)));
  ref.listen<bool>(Preferences.museExitCheck, (_, enabled) {
    if (enabled) {
      schedule(const Duration(milliseconds: 100));
    } else {
      pending?.cancel();
      notifier.clear();
    }
  });
  // back in front (maybe on another network) and every 10 min while shown: only when stale
  AppLifecycleListener? life;
  var resumed = true;
  try {
    life = AppLifecycleListener(
      onResume: () {
        resumed = true;
        schedule(const Duration(milliseconds: 500));
      },
      onPause: () => resumed = false,
    );
  } catch (_) {}
  final periodic = Timer.periodic(museExitMaxAge, (_) {
    if (resumed) schedule(Duration.zero);
  });
  ref.onDispose(() {
    pending?.cancel();
    periodic.cancel();
    life?.dispose();
  });
  return notifier;
});
