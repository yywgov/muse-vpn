// 穿云 1.6.0 C4 - 首页「服务状态」: whether 13 common services answer through the connection.
// Probed through the local mixed port (as every proxied app; straight out when it isn't listening),
// 4 at a time, 5 s per service, results cached for 10 minutes. Only runs when the card is shown and
// the user is connected (or taps 刷新). Never changes the connection.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';

// 1.10.4: [timeout] = no answer within [museServiceTimeout] (was folded into failed). Every service
// of a check ends in ok / limited / timeout / failed: the whole check is capped at
// [museServiceTotalCap], and what has not answered by then is a timeout.
// 1.12.0: [originals] = 仅自制剧 (only the service's own shows), [unsupported] = 不支持 (not offered
// in the region the service sees).
enum MuseSvcState { unknown, checking, ok, limited, failed, timeout, originals, unsupported }

/// 1.12.0: a full check of one service (state + the region it sees), used instead of [MuseServiceProbe].
typedef MuseServiceCheck = Future<({MuseSvcState state, String? region})> Function(MuseService service);

class MuseService {
  const MuseService(this.key, this.name, this.url);

  final String key;
  final String name;
  final String url;
}

const museServices = [
  MuseService('google', 'Google', 'https://www.google.com/generate_204'),
  MuseService('github', 'GitHub', 'https://github.com/'),
  MuseService('youtube', 'YouTube', 'https://www.youtube.com/generate_204'),
  MuseService('chatgpt', 'ChatGPT', 'https://chatgpt.com/'),
  MuseService('claude', 'Claude', 'https://claude.ai/'),
  MuseService('gemini', 'Gemini', 'https://gemini.google.com/'),
  MuseService('netflix', 'Netflix', 'https://www.netflix.com/title/81280792'),
  MuseService('disney', 'Disney+', 'https://www.disneyplus.com/'),
  MuseService('prime', 'Prime Video', 'https://www.primevideo.com/'),
  MuseService('spotify', 'Spotify', 'https://open.spotify.com/'),
  MuseService('tiktok', 'TikTok', 'https://www.tiktok.com/'),
  MuseService('discord', 'Discord', 'https://discord.com/'),
  MuseService('bilibili', 'Bilibili', 'https://www.bilibili.com/'),
];

const museServiceConcurrency = 4;
const museServiceTimeout = Duration(seconds: 5);
const museServiceCacheFor = Duration(minutes: 10);

/// 1.10.4: the longest a whole check can take (13 services, 4 at a time, 5 s each is 20 s; the
/// rest is headroom for a slow proxy hand-off). Anything still open then is reported as 超时.
const museServiceTotalCap = Duration(seconds: 30);

/// HTTP status → state: 2xx/3xx answered; 403/451 = the service refuses this region; anything else
/// or no answer = not reachable.
MuseSvcState museServiceVerdict(int? status) {
  if (status == null) return MuseSvcState.failed;
  if (status == 403 || status == 451) return MuseSvcState.limited;
  if (status >= 200 && status < 400) return MuseSvcState.ok;
  if (status == 404 || status == 405 || status == 429) return MuseSvcState.ok; // answered
  return MuseSvcState.failed;
}

typedef MuseServiceProbe = Future<int?> Function(MuseService service);

/// 1.10.4: a probe that gave no answer in time (as opposed to an answer saying no).
class MuseServiceTimeout implements Exception {
  const MuseServiceTimeout();
}

/// Runs [probe] for every service with at most [concurrency] at once and [timeout] each; calls
/// [onResult] as each finishes (with the time it took when it answered). Returns the full result
/// map, which always holds every service: a probe that throws is failed, one that runs past
/// [timeout] is timeout, and when [totalCap] is reached the services not done yet are timeout
/// (1.10.4: before, one probe that never settled kept the card at 检测中 for good).
Future<Map<String, MuseSvcState>> museProbeServices(
  MuseServiceProbe probe, {
  List<MuseService> services = museServices,
  int concurrency = museServiceConcurrency,
  Duration timeout = museServiceTimeout,
  Duration totalCap = museServiceTotalCap,
  void Function(String key, MuseSvcState state, int? ms)? onResult,
  MuseServiceCheck? check,
  void Function(String key, String region)? onRegion,
}) async {
  final out = <String, MuseSvcState>{};
  if (services.isEmpty) return out;
  var next = 0;
  var closed = false;
  void report(String key, MuseSvcState v, int? ms) {
    if (closed || out.containsKey(key)) return;
    out[key] = v;
    onResult?.call(key, v, ms);
  }

  Future<void> worker() async {
    while (!closed && next < services.length) {
      final s = services[next++];
      final watch = Stopwatch()..start();
      MuseSvcState v;
      try {
        if (check != null) {
          final r = await Future.sync(() => check(s)).timeout(timeout);
          v = r.state;
          final region = r.region;
          if (region != null && !closed) onRegion?.call(s.key, region);
        } else {
          final status = await Future<int?>.sync(() => probe(s)).timeout(timeout);
          v = museServiceVerdict(status);
        }
      } on TimeoutException {
        v = MuseSvcState.timeout;
      } on MuseServiceTimeout {
        v = MuseSvcState.timeout;
      } catch (_) {
        v = MuseSvcState.failed;
      }
      report(s.key, v, v == MuseSvcState.ok || v == MuseSvcState.limited || v == MuseSvcState.originals ? watch.elapsedMilliseconds : null);
    }
  }

  final all = Future.wait([for (var i = 0; i < concurrency.clamp(1, services.length); i++) worker()]);
  try {
    await all.timeout(totalCap);
  } on TimeoutException {
    // the cap: whatever has not answered is a timeout
  }
  for (final s in services) {
    report(s.key, MuseSvcState.timeout, null);
  }
  closed = true;
  return out;
}

/// The cache: results and when they were taken.
class MuseServiceCache {
  MuseServiceCache({this.maxAge = museServiceCacheFor});

  final Duration maxAge;
  Map<String, MuseSvcState> results = const {};
  Map<String, int> ms = const {}; // 1.10.4: how long each answer took
  Map<String, String> regions = const {}; // 1.12.0: region each service sees
  DateTime? at;

  bool fresh(DateTime now) => at != null && now.difference(at!) < maxAge && results.isNotEmpty;

  void store(Map<String, MuseSvcState> r, DateTime now, {Map<String, int> ms = const {}, Map<String, String> regions = const {}}) {
    results = Map.unmodifiable(r);
    this.ms = Map.unmodifiable(ms);
    this.regions = Map.unmodifiable(regions);
    at = now;
  }

  void clear() {
    results = const {};
    ms = const {};
    regions = const {};
    at = null;
  }
}

/// The real probe: GET through 127.0.0.1:[port] when it listens. Redirects are not followed.
MuseServiceProbe museHttpServiceProbe(int port) => (service) async {
  final client = HttpClient()
    ..connectionTimeout = museServiceTimeout
    ..idleTimeout = const Duration(seconds: 1)
    ..userAgent = 'Mozilla/5.0';
  try {
    var viaProxy = false;
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 500));
      s.destroy();
      viaProxy = true;
    } catch (_) {}
    if (viaProxy) client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
    // 1.10.4: the request itself is bounded too, so the client is closed (force) as soon as the
    // service is given up on, not whenever the socket finally fails
    final req = await client.getUrl(Uri.parse(service.url)).timeout(museServiceTimeout);
    req.followRedirects = false;
    final res = await req.close().timeout(museServiceTimeout);
    unawaited(res.drain<void>().catchError((_) {}));
    return res.statusCode;
  } on TimeoutException {
    throw const MuseServiceTimeout();
  } on SocketException catch (e) {
    if (e.osError == null && e.message.toLowerCase().contains('timed out')) throw const MuseServiceTimeout();
    return null;
  } on HttpException catch (e) {
    if (e.message.toLowerCase().contains('timed out')) throw const MuseServiceTimeout();
    return null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
};

/// 内网 IP: the local addresses worth showing (no loopback / link-local), IPv4 first.
List<String> museLanAddresses(Iterable<NetworkInterface> interfaces) {
  final v4 = <String>[];
  final v6 = <String>[];
  for (final i in interfaces) {
    for (final a in i.addresses) {
      if (a.isLoopback || a.isLinkLocal) continue;
      final ip = a.address;
      if (a.type == InternetAddressType.IPv4) {
        if (ip.startsWith('169.254.') || ip.startsWith('198.18.') || ip.startsWith('172.19.0.')) continue; // TUN / auto
        if (!v4.contains(ip)) v4.add(ip);
      } else if (a.type == InternetAddressType.IPv6) {
        if (ip.toLowerCase().startsWith('fd') || ip.toLowerCase().startsWith('fc')) continue;
        if (!v6.contains(ip)) v6.add(ip);
      }
    }
  }
  return [...v4, ...v6];
}
