// 穿云 1.16.0 B7 - records 按应用流量 only while a page that already reads the connections is open
// (统计 reads /connections once when opened; 连接 streams one frame a second while open, flushed
// every 30 frames and when the page is left). No background sampling, no timer of its own.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/app_traffic.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The per-connection baseline; cleared on every connect / disconnect.
final museAppSamplerProvider = Provider<MuseAppTrafficSampler>((ref) {
  final s = MuseAppTrafficSampler();
  ref.listen<bool>(museRunningProvider, (_, _) => s.reset());
  return s;
});

/// Writes [bytes] into today's 按应用流量.
void museSaveAppBytes(PreferencesNotifierLike notifier, String current, Map<String, (int, String)> bytes, {DateTime? now}) {
  if (bytes.isEmpty) return;
  final next = MuseAppTrafficLog.parse(current).add(now ?? DateTime.now(), bytes);
  notifier.update(next.toRaw());
}

/// What [museSaveAppBytes] needs of a preference notifier (tests pass a fake).
abstract interface class PreferencesNotifierLike {
  Future<void> update(String value);
}

class _PrefWriter implements PreferencesNotifierLike {
  _PrefWriter(this.write);
  final Future<void> Function(String) write;
  @override
  Future<void> update(String value) => write(value);
}

/// 统计 page opened: one read of /connections while connected.
final museAppTrafficOnOpenProvider = FutureProvider.autoDispose<void>((ref) async {
  final api = ref.watch(museLocalApiProvider);
  if (api == null) return;
  try {
    final j = await api.getJson('/connections');
    final conns = [
      for (final c in (j['connections'] as List? ?? const []))
        if (c is Map) MuseConn.fromJson(c.cast<String, dynamic>()),
    ].whereType<MuseConn>();
    final bytes = ref.read(museAppSamplerProvider).sample(conns);
    final n = ref.read(MusePrefs.appTraffic.notifier);
    museSaveAppBytes(_PrefWriter(n.update), ref.read(MusePrefs.appTraffic), bytes);
  } catch (_) {}
});

/// Used by 连接: feeds each frame, flushes every [flushEvery] frames and on [close].
class MuseAppTrafficFeed {
  MuseAppTrafficFeed(this._sampler, this._read, this._write, {this.flushEvery = 30});

  final MuseAppTrafficSampler _sampler;
  final String Function() _read;
  final Future<void> Function(String) _write;
  final int flushEvery;
  var _pending = <String, (int, String)>{};
  var _frames = 0;

  void frame(Iterable<MuseConn> conns) {
    _pending = museMergeAppBytes(_pending, _sampler.sample(conns));
    if (++_frames % flushEvery == 0) flush();
  }

  void flush() {
    if (_pending.isEmpty) return;
    final p = _pending;
    _pending = {};
    try {
      museSaveAppBytes(_PrefWriter(_write), _read(), p);
    } catch (_) {}
  }
}
