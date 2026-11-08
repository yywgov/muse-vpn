// 穿云 - 设置 › 统计. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// 1.11.0: 导出 CSV removed.

// ======================================================================= 统计

class MuseStatsPage extends HookConsumerWidget {
  const MuseStatsPage({super.key, this.header});

  /// 1.10.0: the 活动 tabs (统计 is a tab of 设置 › 活动)
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = MuseTrafficLog.parse(ref.watch(MusePrefs.trafficLog));
    // 1.5.0 #172: 日 / 周 / 月
    final range = useState(0);
    final now = DateTime.now();
    final days = log.lastDays(now, 14);
    final months = log.months();
    final shownMonths = months.length > 12 ? months.sublist(months.length - 12) : months;
    final bars = switch (range.value) {
      2 => [for (final m in shownMonths) (m.$1.substring(5), m.$2 + m.$3)],
      1 => [for (final w in log.lastWeeks(now, 8)) ('${int.parse(w.$1.substring(5, 7))}/${int.parse(w.$1.substring(8))}', w.$2 + w.$3)],
      _ => [for (final d in days) (d.$1.substring(8), d.$2 + d.$3)],
    };
    final today = days.isEmpty ? 0 : days.last.$2 + days.last.$3;
    final thisMonth = months.isEmpty || months.last.$1 != museMonthKey(now) ? 0 : months.last.$2 + months.last.$3;
    final report = museMonthlyReport(log, museMonthKey(now), bytes: museBytes);
    final mt = MuseTheme.of(context);
    // 1.16.0 B7: 按应用 — opening this page counts the live connections once (no background sampling)
    ref.watch(museAppTrafficOnOpenProvider);
    final appLog = MuseAppTrafficLog.parse(ref.watch(MusePrefs.appTraffic));
    final appRange = useState(0);
    final labels = ref.watch(museAppLabelsProvider).valueOrNull ?? const <String, String>{};
    final apps = museAppBars(appLog, now, range: appRange.value, labels: labels);

    final body = MuseGroupedBody(
        children: [
          MuseSection(
            dividerIndent: MuseSpace.s16,
            children: [
              MuseTile(title: '今天', trailing: Text(museBytes(today), style: const TextStyle(fontFeatures: MuseType.tabular))),
              MuseTile(title: '本月', trailing: Text(museBytes(thisMonth), style: const TextStyle(fontFeatures: MuseType.tabular))),
            ],
          ),
          MuseSection(
            header: switch (range.value) {
              2 => '每月流量',
              1 => '近 8 周流量',
              _ => '近 14 天流量',
            },
            // 1.5.1: the same pill control as 首页 去广告
            headerTrailing: SizedBox(
              width: MuseSize.segmentedRange,
              child: MuseSegmented<int>(
                key: const ValueKey('stats_range'),
                values: const [0, 1, 2],
                selected: range.value,
                label: (v) => const ['日', '周', '月'][v],
                onChanged: (v) => range.value = v,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(MuseSpace.s16),
                child: SizedBox(
                  height: MuseSize.chartHeight,
                  child: bars.every((b) => b.$2 == 0)
                      ? Center(child: Text('还没有流量记录', style: MuseType.body(context).copyWith(color: mt.text2)))
                      : _MuseBarChart(bars: bars),
                ),
              ),
            ],
          ),
          MuseSection(
            header: '按应用流量',
            footer: '只在本机统计：打开「连接」或「统计」页时累计各应用的流量，保留 30 天',
            headerTrailing: SizedBox(
              width: MuseSize.segmentedRange,
              child: MuseSegmented<int>(
                key: const ValueKey('stats_app_range'),
                values: const [0, 1, 2],
                selected: appRange.value,
                label: (v) => const ['今天', '7 天', '30 天'][v],
                onChanged: (v) => appRange.value = v,
              ),
            ),
            children: [
              if (apps.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(MuseSpace.s16),
                  child: Text('还没有按应用的记录', key: const ValueKey('stats_app_empty'), style: MuseType.body(context).copyWith(color: mt.text2)),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(MuseSpace.s16),
                  child: _MuseAppBars(key: const ValueKey('stats_app_bars'), apps: apps),
                ),
            ],
          ),
          MuseSection(
            header: '本月报告',
            dividerIndent: MuseSpace.s16,
            children: [for (final line in report) MuseTile(title: line)],
          ),
        ],
      );
    return MuseScaffold(
      title: header == null ? '统计' : '活动',
      body: header == null ? body : Column(children: [header!, Expanded(child: body)]),
    );
  }
}

class _MuseBarChart extends StatelessWidget {
  const _MuseBarChart({required this.bars});

  final List<(String, int)> bars;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final maxV = bars.map((b) => b.$2).fold<int>(1, math.max);
    return LayoutBuilder(
      builder: (context, c) {
        final labelH = MuseSpace.s16 + MuseSpace.s4;
        // 1.4.1: never negative (a very short box / large text)
        final h = math.max(0.0, c.maxHeight - labelH);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final b in bars)
              Expanded(
                child: Tooltip(
                  message: '${b.$1}  ${museBytes(b.$2)}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: MuseSize.barGap),
                        height: b.$2 == 0 ? MuseSize.barGap : math.min(h, math.max(MuseSize.barMin, h * b.$2 / maxV)),
                        decoration: BoxDecoration(
                          color: b.$2 == 0 ? mt.hairline : museBrandOf(context),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(MuseSize.barMin)),
                        ),
                      ),
                      SizedBox(
                        height: labelH,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Text(b.$1, style: MuseType.caption(context), maxLines: 1, overflow: TextOverflow.clip),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 1.16.0 B7: the 按应用 bars for [range] (0 今天, 1 近 7 天, 2 近 30 天): (name, bytes), biggest first.
List<(String, int)> museAppBars(MuseAppTrafficLog log, DateTime now, {required int range, Map<String, String> labels = const {}}) => [
  for (final a in log.top(now, n: const [1, 7, 30][range.clamp(0, 2)], count: 8)) (labels[a.$1] ?? a.$2, a.$3),
];

class _MuseAppBars extends StatelessWidget {
  const _MuseAppBars({super.key, required this.apps});

  final List<(String, int)> apps;

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final maxV = apps.map((a) => a.$2).fold<int>(1, math.max);
    return Column(
      children: [
        for (final a in apps)
          Semantics(
            label: '${a.$1} ${museBytes(a.$2)}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(a.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.caption(context))),
                      Text(museBytes(a.$2), style: MuseType.caption(context).copyWith(color: mt.text2, fontFeatures: MuseType.tabular)),
                    ],
                  ),
                  const SizedBox(height: MuseSpace.s4),
                  LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: MuseSize.barMin * 2,
                        width: math.max(MuseSize.barMin, c.maxWidth * a.$2 / maxV),
                        decoration: BoxDecoration(color: museBrandOf(context), borderRadius: MuseRadius.fullAll),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
