// 穿云 1.19.0 P1 路由弧线图：本机（上海）→ 出口城市；出口位置来自已有的出口 IP 检测（实测）或节点名（按名称），
// 都没有则「出口位置未知」。分类线取已有连接列表 / 统计算出的各类占比，不读接口、不开计时器。
// 1.20.0 首页方向 A：单独的路由卡并入连接卡——地图做连接卡的底（[MuseHeroMap]），图例与一句话路由在地图下方
// （[MuseHeroRouteNotes]，有分类数据时才出现）；原来地图下的「上海 → 东京 · 实测 · 86 ms」说明行与节点行重复，去掉。
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

/// 1.20.0：连接卡上的地图高度（卡宽 / [MuseHomeA.mapAspect]，148–220）。
double museHeroMapHeight(double width) => (width / MuseHomeA.mapAspect).clamp(MuseHomeA.mapMin, MuseHomeA.mapMax);

/// 1.20.0：地图要高亮的国家——出口位置的地区（实测优先，否则按节点名旗帜 / 名称），都没有时按节点名取地区代码。
String? museHeroRegion(MuseExitPlace exit, String? nodeName) =>
    exit.city?.region ?? (nodeName == null ? null : museRegionCode(nodeName));

/// 1.20.0：连接卡的地图——未连接整幅世界全灰、无弧线；已连接按本机 + 节点所在国家取景，只有该国点阵变已连接色。
class MuseHeroMap extends ConsumerWidget {
  const MuseHeroMap({super.key, required this.surface});

  /// 连接卡的底色（城市名描边、高亮色对比度按它算）
  final Color surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final status = ref.watch(museConnectionProvider).valueOrNull;
    final connected = status is Connected;
    final preparing = ref.watch(museConnectPreparingProvider);
    final link = museLinkStateOf(status, preparing: preparing && !connected);
    final group = ref.watch(museNodeGroupProvider).valueOrNull;
    final nodeName = museRouteNodeName(group);
    final measured = ref.watch(museExitProvider.select((r) => r?.info?.country));
    final exit = museResolveExitPlace(nodeName: nodeName, measuredRegion: measured);
    // 只在整数百分比变化时重建
    ref.watch(museRouteShareProvider.select((s) => s.signature));
    final shares = connected ? ref.read(museRouteShareProvider).shares() : const <(MuseRouteKind, double)>[];
    return LayoutBuilder(
      builder: (context, c) => IgnorePointer(
        child: MuseRouteMap(
          key: const ValueKey('home_hero_map'),
          connected: connected,
          connecting: link == MuseLinkState.connecting,
          exit: exit,
          shares: shares,
          height: museHeroMapHeight(c.maxWidth),
          showCaption: false,
          dotColor: mt.text1.withValues(alpha: mt.dark ? MuseHomeA.dotAlphaDark : MuseHomeA.dotAlphaLight),
          surface: surface,
          labelColor: mt.text2,
          centerLon: MuseHomeA.centerLon,
          fit: true,
          highlightRegion: museHeroRegion(exit, nodeName),
          look: MuseMapLook.card,
          baseMask: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [for (final a in MuseHomeA.maskAlpha) MuseHomeA.maskInk.withValues(alpha: a)],
            stops: MuseHomeA.maskStops,
          ),
        ),
      ),
    );
  }
}

/// 1.19.0 分类图例 + 一句话路由（1.20.0 起在连接卡地图下方；没有分类数据时什么都不显示）。
class MuseHeroRouteNotes extends ConsumerWidget {
  const MuseHeroRouteNotes({super.key, required this.padding});

  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final connected = ref.watch(museConnectionProvider).valueOrNull is Connected;
    if (!connected) return const SizedBox.shrink();
    final group = ref.watch(museNodeGroupProvider).valueOrNull;
    final nodeName = museRouteNodeName(group);
    final measured = ref.watch(museExitProvider.select((r) => r?.info?.country));
    final exit = museResolveExitPlace(nodeName: nodeName, measuredRegion: measured);
    ref.watch(museRouteShareProvider.select((s) => s.signature));
    final shares = ref.read(museRouteShareProvider).shares();
    final colors = museRouteKindColors(Theme.of(context).colorScheme);
    // 1.19.0 P4 一句话路由：节点名换成城市名（当前节点用上面判断出的出口城市）
    final sentence = museRouteSentence(
      ref.read(museRouteShareProvider),
      place: (node) => node == nodeName ? exit.city?.name : museCityForNodeName(node)?.name,
      fallbackPlace: exit.city?.name,
    );
    if (shares.isEmpty && sentence == null) return const SizedBox.shrink();
    final caption = MuseTextLevel.footnote.style(context, color: mt.text2);
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 0, padding, MuseSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shares.isNotEmpty)
            Wrap(
              key: const ValueKey('home_route_legend'),
              spacing: MuseSpace.s12,
              runSpacing: MuseSpace.s4,
              children: [
                for (final (kind, share) in shares)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: MuseSpace.s8,
                        height: museRouteShareWidth(share).clamp(2.0, 6.0),
                        decoration: BoxDecoration(color: colors[kind], borderRadius: MuseRadius.fullAll),
                      ),
                      const SizedBox(width: MuseSpace.s4),
                      Text('${kind.label} ${(share * 100).round()}%', style: caption),
                    ],
                  ),
              ],
            ),
          if (sentence != null) ...[
            if (shares.isNotEmpty) const SizedBox(height: MuseSpace.s4),
            Text(
              sentence,
              key: const ValueKey('home_route_sentence'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: caption.copyWith(color: mt.text1),
            ),
          ],
        ],
      ),
    );
  }
}
