// 穿云 - 首页 网速 card: live speed curve + speed test through the current node.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ---------------------------------------------------------------------------------------------
// live speed history (last 60 s)

typedef SpeedSample = ({int up, int down});

final museSpeedHistoryProvider = NotifierProvider<MuseSpeedHistory, List<SpeedSample>>(MuseSpeedHistory.new);

class MuseSpeedHistory extends Notifier<List<SpeedSample>> {
  static const length = 60;

  @override
  List<SpeedSample> build() {
    ref.listen(serviceRunningProvider, (_, running) {
      if (!running) state = const [];
    });
    ref.listen(statsNotifierProvider, (_, next) {
      final info = next.valueOrNull;
      if (info == null || !ref.read(serviceRunningProvider)) return;
      final list = [...state, (up: info.uplink.toInt(), down: info.downlink.toInt())];
      state = list.length > length ? list.sublist(list.length - length) : list;
    });
    return const [];
  }
}

class MuseSpeedChart extends StatelessWidget {
  const MuseSpeedChart({super.key, required this.samples});

  final List<SpeedSample> samples;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(double.infinity, 56),
        painter: _SpeedPainter(samples, MuseColors.brandLight, const Color(0xFF22C55E), MuseColors.separator(context)),
      ),
    );
  }
}

class _SpeedPainter extends CustomPainter {
  _SpeedPainter(this.samples, this.downColor, this.upColor, this.gridColor);

  final List<SpeedSample> samples;
  final Color downColor;
  final Color upColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), grid);
    if (samples.length < 2) return;
    final peak = samples.fold<int>(1, (m, s) => max(m, max(s.up, s.down))).toDouble();
    final step = size.width / (MuseSpeedHistory.length - 1);
    final offset = (MuseSpeedHistory.length - samples.length) * step;

    Path line(int Function(SpeedSample s) pick) {
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = offset + i * step;
        final y = size.height - 2 - (pick(samples[i]) / peak) * (size.height - 6);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      return path;
    }

    final down = line((s) => s.down);
    final fill = Path.from(down)
      ..lineTo(offset + (samples.length - 1) * step, size.height)
      ..lineTo(offset, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [downColor.withValues(alpha: 0.35), downColor.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(down, stroke..color = downColor);
    canvas.drawPath(line((s) => s.up), stroke..color = upColor.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_SpeedPainter old) => !identical(old.samples, samples) || old.gridColor != gridColor;
}

// ---------------------------------------------------------------------------------------------
// speed test (speed.cloudflare.com through the local mixed proxy, so it runs over the node)

enum SpeedTestPhase { idle, latency, download, upload, done, failed }

@immutable
class SpeedTestState {
  const SpeedTestState({this.phase = SpeedTestPhase.idle, this.latencyMs, this.downMbps, this.upMbps, this.error});

  final SpeedTestPhase phase;
  final int? latencyMs;
  final double? downMbps;
  final double? upMbps;
  final String? error;

  bool get running =>
      phase == SpeedTestPhase.latency || phase == SpeedTestPhase.download || phase == SpeedTestPhase.upload;

  SpeedTestState copyWith({SpeedTestPhase? phase, int? latencyMs, double? downMbps, double? upMbps, String? error}) =>
      SpeedTestState(
        phase: phase ?? this.phase,
        latencyMs: latencyMs ?? this.latencyMs,
        downMbps: downMbps ?? this.downMbps,
        upMbps: upMbps ?? this.upMbps,
        error: error ?? this.error,
      );
}

final museSpeedTestProvider = NotifierProvider<MuseSpeedTest, SpeedTestState>(MuseSpeedTest.new);

class MuseSpeedTest extends Notifier<SpeedTestState> {
  static const _host = 'speed.cloudflare.com';
  static const _phaseTime = Duration(seconds: 8);
  int _run = 0;

  @override
  SpeedTestState build() {
    ref.listen(serviceRunningProvider, (_, running) {
      if (!running) {
        _run++;
        state = const SpeedTestState();
      }
    });
    return const SpeedTestState();
  }

  HttpClient _client() {
    final port = ref.read(ConfigOptions.mixedPort);
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 5)
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$port');
  }

  Future<void> start() async {
    if (state.running) return;
    final run = ++_run;
    bool alive() => run == _run;
    final client = _client();
    try {
      state = const SpeedTestState(phase: SpeedTestPhase.latency);
      final latency = await _latency(client);
      if (!alive()) return;
      state = state.copyWith(phase: SpeedTestPhase.download, latencyMs: latency);
      final down = await _download(client, alive);
      if (!alive()) return;
      state = state.copyWith(phase: SpeedTestPhase.upload, downMbps: down);
      final up = await _upload(client, alive);
      if (!alive()) return;
      state = state.copyWith(phase: SpeedTestPhase.done, upMbps: up);
    } catch (e) {
      if (alive()) state = state.copyWith(phase: SpeedTestPhase.failed, error: '测速失败，请确认已连接且节点可用');
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _latency(HttpClient client) async {
    var best = 1 << 30;
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      final req = await client.getUrl(Uri.https(_host, '/__down', {'bytes': '0'}));
      req.headers.set(HttpHeaders.refererHeader, 'https://$_host/');
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>();
      best = min(best, sw.elapsedMilliseconds);
    }
    return best;
  }

  Future<double> _download(HttpClient client, bool Function() alive) async {
    final req = await client.getUrl(Uri.https(_host, '/__down', {'bytes': '${100 * 1024 * 1024}'}));
    req.headers.set(HttpHeaders.refererHeader, 'https://$_host/');
    final res = await req.close().timeout(const Duration(seconds: 10));
    var bytes = 0;
    final sw = Stopwatch()..start();
    final done = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = res.listen(
      (chunk) {
        bytes += chunk.length;
        if (sw.elapsed >= _phaseTime || !alive()) {
          sub.cancel();
          if (!done.isCompleted) done.complete();
        }
      },
      onDone: () => done.isCompleted ? null : done.complete(),
      onError: (Object e) => done.isCompleted ? null : done.completeError(e),
      cancelOnError: true,
    );
    await done.future.timeout(_phaseTime + const Duration(seconds: 4), onTimeout: () => sub.cancel());
    return _mbps(bytes, sw.elapsed);
  }

  Future<double> _upload(HttpClient client, bool Function() alive) async {
    final chunk = Uint8List(64 * 1024);
    final req = await client.postUrl(Uri.https(_host, '/__up'));
    req.headers.set(HttpHeaders.refererHeader, 'https://$_host/');
    req.headers.contentType = ContentType.binary;
    req.contentLength = -1;
    req.bufferOutput = false;
    var bytes = 0;
    final sw = Stopwatch()..start();
    while (sw.elapsed < _phaseTime && alive()) {
      req.add(chunk);
      await req.flush();
      bytes += chunk.length;
    }
    final elapsed = sw.elapsed;
    final res = await req.close().timeout(const Duration(seconds: 8));
    await res.drain<void>();
    return _mbps(bytes, elapsed);
  }

  double _mbps(int bytes, Duration elapsed) {
    final seconds = max(elapsed.inMilliseconds, 1) / 1000;
    return bytes * 8 / seconds / 1000000;
  }
}

// ---------------------------------------------------------------------------------------------

class MuseSpeedCard extends ConsumerWidget {
  const MuseSpeedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final secondary = MuseColors.secondaryText(context);
    final samples = ref.watch(museSpeedHistoryProvider);
    final test = ref.watch(museSpeedTestProvider);
    final running = ref.watch(serviceRunningProvider);
    final last = samples.isEmpty ? null : samples.last;

    String mbps(double? v) => v == null ? '--' : (v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));

    Widget metric(String label, String value, String unit, {bool active = false}) => Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: secondary)),
          const SizedBox(height: 2),
          active
              ? const SizedBox(
                  height: 22,
                  child: Center(
                    child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      TextSpan(text: ' $unit', style: theme.textTheme.labelSmall?.copyWith(color: secondary)),
                    ],
                  ),
                ),
        ],
      ),
    );

    return MuseSection(
      header: '网速',
      headerTrailing: TextButton(
        onPressed: running && !test.running ? () => ref.read(museSpeedTestProvider.notifier).start() : null,
        child: Text(test.running ? '测速中…' : '测速'),
      ),
      footer: test.error ?? (running ? '测速经过当前节点（Cloudflare），约 20 秒，会消耗约 50~200 MB 流量。' : '连接后可查看实时网速和测速。'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  _Legend(color: MuseColors.brandLight, text: '↓ ${last == null ? '--' : last.down.speed()}'),
                  const SizedBox(width: 16),
                  _Legend(color: const Color(0xFF22C55E), text: '↑ ${last == null ? '--' : last.up.speed()}'),
                ],
              ),
              const SizedBox(height: 8),
              MuseSpeedChart(samples: samples),
              const SizedBox(height: 12),
              Row(
                children: [
                  metric('延迟', test.latencyMs?.toString() ?? '--', 'ms', active: test.phase == SpeedTestPhase.latency),
                  metric('下载', mbps(test.downMbps), 'Mbps', active: test.phase == SpeedTestPhase.download),
                  metric('上传', mbps(test.upMbps), 'Mbps', active: test.phase == SpeedTestPhase.upload),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
