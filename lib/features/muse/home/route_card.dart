// 穿云 1.19.0 P1 新首页顶部的路由弧线图卡片：本机（上海）→ 出口城市；出口位置来自已有的出口 IP 检测
// （实测）或节点名（按名称），都没有则「出口位置未知」。分类线取已有连接列表 / 统计算出的各类占比，
// 本卡不读接口、不开计时器。
// Part of 穿云 (GPLv3).

part of 'muse_home_page.dart';

/// 当前节点用来判断出口城市的名字（分组取它选中的那个）。
String? museRouteNodeName(OutboundGroup? group) {
  final item = group?.items.where((e) => e.tag == group.selected).firstOrNull;
  if (item == null) return null;
  if (item.isGroup) {
    final sel = item.groupSelectedTagDisplay.trim();
    return sel.isEmpty ? museNodeName(item) : sel;
  }
  return museNodeName(item);
}

class MuseRouteCard extends ConsumerWidget {
  const MuseRouteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(museConnectionProvider).valueOrNull;
    final connected = status is Connected;
    final preparing = ref.watch(museConnectPreparingProvider);
    final link = museLinkStateOf(status, preparing: preparing && !connected);
    final connecting = link == MuseLinkState.connecting;
    final nodeName = museRouteNodeName(ref.watch(museNodeGroupProvider).valueOrNull);
    final measured = ref.watch(museExitProvider.select((r) => r?.info?.country));
    final exit = museResolveExitPlace(nodeName: nodeName, measuredRegion: measured);
    // 只在整数百分比变化时重建
    ref.watch(museRouteShareProvider.select((s) => s.signature));
    final shares = connected ? ref.read(museRouteShareProvider).shares() : const <(MuseRouteKind, double)>[];
    final colors = museRouteKindColors(Theme.of(context).colorScheme);
    return MuseCard(
      key: const ValueKey('home_route_card'),
      padding: const EdgeInsets.fromLTRB(MuseSpace.s12, MuseSpace.s12, MuseSpace.s12, MuseSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MuseRouteMap(connected: connected, connecting: connecting, exit: exit, shares: shares),
          if (shares.isNotEmpty) ...[
            const SizedBox(height: MuseSpace.s4),
            Wrap(
              key: const ValueKey('home_route_legend'),
              alignment: WrapAlignment.center,
              spacing: MuseSpace.s12,
              runSpacing: MuseSpace.s4,
              children: [
                for (final (kind, share) in shares)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: museRouteShareWidth(share).clamp(2.0, 6.0),
                        decoration: BoxDecoration(color: colors[kind], borderRadius: MuseRadius.fullAll),
                      ),
                      const SizedBox(width: MuseSpace.s4),
                      Text(
                        '${kind.label} ${(share * 100).round()}%',
                        style: MuseType.caption(context).copyWith(fontFeatures: MuseType.tabular),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
