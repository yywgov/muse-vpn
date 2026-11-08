// 穿云 1.6.0 C3 - providers over the local control API. Streams only run while a page / card
// watches them and the core is running; they stop 5 s after the last listener leaves.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/app_traffic_recorder.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/dns_queries.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/logic/compat_profile.dart' show museEffectiveCoreKind;
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/resources.dart' show museEngineVersion;
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/platform_utils.dart';
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

/// 1.6.0 C11: [source] until the provider is disposed. An `async*` provider only notices it was
/// cancelled at its next `yield`, so a quiet stream (no log lines) would keep its WebSocket open
/// after the page left; this ends the subscription the moment the provider goes away.
Stream<T> museUntilDisposed<T>(Ref ref, Stream<T> source) {
  final out = StreamController<T>(sync: true);
  StreamSubscription<T>? sub;
  out.onListen = () {
    sub = source.listen(out.add, onError: out.addError, onDone: out.close);
  };
  ref.onDispose(() {
    unawaited(sub?.cancel());
    sub = null;
    unawaited(out.close());
  });
  return out.stream;
}

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
  // 1.16.0 B7: 按应用流量 from the frames this page receives anyway (written every 30 s and on leaving)
  final prefs = ref.read(MusePrefs.appTraffic.notifier);
  var lastRaw = ref.read(MusePrefs.appTraffic);
  String read() {
    try {
      return lastRaw = ref.read(MusePrefs.appTraffic);
    } catch (_) {
      return lastRaw; // on dispose
    }
  }

  final feed = MuseAppTrafficFeed(ref.read(museAppSamplerProvider), read, (v) {
    lastRaw = v;
    return prefs.update(v);
  });
  ref.onDispose(feed.flush);
  yield const MuseConnState(loading: true);
  try {
    await for (final raw in museUntilDisposed(ref, api.stream('/connections', query: const {'interval': '1000'}))) {
      final frame = await museParseConnFrameAsync(raw);
      feed.frame(frame.connections);
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
    await for (final raw in museUntilDisposed(ref, api.stream('/logs', query: {'level': level == 'warning' ? 'warn' : level}))) {
      final l = MuseLogLine.fromJson(raw, DateTime.now());
      if (l == null) continue;
      buffer.add(l);
      yield buffer.lines;
    }
  } catch (_) {
    yield buffer.lines;
  }
});

/// 1.8.0 DNS 查询 ---------------------------------------------------------------------------

/// The queries seen so far (kept while the app runs; the core keeps its own copy).
final museDnsBufferProvider = Provider<MuseDnsBuffer>((ref) => MuseDnsBuffer());

/// The core the connection runs on (Windows: the one the app started with; Android: the saved
/// choice, used at every connect).
final museRunningCoreKindProvider = Provider<MuseCoreKind>(
  (ref) => museEffectiveCoreKind(desktop: PlatformUtils.isDesktop, savedKey: ref.watch(MusePrefs.coreKind)),
);

/// What the DNS tab shows.
class MuseDnsState {
  const MuseDnsState({this.queries = const [], this.error, this.loading = false, this.unsupported = false});

  final List<MuseDnsQuery> queries;
  final String? error;
  final bool loading;

  /// 兼容内核 has no query records
  final bool unsupported;
}

/// Live DNS queries. Only while the DNS tab is on screen: no grace period, the WebSocket closes
/// the moment the tab goes away (and with it the core stops recording).
final museDnsQueriesProvider = StreamProvider.autoDispose<MuseDnsState>((ref) async* {
  final buffer = ref.read(museDnsBufferProvider);
  if (ref.watch(museRunningCoreKindProvider) == MuseCoreKind.compat) {
    yield const MuseDnsState(unsupported: true);
    return;
  }
  final api = ref.watch(museLocalApiProvider);
  if (api == null) {
    yield MuseDnsState(queries: buffer.items, error: '未连接');
    return;
  }
  yield MuseDnsState(queries: buffer.items, loading: true);
  var first = true;
  try {
    await for (final raw in museUntilDisposed(ref, api.stream('/dns/queries'))) {
      final batch = museParseDnsFrame(raw);
      if (first) {
        buffer.reset(batch);
        first = false;
      } else {
        buffer.addAll(batch);
      }
      yield MuseDnsState(queries: buffer.items);
    }
    yield MuseDnsState(queries: buffer.items, error: '连接已断开');
  } on MuseLocalApiError catch (e) {
    yield MuseDnsState(queries: buffer.items, error: e.message);
  } catch (_) {
    yield MuseDnsState(queries: buffer.items, error: '暂不可用');
  }
});

/// 清空: the app's list and the core's buffer.
Future<void> museClearDnsQueries(WidgetRef ref) async {
  ref.read(museDnsBufferProvider).clear();
  final api = ref.read(museLocalApiProvider);
  if (api != null) {
    try {
      await api.clearDnsQueries();
    } catch (_) {
      // the core's copy just stays until it fills up
    }
  }
  // show the empty list now (the reopened stream starts from the core's emptied buffer)
  ref.invalidate(museDnsQueriesProvider);
}

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

/// 1.6.0 C10 关于 › 内核版本: the running engine's version number (null while disconnected or when
/// the local interface does not answer).
final museEngineVersionProvider = FutureProvider.autoDispose<String?>((ref) async {
  final api = ref.watch(museLocalApiProvider);
  if (api == null) return null;
  try {
    final j = await api.getJson('/version');
    return museEngineVersion('${j['version'] ?? ''}');
  } catch (_) {
    return null;
  }
});
