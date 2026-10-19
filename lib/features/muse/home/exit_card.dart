// 穿云 1.2.3 - 首页「出口」card: the IP and region traffic leaves from and whether Google,
// ChatGPT and Netflix work from there. Checked through the local mixed port (so it sees exactly
// what proxied apps see), once after connecting, after each node change, and on tap.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
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

/// The card itself; nothing while disconnected or with 出口检测 switched off.
class MuseExitCard extends ConsumerWidget {
  const MuseExitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(Preferences.museExitCheck);
    final running = ref.watch(serviceRunningProvider);
    final result = ref.watch(museExitProvider);
    if (!enabled || !running) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final secondary = MuseColors.secondaryText(context);
    final r = result ?? const MuseExitResult();
    final info = r.info;

    final String place;
    final String? flag;
    if (info != null) {
      place = '${museCountryLabel(info.country)} · ${museMaskIp(info.ip)}';
      flag = museCountryFlag(info.country);
    } else if (r.infoFailed) {
      place = '获取出口失败';
      flag = null;
    } else {
      place = '正在检测出口…';
      flag = null;
    }

    return Padding(
      key: const ValueKey('home_exit_card'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: MuseColors.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: r.busy && result != null ? null : () => ref.read(museExitProvider.notifier).check(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MuseColors.brand.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: flag != null
                          ? Text(flag, style: const TextStyle(fontSize: 20, height: 1.1))
                          : const Icon(Icons.travel_explore_rounded, size: 18, color: MuseColors.brandLight),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('出口', style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
                          Text(
                            place,
                            key: const ValueKey('home_exit_place'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: r.busy
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Tooltip(
                              message: '重新检测',
                              child: Icon(Icons.refresh_rounded, size: 20, color: secondary),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _ServiceChip(name: 'Google', state: r.google)),
                    const SizedBox(width: 6),
                    Expanded(child: _ServiceChip(name: 'ChatGPT', state: r.chatGpt)),
                    const SizedBox(width: 6),
                    Expanded(child: _ServiceChip(name: 'Netflix', state: r.netflix, partial: '仅自制剧')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.name, required this.state, this.partial = '部分'});

  final String name;
  final MuseServiceState state;
  final String partial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = MuseColors.secondaryText(context);
    final Color dot = switch (state) {
      MuseServiceState.ok => const Color(0xFF34C759),
      MuseServiceState.partial => const Color(0xFFFF9F0A),
      MuseServiceState.blocked => theme.colorScheme.error,
      MuseServiceState.failed => theme.colorScheme.error.withValues(alpha: 0.7),
      MuseServiceState.checking => secondary.withValues(alpha: 0.5),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: MuseColors.innerSurface(context), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium),
                Text(
                  museServiceStateLabel(state, partial: partial),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
