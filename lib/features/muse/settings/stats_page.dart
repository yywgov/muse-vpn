// 穿云 - 设置 › 统计. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

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
            header: '本月报告',
            dividerIndent: MuseSpace.s16,
            children: [for (final line in report) MuseTile(title: line)],
          ),
          // 1.9.0 #179
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('stats_export_csv'),
                leading: const Icon(Icons.table_chart_outlined),
                title: '导出 CSV',
                subtitle: log.days.isEmpty ? '还没有流量记录' : '每天的上传 / 下载字节数，可用表格软件打开',
                chevron: log.days.isNotEmpty,
                onTap: log.days.isEmpty
                    ? null
                    : () async {
                        final ok = await museSaveTextFile(context, 'chuanyun-traffic.csv', museTrafficCsv(log));
                        if (context.mounted) _toast(ref, ok ? '已导出' : '没有导出');
                      },
              ),
            ],
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
