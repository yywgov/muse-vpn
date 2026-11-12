// 穿云 1.15.0 R20 - DNS 泄漏检测：点按才测。访问一个随机子域名（免费公开接口 edns.ip-api.com，
// 无需密钥），它回答是哪台 DNS 服务器替你解析了这个境外域名；解析服务器在中国大陆时提示可能泄漏
// （运营商能看到你访问的境外域名）。经本机代理端口发出（端口不在时直连），不轮询、不在后台运行。
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum MuseDnsLeakVerdict {
  safe('未发现泄漏'),
  leak('可能泄漏'),
  unknown('无法判断');

  const MuseDnsLeakVerdict(this.title);

  final String title;
}

class MuseDnsLeakResult {
  const MuseDnsLeakResult({required this.verdict, required this.text, this.resolverIp = '', this.resolverGeo = '', this.error});

  final MuseDnsLeakVerdict verdict;

  /// 一句中文说明
  final String text;
  final String resolverIp;

  /// 检测站给的「国家 - 运营商」
  final String resolverGeo;

  /// 失败原因（中文），成功时为 null
  final String? error;

  bool get failed => error != null;
}

/// 32 位随机十六进制子域名（每次不同，避开各级缓存）。
String museDnsLeakHost([Random? rnd]) {
  final r = rnd ?? Random.secure();
  final s = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  return '$s.edns.ip-api.com';
}

String museDnsLeakUrl(String host) => 'http://$host/json';

bool _isMainlandChina(String geo) {
  final country = geo.split(' - ').first.trim().toLowerCase();
  return country == 'china' || country == '中国';
}

/// 检测站的回答 → 结论。[connected] = 穿云已连接（未连接时只报告，不判泄漏）。
MuseDnsLeakResult museParseDnsLeak(String body, {required bool connected}) {
  Map<dynamic, dynamic>? dns;
  try {
    final j = jsonDecode(body);
    if (j is Map && j['dns'] is Map) dns = j['dns'] as Map;
  } catch (_) {}
  if (dns == null || '${dns['ip'] ?? ''}'.isEmpty) {
    return const MuseDnsLeakResult(verdict: MuseDnsLeakVerdict.unknown, text: '检测服务返回了无法识别的结果', error: '检测服务返回了无法识别的结果');
  }
  final ip = '${dns['ip']}';
  final geo = '${dns['geo'] ?? ''}'.trim();
  final where = geo.isEmpty ? ip : '$geo（$ip）';
  if (!connected) {
    return MuseDnsLeakResult(
      verdict: MuseDnsLeakVerdict.unknown,
      text: '未连接：当前由 $where 解析。连接后再测才能判断是否泄漏',
      resolverIp: ip,
      resolverGeo: geo,
    );
  }
  if (_isMainlandChina(geo)) {
    return MuseDnsLeakResult(
      verdict: MuseDnsLeakVerdict.leak,
      text: '境外域名由国内服务器 $where 解析，运营商可能看到你访问的境外网站。可在「设置 › 连接与网络 › 网络 › 远程 DNS」更换后再测',
      resolverIp: ip,
      resolverGeo: geo,
    );
  }
  return MuseDnsLeakResult(verdict: MuseDnsLeakVerdict.safe, text: '境外域名由 $where 解析，没有经过国内运营商', resolverIp: ip, resolverGeo: geo);
}

/// 失败原因 → 中文。
String museDnsLeakErrorText(Object e) {
  if (e is TimeoutException) return '检测超时，请检查网络后重试';
  if (e is SocketException) return '无法连接检测服务，请稍后重试';
  if (e is HttpException) return '检测服务暂不可用，请稍后重试';
  return '检测失败，请稍后重试';
}

/// 测一次：经 127.0.0.1:[port]（未监听时直连）。[get] 供测试替换网络请求。
Future<MuseDnsLeakResult> museRunDnsLeakTest({
  required int port,
  required bool connected,
  Future<String> Function(String url, int? proxyPort)? get,
}) async {
  final url = museDnsLeakUrl(museDnsLeakHost());
  try {
    final body = await (get ?? _get)(url, port);
    return museParseDnsLeak(body, connected: connected);
  } catch (e) {
    final msg = museDnsLeakErrorText(e);
    return MuseDnsLeakResult(verdict: MuseDnsLeakVerdict.unknown, text: msg, error: msg);
  }
}

Future<String> _get(String url, int? port) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 2)
    ..userAgent = 'Mozilla/5.0';
  try {
    if (port != null) {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
        s.destroy();
        client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
      } catch (_) {}
    }
    final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      unawaited(res.drain<void>().catchError((_) {}));
      throw HttpException('HTTP ${res.statusCode}');
    }
    return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
  } finally {
    client.close(force: true);
  }
}
