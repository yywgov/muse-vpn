// 穿云 1.6.0 C4 - the 首页 dashboard cards added in 1.6.0: 服务状态, 代理组, 连接统计, 内网 IP, 内存,
// 网络接管 (Windows). Each is a small widget that watches only its own data (selects), so a 1 s
// stats frame never rebuilds the rest of 首页. All hidden by default (编辑首页 adds them).
// Part of 穿云 (GPLv3).

part of 'muse_home_page.dart';

// ---------------------------------------------------------------- 服务状态

class MuseServicesState {
  const MuseServicesState({this.results = const {}, this.ms = const {}, this.checking = false, this.at});

  final Map<String, MuseSvcState> results;

  /// 1.10.4: answer time per service (ms), shown next to 可用
  final Map<String, int> ms;
  final bool checking;
  final DateTime? at;

  int get okCount => results.values.where((v) => v == MuseSvcState.ok).length;

  /// 1.10.4: nothing to show and nothing running (a new connection / never checked): the card
  /// starts a check when it is on screen, instead of showing 检测中 with nothing behind it.
  bool get idle => !checking && results.isEmpty;
}

class MuseServicesNotifier extends StateNotifier<MuseServicesState> {
  MuseServicesNotifier(this._probe, {DateTime Function()? now, this.totalCap = museServiceTotalCap})
    : _now = now ?? DateTime.now,
      super(const MuseServicesState());

  final MuseServiceProbe Function() _probe;
  final DateTime Function() _now;
  final Duration totalCap;
  final cache = MuseServiceCache();
  int _run = 0;

  /// Probes unless the cache is fresh ([force] = the user tapped the card or 刷新). Always ends
  /// with every service in a final state and [MuseServicesState.checking] false (1.10.4).
  Future<void> check({bool force = false}) async {
    if (state.checking) return;
    if (!force && cache.fresh(_now())) {
      state = MuseServicesState(results: cache.results, ms: cache.ms, at: cache.at);
      return;
    }
    final run = ++_run;
    state = MuseServicesState(results: const {}, checking: true, at: state.at);
    final partial = <String, MuseSvcState>{};
    final ms = <String, int>{};
    Map<String, MuseSvcState> results;
    try {
      results = await museProbeServices(
        _probe(),
        totalCap: totalCap,
        onResult: (k, v, t) {
          partial[k] = v;
          if (t != null) ms[k] = t;
          if (!mounted || run != _run) return;
          state = MuseServicesState(results: Map.of(partial), ms: Map.of(ms), checking: true, at: state.at);
        },
      );
    } catch (_) {
      // 1.10.4: never leave the card at 检测中 — what did not answer failed
      results = {for (final s in museServices) s.key: partial[s.key] ?? MuseSvcState.failed};
    }
    if (!mounted || run != _run) return;
    cache.store(results, _now(), ms: ms);
    state = MuseServicesState(results: results, ms: Map.of(ms), at: cache.at);
  }

  /// A new connection: what answered before says nothing now. The card (when on screen) checks
  /// again because the state is [MuseServicesState.idle].
  void reset() {
    _run++;
    cache.clear();
    state = const MuseServicesState();
  }

  /// 1.10.4: another node — keep showing the last results (they stay final) but the next check
  /// (tap, or the card coming back) probes again. Before, every switch of 自动最快 / 负载均衡 (or the
  /// node list reloading) wiped the results while the card stayed on screen, and nothing started a
  /// new check: 「检测中」 with every service at 「—」 for as long as the app stayed open.
  void stale() {
    cache.clear();
  }
}

final museServicesProvider = StateNotifierProvider<MuseServicesNotifier, MuseServicesState>((ref) {
  final n = MuseServicesNotifier(() => museHttpServiceProbe(ref.read(ConfigOptions.mixedPort)));
  ref.listen<bool>(museRunningProvider, (prev, running) {
    if (prev != running) n.reset();
  });
  ref.listen<String?>(proxiesOverviewNotifierProvider.select((g) => g.valueOrNull?.selected), (prev, next) {
    // 1.10.4: the list reloading (null in between) is not a node change
    if (prev != null && next != null && prev != next) n.stale();
  });
  return n;
});

String museServiceStateText(MuseSvcState s) => switch (s) {
  MuseSvcState.ok => '可用',
  MuseSvcState.limited => '受限',
  MuseSvcState.failed => '不可用',
  MuseSvcState.timeout => '超时',
  MuseSvcState.checking => '检测中',
  MuseSvcState.unknown => '—',
};

/// 1.10.4: one service as the card / sheet shows it: 可用 with its answer time, else the state.
String museServiceLabel(MuseSvcState s, int? ms) =>
    s == MuseSvcState.ok && ms != null ? '${museServiceStateText(s)} $ms ms' : museServiceStateText(s);

/// 1.10.4: the card's big value — 检测中 only while a check runs.
String museServicesValue({required bool running, required MuseServicesState s, required int total}) {
  if (!running) return '—';
  if (s.results.isEmpty) return s.checking ? '检测中' : '点按检测';
  return '${s.okCount}/$total';
}

class _ServicesTile extends HookConsumerWidget {
  const _ServicesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(museRunningProvider);
    final s = ref.watch(museServicesProvider);
    // checks once the card is on screen and connected (cached 10 minutes); 1.10.4: also when the
    // results were cleared while the card stayed on screen (no timer: it reacts to that change)
    final idle = s.idle;
    useEffect(() {
      if (running && idle) Future.microtask(() => ref.read(museServicesProvider.notifier).check());
      return null;
    }, [running, idle]);
    final total = museServices.length;
    final value = museServicesValue(running: running, s: s, total: total);
    final mt = MuseTheme.of(context);
    return _Tile(
      title: '服务状态',
      titleTrailing: s.checking
          ? SizedBox(
              width: MuseSpace.s12,
              height: MuseSpace.s12,
              child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke, color: mt.text2),
            )
          : null,
      value: value,
      bottom: Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          !running
              ? '未连接'
              : [
                  for (final sv in museServices.take(4))
                    '${sv.name} ${museServiceLabel(s.results[sv.key] ?? (s.checking ? MuseSvcState.checking : MuseSvcState.unknown), s.ms[sv.key])}',
                ].join(' · '),
          style: MuseType.caption(context),
        ),
      ),
      // 1.10.4: a tap checks again (unless a check is running) and shows the details
      onTap: () {
        if (running && !s.checking) ref.read(museServicesProvider.notifier).check(force: true);
        showMuseSnapSheet<void>(
          context,
          title: '服务状态',
          builder: (_, c) => _ServicesSheet(controller: c),
        );
      },
    );
  }
}

class _ServicesSheet extends ConsumerWidget {
  const _ServicesSheet({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(museServicesProvider);
    final running = ref.watch(museRunningProvider);
    return CustomScrollView(
      key: const ValueKey('services_sheet'),
      controller: controller,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
            child: Row(
              children: [
                Expanded(child: Text(running ? '经当前节点访问，每 10 分钟最多检测一次' : '连接后才能检测', style: MuseType.caption(context))),
                TextButton(
                  key: const ValueKey('services_refresh'),
                  onPressed: running && !s.checking
                      ? () => ref.read(museServicesProvider.notifier).check(force: true)
                      : null,
                  child: const Text('刷新'),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(MuseSpace.s16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: MuseSize.rowMin,
              crossAxisSpacing: MuseSpace.s8,
              mainAxisSpacing: MuseSpace.s8,
            ),
            delegate: SliverChildBuilderDelegate(childCount: museServices.length, (context, i) {
              final sv = museServices[i];
              final st = s.results[sv.key] ?? (s.checking ? MuseSvcState.checking : MuseSvcState.unknown);
              final color = switch (st) {
                MuseSvcState.ok => Theme.of(context).colorScheme.success,
                MuseSvcState.limited => Theme.of(context).colorScheme.warning,
                MuseSvcState.failed || MuseSvcState.timeout => Theme.of(context).colorScheme.error,
                _ => Theme.of(context).colorScheme.idle,
              };
              return MuseCard(
                key: ValueKey('service_${sv.key}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(sv.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.body(context)),
                    ),
                    Text(museServiceLabel(st, s.ms[sv.key]), style: MuseType.caption(context).copyWith(color: color)),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 代理组

class _GroupsTile extends ConsumerWidget {
  const _GroupsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(museNodeGroupProvider.select((g) => g.valueOrNull));
    final selected = group?.selected ?? '';
    final count = group?.items.length ?? 0;
    return _Tile(
      title: '代理组',
      titleTrailing: group == null ? null : Text(museGroupTitle(group.tag), style: MuseType.caption(context)),
      value: selected.isEmpty ? '—' : museNodeShortName(selected),
      bottom: Align(
        alignment: Alignment.bottomLeft,
        child: Text(group == null ? '还没有节点' : '$count 个节点', style: MuseType.caption(context)),
      ),
      onTap: () => context.goNamed('nodes'),
    );
  }
}

/// 「select」/「auto」 → 手动选择 / 自动最快; other tags as they are.
String museGroupTitle(String tag) => switch (tag.toLowerCase()) {
  'select' || 'proxy' => '手动选择',
  'auto' || 'urltest' => '自动最快',
  _ => tag,
};

/// The node name without a trailing latency / rate decoration.
String museNodeShortName(String name) => name.replaceAll(RegExp(r'\s*§.*$'), '').trim();

// ---------------------------------------------------------------- 连接统计

class _ConnectionsTile extends ConsumerWidget {
  const _ConnectionsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(museRunningProvider);
    final count = running ? ref.watch(museConnectionsProvider.select((s) => s.valueOrNull?.connections.length)) : null;
    final error = running ? ref.watch(museConnectionsProvider.select((s) => s.valueOrNull?.error)) : null;
    final requests = ref.watch(museRequestHistoryProvider).length;
    return _Tile(
      title: '连接统计',
      value: count == null ? '—' : '$count',
      bottom: Align(
        alignment: Alignment.bottomLeft,
        child: Text(!running ? '未连接' : (error ?? '活动连接 · 最近请求 $requests'), style: MuseType.caption(context)),
      ),
      onTap: () => context.go(museActivityLocation(MuseActivityTab.connections)),
    );
  }
}

// ---------------------------------------------------------------- 内网 IP

final museLanIpProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  try {
    return museLanAddresses(await NetworkInterface.list(includeLinkLocal: false));
  } catch (_) {
    return const [];
  }
});

class _LanIpTile extends ConsumerWidget {
  const _LanIpTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ips = ref.watch(museLanIpProvider).valueOrNull;
    final first = ips?.firstOrNull;
    return _Tile(
      title: '内网 IP',
      value: ips == null ? '…' : (first ?? '—'),
      bottom: Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          ips == null ? '' : (ips.length > 1 ? ips[1] : (first == null ? '没有局域网地址' : '点按复制')),
          style: MuseType.caption(context),
        ),
      ),
      onTap: first == null
          ? () => ref.invalidate(museLanIpProvider)
          : () async {
              await Clipboard.setData(ClipboardData(text: ips!.join('\n')));
              try {
                ref.read(inAppNotificationControllerProvider).showSuccessToast('已复制内网 IP');
              } catch (_) {}
            },
    );
  }
}

// ---------------------------------------------------------------- 内存

/// 「12.3 MB」.
String museMemText(int bytes) {
  if (bytes <= 0) return '—';
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${mb >= 100 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1)} MB';
}

/// The last 30 samples of the core's memory (one per stats frame while connected).
class MuseMemoryHistory extends Notifier<List<int>> {
  static const points = 30;

  @override
  List<int> build() {
    ref.listen<bool>(museRunningProvider, (_, running) {
      if (!running) state = const [];
    });
    ref.listen<int>(museStatsProvider.select((s) => s.memory.toInt()), (_, m) {
      if (!ref.read(museRunningProvider)) return;
      state = museAppendSample(state, m, points);
    });
    return const [];
  }
}

List<int> museAppendSample(List<int> list, int v, int max) {
  final next = [...list, v];
  return next.length > max ? next.sublist(next.length - max) : next;
}

final museMemoryHistoryProvider = NotifierProvider<MuseMemoryHistory, List<int>>(MuseMemoryHistory.new);

class _MemoryTile extends ConsumerWidget {
  const _MemoryTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(museStatsProvider.select((s) => s.memory.toInt()));
    final history = ref.watch(museMemoryHistoryProvider);
    final app = ProcessInfo.currentRss;
    return _Tile(
      title: '内存',
      titleTrailing: Text('应用 ${museMemText(app)}', style: MuseType.caption(context)),
      value: core > 0 ? museMemText(core) : '—',
      bottom: history.length < 2
          ? Align(
              alignment: Alignment.bottomLeft,
              child: Text('内核', style: MuseType.caption(context)),
            )
          : RepaintBoundary(
              child: SizedBox.expand(
                child: CustomPaint(
                  painter: _SparklinePainter(
                    history,
                    Theme.of(context).colorScheme.secondSeries,
                    MuseTheme.of(context).hairline,
                  ),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------- 网络接管 (Windows)

class _TakeoverTile extends ConsumerWidget {
  const _TakeoverTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ConfigOptions.serviceMode);
    final tun = mode == ServiceMode.tun;
    return _Tile(
      title: '网络接管',
      value: tun ? 'TUN' : '系统代理',
      bottomHeight: MuseSize.segmented,
      bottom: MuseSegmented<ServiceMode>(
        key: const ValueKey('takeover_segmented'),
        values: const [ServiceMode.systemProxy, ServiceMode.tun],
        selected: tun ? ServiceMode.tun : ServiceMode.systemProxy,
        label: (m) => m == ServiceMode.tun ? 'TUN' : '系统代理',
        onChanged: (m) => museSwitchServiceMode(ref.read, m),
      ),
    );
  }
}
