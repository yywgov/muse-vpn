// 穿云 1.5.0 #24 - 下载测速: downloads up to 5 MB through the app's own local port (so through the
// node in use) and reports the speed. Only for the node in use: testing another one would mean
// switching the connection. Nothing runs unless the user taps the button.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';

/// Where the test downloads from (a speed-test endpoint that serves exactly the bytes asked for).
const museSpeedTestUrl = 'https://speed.cloudflare.com/__down?bytes=5000000';
const museSpeedTestBytes = 5000000;

class MuseSpeedTestException implements Exception {
  const MuseSpeedTestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One download test; [cancel] stops it (the future then completes with an error).
class MuseSpeedTest {
  MuseSpeedTest({required this.port, this.url = museSpeedTestUrl, this.timeout = const Duration(seconds: 20)});

  final int port;
  final String url;
  final Duration timeout;
  HttpClient? _client;
  bool _cancelled = false;

  /// Bytes per second over the whole download (connection set-up included, like a real page).
  Future<double> run() async {
    final client = HttpClient()
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$port')
      ..connectionTimeout = const Duration(seconds: 8);
    _client = client;
    final watch = Stopwatch()..start();
    var received = 0;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) throw MuseSpeedTestException('HTTP ${res.statusCode}');
      final deadline = timeout - watch.elapsed;
      await for (final chunk in res.timeout(deadline.isNegative ? Duration.zero : deadline)) {
        if (_cancelled) throw const MuseSpeedTestException('已取消');
        received += chunk.length;
        if (received >= museSpeedTestBytes) break;
      }
    } on TimeoutException {
      // a slow node: what arrived in time still says how fast it is
      if (received < 256 * 1024) throw const MuseSpeedTestException('超时');
    } on SocketException catch (e) {
      throw MuseSpeedTestException(_cancelled ? '已取消' : '连接失败：${e.osError?.message ?? e.message}');
    } on HttpException catch (e) {
      throw MuseSpeedTestException(_cancelled ? '已取消' : '下载失败：${e.message}');
    } finally {
      watch.stop();
      client.close(force: true);
      _client = null;
    }
    if (_cancelled) throw const MuseSpeedTestException('已取消');
    final secs = watch.elapsedMicroseconds / 1e6;
    if (received == 0 || secs <= 0) throw const MuseSpeedTestException('没有收到数据');
    return received / secs;
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }
}
