// 穿云 1.6.0 C3 - providers over the local control API. Streams only run while a page / card
// watches them and the core is running; they stop 5 s after the last listener leaves.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const museWebSecretKey = 'muse_web_secret';

/// The per-install key of the local control API: made once, kept locally, never synced.
final museWebSecretProvider = Provider<String>((ref) {
  final sp = ref.watch(sharedPreferencesProvider).requireValue;
  final saved = sp.getString(museWebSecretKey) ?? '';
  if (saved.length >= 16) return saved;
  final fresh = museNewWebSecret();
  unawaited(sp.setString(museWebSecretKey, fresh));
  return fresh;
});

/// The client for the running core (null while disconnected).
final museLocalApiProvider = Provider.autoDispose<MuseLocalApi?>((ref) {
  if (!ref.watch(museRunningProvider)) return null;
  final api = MuseLocalApi(port: ref.watch(ConfigOptions.clashApiPort), secret: ref.watch(museWebSecretProvider));
  ref.onDispose(api.close);
  return api;
});

/// Keeps an autoDispose provider for [grace] after its last listener left (switching tabs or a
/// quick back-and-forth does not reconnect the stream).
void museKeepFor(Ref ref, Duration grace) {
  final link = ref.keepAlive();
  Timer? t;
  ref.onCancel(() => t = Timer(grace, link.close));
  ref.onResume(() => t?.cancel());
  ref.onDispose(() => t?.cancel());
}

const museStreamGrace = Duration(seconds: 5);

/// Ended connections (请求), shared by 连接 and 首页.
final museRequestHistoryProvider = Provider<MuseRequestHistory>((ref) => MuseRequestHistory());

/// What 连接 shows: the live list, or why it is not available.
class MuseConnState {
  const MuseConnState({this.connections = const [], this.frame = MuseConnFrame.empty, this.error, this.loading = false});

  final List<MuseConn> connections;
  final MuseConnFrame frame;

  /// 「暂不可用」 reason (never changes the connection itself)
  final String? error;
  final bool loading;
}

/// Live connections, one frame a second.
final museConnectionsProvider = StreamProvider.autoDispose<MuseConnState>((ref) async* {
  museKeepFor(ref, museStreamGrace);
  final api = ref.watch(museLocalApiProvider);
  if (api == null) {
    yield const MuseConnState(error: '未连接');
    return;
  }
  final tracker = MuseConnTracker(history: ref.read(museRequestHistoryProvider));
  yield const MuseConnState(loading: true);
  try {
    await for (final raw in api.stream('/connections', query: const {'interval': '1000'})) {
      final frame = await museParseConnFrameAsync(raw);
      yield MuseConnState(connections: tracker.apply(frame, DateTime.now()), frame: frame);
    }
    yield const MuseConnState(error: '连接已断开');
  } on MuseLocalApiError catch (e) {
    yield MuseConnState(error: e.message);
  } catch (_) {
    yield const MuseConnState(error: '暂不可用');
  }
});

/// Live log lines (only while 日志记录 is on).
final museLogBufferProvider = Provider<MuseLogBuffer>((ref) => MuseLogBuffer());

final museLogLevelProvider = StateProvider<String>((ref) => 'info');

final museLogsProvider = StreamProvider.autoDispose<List<MuseLogLine>>((ref) async* {
  museKeepFor(ref, museStreamGrace);
  final buffer = ref.read(museLogBufferProvider);
  if (!ref.watch(MusePrefs.logCapture)) {
    yield buffer.lines;
    return;
  }
  final api = ref.watch(museLocalApiProvider);
  yield buffer.lines;
  if (api == null) return;
  final level = ref.watch(museLogLevelProvider);
  try {
    await for (final raw in api.stream('/logs', query: {'level': level == 'warning' ? 'warn' : level})) {
      final l = MuseLogLine.fromJson(raw, DateTime.now());
      if (l == null) continue;
      buffer.add(l);
      yield buffer.lines;
    }
  } catch (_) {
    yield buffer.lines;
  }
});

/// 屏蔽此域名: hosts sent to the core as one 拦截 rule (hot-reloaded while connected).
List<String> museParseBlockedHosts(String raw) {
  try {
    return [for (final h in jsonDecode(raw) as List) '$h'];
  } catch (_) {
    return const [];
  }
}

String museBlockedHostsToRaw(List<String> hosts) => jsonEncode(hosts);

/// Adds [host] (lower-case, de-duplicated); returns the new list.
List<String> museAddBlockedHost(List<String> hosts, String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty || hosts.contains(h)) return hosts;
  return [...hosts, h];
}

/// 1.6.0 C3 (G72): after the user switches node, connections still on the old node are closed
/// (apps reconnect through the new one). Best effort: any failure is ignored.
Future<void> museCloseConnectionsAfterSwitch(T Function<T>(ProviderListenable<T>) read) async {
  try {
    if (!read(MusePrefs.autoCloseConnections) || !read(museRunningProvider)) return;
    final api = MuseLocalApi(port: read(ConfigOptions.clashApiPort), secret: read(museWebSecretProvider));
    try {
      await api.closeAll();
    } finally {
      api.close();
    }
  } catch (_) {
    // the old connections just end on their own
  }
}
