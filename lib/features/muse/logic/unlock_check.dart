// 穿云 1.12.0 - 首页「服务状态」解锁检测: besides "does it answer", the streaming / AI services tell
// which region they see (地区), whether only the service's own shows are offered (仅自制剧), or
// that the service is not offered there (不支持). Runs only when the user taps the card or 刷新;
// no timer, no polling. Each request goes through the local mixed port like every proxied app.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/muse/logic/service_probe.dart';

/// One HTTP answer: status, the redirect target (redirects are not followed) and the start of the body.
class MuseHttpAnswer {
  const MuseHttpAnswer(this.status, {this.location = '', this.body = ''});

  final int status;
  final String location;
  final String body;
}

typedef MuseHttpFetch = Future<MuseHttpAnswer?> Function(String url);

/// What a service says about this exit.
class MuseUnlock {
  const MuseUnlock(this.state, {this.region});

  final MuseSvcState state;

  /// two-letter region code the service sees (upper case), when it says
  final String? region;
}

/// Regions where the AI services below are not offered (their published lists, kept short on purpose).
const museAiBlockedRegions = {'CN', 'HK', 'MO', 'RU', 'BY', 'IR', 'KP', 'SY', 'CU', 'VE'};

/// Services with a region-aware check; the rest only check whether they answer.
const museUnlockKeys = {'netflix', 'youtube', 'disney', 'chatgpt', 'claude', 'tiktok', 'prime'};

const museNetflixLicensed = 'https://www.netflix.com/title/81280792';
const museNetflixLicensed2 = 'https://www.netflix.com/title/70143836';

String? _match(RegExp re, String s) {
  final m = re.firstMatch(s);
  final v = m?.group(1);
  return v == null || v.length != 2 ? null : v.toUpperCase();
}

/// Cloudflare trace (`loc=XX`).
String? museTraceRegion(String body) => _match(RegExp(r'^loc=([A-Za-z]{2})\s*$', multiLine: true), body);

/// Netflix: region in the page, or in the redirect (/hk/title/…, /hk-en/title/…).
String? museNetflixRegion(MuseHttpAnswer a) =>
    _match(RegExp(r'"requestCountry":\{"id":"([A-Z]{2})"'), a.body) ??
    _match(RegExp(r'netflix\.com/([a-z]{2})(?:-[a-z]{2})?/title'), a.location) ??
    _match(RegExp(r'^/([a-z]{2})(?:-[a-z]{2})?/title'), a.location);

/// Netflix verdict from the licensed title (and a second one when the first is missing).
MuseUnlock museNetflixVerdict(MuseHttpAnswer? first, MuseHttpAnswer? second) {
  bool shown(MuseHttpAnswer? a) => a != null && a.status >= 200 && a.status < 400;
  if (first == null && second == null) return const MuseUnlock(MuseSvcState.failed);
  if (first?.status == 403) return const MuseUnlock(MuseSvcState.unsupported);
  if (shown(first)) return MuseUnlock(MuseSvcState.ok, region: museNetflixRegion(first!));
  if (shown(second)) return MuseUnlock(MuseSvcState.ok, region: museNetflixRegion(second!));
  if (first?.status == 404 && (second == null || second.status == 404)) {
    return const MuseUnlock(MuseSvcState.originals);
  }
  return MuseUnlock(museServiceVerdict(first?.status ?? second?.status));
}

/// YouTube Premium page.
MuseUnlock museYoutubeVerdict(MuseHttpAnswer? a) {
  if (a == null) return const MuseUnlock(MuseSvcState.failed);
  if (a.body.contains('Premium is not available in your country')) return const MuseUnlock(MuseSvcState.unsupported);
  final base = museServiceVerdict(a.status);
  if (base != MuseSvcState.ok) return MuseUnlock(base);
  return MuseUnlock(
    MuseSvcState.ok,
    region: _match(RegExp(r'"GL":"([A-Z]{2})"'), a.body) ?? _match(RegExp(r'"countryCode":"([A-Z]{2})"'), a.body),
  );
}

/// Disney+: redirected to an "unavailable" page where it is not offered.
MuseUnlock museDisneyVerdict(MuseHttpAnswer? a) {
  if (a == null) return const MuseUnlock(MuseSvcState.failed);
  final loc = a.location.toLowerCase();
  if (loc.contains('unavailable') || loc.contains('/unsupported')) return const MuseUnlock(MuseSvcState.unsupported);
  return MuseUnlock(museServiceVerdict(a.status), region: _match(RegExp(r'"countryCode":"([A-Z]{2})"'), a.body));
}

/// ChatGPT / Claude: the region from the trace decides; without a trace, whether the site answers.
MuseUnlock museAiVerdict(MuseHttpAnswer? trace, MuseHttpAnswer? site) {
  final region = trace == null || trace.status != 200 ? null : museTraceRegion(trace.body);
  if (region != null) {
    if (museAiBlockedRegions.contains(region)) return MuseUnlock(MuseSvcState.unsupported, region: region);
    if (site != null && museServiceVerdict(site.status) == MuseSvcState.limited) {
      return MuseUnlock(MuseSvcState.limited, region: region);
    }
    return MuseUnlock(MuseSvcState.ok, region: region);
  }
  if (site == null) return const MuseUnlock(MuseSvcState.failed);
  if (site.location.contains('unavailable') || site.location.contains('unsupported')) {
    return const MuseUnlock(MuseSvcState.unsupported);
  }
  return MuseUnlock(museServiceVerdict(site.status));
}

/// A page whose answer carries its region (TikTok `"region":"XX"`, Prime Video `"currentTerritory":"XX"`).
MuseUnlock museRegionPageVerdict(MuseHttpAnswer? a, RegExp region) {
  if (a == null) return const MuseUnlock(MuseSvcState.failed);
  final base = museServiceVerdict(a.status);
  return MuseUnlock(base, region: base == MuseSvcState.ok ? _match(region, a.body) : null);
}

/// The check for [service] with [fetch]; services without a region check fall back to the status.
Future<MuseUnlock> museCheckUnlock(MuseService service, MuseHttpFetch fetch) async {
  switch (service.key) {
    case 'netflix':
      final first = await fetch(museNetflixLicensed);
      final second = first?.status == 404 ? await fetch(museNetflixLicensed2) : null;
      return museNetflixVerdict(first, second);
    case 'youtube':
      return museYoutubeVerdict(await fetch('https://www.youtube.com/premium'));
    case 'disney':
      return museDisneyVerdict(await fetch(service.url));
    case 'chatgpt':
      final trace = await fetch('https://chatgpt.com/cdn-cgi/trace');
      return museAiVerdict(trace, trace == null ? await fetch(service.url) : null);
    case 'claude':
      final trace = await fetch('https://claude.ai/cdn-cgi/trace');
      return museAiVerdict(trace, await fetch(service.url));
    case 'tiktok':
      return museRegionPageVerdict(await fetch(service.url), RegExp(r'"region":"([A-Z]{2})"'));
    case 'prime':
      return museRegionPageVerdict(await fetch(service.url), RegExp(r'"currentTerritory":"([A-Z]{2})"'));
  }
  final a = await fetch(service.url);
  return MuseUnlock(museServiceVerdict(a?.status));
}

/// Chinese names for the regions seen most; others show their code.
const museRegionNames = {
  'US': '美国', 'HK': '香港', 'TW': '台湾', 'JP': '日本', 'SG': '新加坡', 'KR': '韩国', 'GB': '英国',
  'DE': '德国', 'FR': '法国', 'NL': '荷兰', 'CA': '加拿大', 'AU': '澳大利亚', 'IN': '印度', 'MY': '马来西亚',
  'TH': '泰国', 'VN': '越南', 'PH': '菲律宾', 'ID': '印度尼西亚', 'TR': '土耳其', 'RU': '俄罗斯', 'CN': '中国大陆',
  'MO': '澳门', 'BR': '巴西', 'AR': '阿根廷', 'MX': '墨西哥', 'IT': '意大利', 'ES': '西班牙', 'CH': '瑞士',
  'SE': '瑞典', 'IE': '爱尔兰', 'AE': '阿联酋', 'IL': '以色列', 'NZ': '新西兰', 'PL': '波兰', 'UA': '乌克兰',
};

String museRegionName(String code) => museRegionNames[code.toUpperCase()] ?? code.toUpperCase();

const _bodyLimit = 256 * 1024;

/// The real fetch: GET through 127.0.0.1:[port] when it listens, redirects not followed, body
/// read up to 256 KB. A timeout is thrown as [MuseServiceTimeout]; other failures are null.
MuseHttpFetch museHttpFetch(int port) => (url) async {
  final client = HttpClient()
    ..connectionTimeout = museServiceTimeout
    ..idleTimeout = const Duration(seconds: 1)
    ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
  try {
    var viaProxy = false;
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 500));
      s.destroy();
      viaProxy = true;
    } catch (_) {}
    if (viaProxy) client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
    final req = await client.getUrl(Uri.parse(url)).timeout(museServiceTimeout);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
    final res = await req.close().timeout(museServiceTimeout);
    final buf = <int>[];
    try {
      await for (final chunk in res.timeout(museServiceTimeout)) {
        buf.addAll(chunk);
        if (buf.length >= _bodyLimit) break;
      }
    } catch (_) {}
    return MuseHttpAnswer(
      res.statusCode,
      location: res.headers.value(HttpHeaders.locationHeader) ?? '',
      body: utf8.decode(buf, allowMalformed: true),
    );
  } on TimeoutException {
    throw const MuseServiceTimeout();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
};

/// [museCheckUnlock] in the shape [museProbeServices] takes.
MuseServiceCheck museUnlockServiceCheck(MuseHttpFetch fetch) => (service) async {
  final u = await museCheckUnlock(service, fetch);
  return (state: u.state, region: u.region);
};

/// 1.12.0: two requests for some services (Netflix, Claude), so a service gets a little longer.
const museUnlockTimeout = Duration(seconds: 10);
