// 穿云 1.6.0 C4 - 首页「服务状态」: whether 13 common services answer through the connection.
// Probed through the local mixed port (as every proxied app; straight out when it isn't listening),
// 4 at a time, 5 s per service, results cached for 10 minutes. Only runs when the card is shown and
// the user is connected (or taps 刷新). Never changes the connection.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';

enum MuseSvcState { unknown, checking, ok, limited, failed }

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

/// Runs [probe] for every service with at most [concurrency] at once and [timeout] each; calls
/// [onResult] as each finishes. Returns the full result map.
Future<Map<String, MuseSvcState>> museProbeServices(
  MuseServiceProbe probe, {
  List<MuseService> services = museServices,
  int concurrency = museServiceConcurrency,
  Duration timeout = museServiceTimeout,
  void Function(String key, MuseSvcState state)? onResult,
}) async {
  final out = <String, MuseSvcState>{};
  var next = 0;
  Future<void> worker() async {
    while (next < services.length) {
      final s = services[next++];
      int? status;
      try {
        status = await probe(s).timeout(timeout);
      } catch (_) {
        status = null;
      }
      final v = museServiceVerdict(status);
      out[s.key] = v;
      onResult?.call(s.key, v);
    }
  }

  await Future.wait([for (var i = 0; i < concurrency.clamp(1, services.length); i++) worker()]);
  return out;
}

/// The cache: results and when they were taken.
class MuseServiceCache {
  MuseServiceCache({this.maxAge = museServiceCacheFor});

  final Duration maxAge;
  Map<String, MuseSvcState> results = const {};
  DateTime? at;

  bool fresh(DateTime now) => at != null && now.difference(at!) < maxAge && results.isNotEmpty;

  void store(Map<String, MuseSvcState> r, DateTime now) {
    results = Map.unmodifiable(r);
    at = now;
  }

  void clear() {
    results = const {};
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
    final req = await client.getUrl(Uri.parse(service.url));
    req.followRedirects = false;
    final res = await req.close();
    unawaited(res.drain<void>().catchError((_) {}));
    return res.statusCode;
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
