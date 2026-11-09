// 穿云 1.19.0 P1 分类线：AI / 视频 / 开发 / 直连 各占多少流量。数据只来自已经在读的连接列表
// （连接页每秒一帧、统计页打开时读一次），本文件不读接口、不开计时器、不轮询；首页只显示最近一次的结果。
// 分类按域名与进程名里的通用词判断（不认具体应用），出站是直连的算「直连」。
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum MuseRouteKind {
  ai('AI'),
  video('视频'),
  dev('开发'),
  direct('直连');

  const MuseRouteKind(this.label);

  final String label;
}

// 通用词（不含具体应用名）
final _aiWords = RegExp(r'(^|[.\-_/])(ai|gpt|llm|chat|assistant|inference)([.\-_/]|$)|\.ai$|智能|大模型|助手');
final _videoWords = RegExp(
  r'(^|[.\-_/])(video|videos|vod|tv|live|stream|streaming|media|movie|movies|player|hls|dash)([.\-_/]|$)|\.tv$|视频|影视|直播|播放器',
);
final _devWords = RegExp(
  r'(^|[.\-_/])(git|code|dev|npm|pypi|pub|docker|registry|maven|gradle|crates|ssh|terminal|ide|sdk|api-docs)([.\-_/]|$)|\.dev$|终端|开发',
);

/// 一条连接属于哪一类；判断不了返回 null（算进「其他」，不画线）。
MuseRouteKind? museRouteKindOf(MuseConn c) {
  final chains = c.chains.map((e) => e.toLowerCase());
  if (chains.isNotEmpty && chains.every((e) => e == 'direct' || e == 'bypass' || e == '直连')) {
    return MuseRouteKind.direct;
  }
  final host = c.host.toLowerCase();
  final proc = c.process.toLowerCase().replaceAll('\\', '/').split('/').last;
  for (final s in [host, proc]) {
    if (s.isEmpty) continue;
    if (_aiWords.hasMatch(s)) return MuseRouteKind.ai;
    if (_videoWords.hasMatch(s)) return MuseRouteKind.video;
    if (_devWords.hasMatch(s)) return MuseRouteKind.dev;
  }
  return null;
}

/// 本次连接以来各类的字节数（含「其他」），由连接帧累加。
class MuseRouteShareState {
  const MuseRouteShareState({this.bytes = const {}, this.other = 0});

  static const empty = MuseRouteShareState();

  final Map<MuseRouteKind, int> bytes;
  final int other;

  int get total => other + bytes.values.fold(0, (a, b) => a + b);

  /// 各类占全部流量的比例（0–1），按占比从大到小；占比低于 [min] 的不画。无数据时为空。
  List<(MuseRouteKind, double)> shares({double min = 0.02}) {
    final t = total;
    if (t <= 0) return const [];
    final l = [
      for (final e in bytes.entries)
        if (e.value / t >= min) (e.key, e.value / t),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return l;
  }

  /// 首页只在整数百分比变化时重画
  String get signature => [for (final s in shares()) '${s.$1.name}${(s.$2 * 100).round()}'].join(',');
}

class MuseRouteShareNotifier extends StateNotifier<MuseRouteShareState> {
  MuseRouteShareNotifier() : super(MuseRouteShareState.empty);

  final _seen = <String, int>{};
  final _bytes = <MuseRouteKind, int>{};
  var _other = 0;

  /// 喂一帧连接（连接页的每一帧、统计页打开时的一次读取）。
  void frame(Iterable<MuseConn> conns) {
    final alive = <String>{};
    for (final c in conns) {
      if (c.end != null) continue;
      alive.add(c.id);
      final total = c.total < 0 ? 0 : c.total;
      final before = _seen[c.id];
      _seen[c.id] = total;
      final delta = before == null ? total : (total >= before ? total - before : total);
      if (delta <= 0) continue;
      final k = museRouteKindOf(c);
      if (k == null) {
        _other += delta;
      } else {
        _bytes[k] = (_bytes[k] ?? 0) + delta;
      }
    }
    _seen.removeWhere((id, _) => !alive.contains(id));
    final next = MuseRouteShareState(bytes: Map.unmodifiable(_bytes), other: _other);
    if (next.signature != state.signature) state = next;
  }

  void reset() {
    _seen.clear();
    _bytes.clear();
    _other = 0;
    if (state.total != 0) state = MuseRouteShareState.empty;
  }
}

/// 连接 / 断开时清零。
final museRouteShareProvider = StateNotifierProvider<MuseRouteShareNotifier, MuseRouteShareState>((ref) {
  final n = MuseRouteShareNotifier();
  ref.listen<bool>(museRunningProvider, (_, _) => n.reset());
  return n;
});
