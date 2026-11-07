// 穿云 - node list: node detail sheet and the 首页 node picker. Split out of node_list.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'node_list.dart';

/// Long-press a node: full name, protocol, latency and when it was measured, with
/// 收藏 / 只测这个节点 / 复制名称 / 使用此节点.
Future<void> showMuseNodeDetails(
  BuildContext context,
  WidgetRef ref,
  OutboundInfo proxy, {
  required DateTime? since,
  required String groupTag,
}) async {
  final name = museNodeName(proxy);
  final running = ref.read(museRunningProvider);
  final isFavorite = museParseFavorites(ref.read(Preferences.museFavoriteNodes)).contains(proxy.tag);
  final delay = museFreshDelay(proxy, since);
  final testedAt = proxy.hasUrlTestTime() ? proxy.urlTestTime.toDateTime() : null;
  final String delayText;
  if (delay == 0) {
    delayText = '未测速';
  } else if (ConnectionConst.isValidDelay(delay)) {
    delayText = '$delay ms';
  } else {
    delayText = MuseFailReason.parse(proxy.urlTestError).title;
  }
  // 1.12.0: why it failed, with one thing to try
  final fail = delay != 0 && !ConnectionConst.isValidDelay(delay) ? MuseFailReason.parse(proxy.urlTestError) : null;
  // 1.4.0: address, landing IP, health from the recent 测速 results
  final metas = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
  final meta = metas.of(proxy.tag);
  final region = metas.regionOf(proxy.tag, museRegionCode(name));
  final history = MuseDelayHistories.parse(ref.read(MusePrefs.delayHistory)).of(proxy.tag);
  final health = museHealthScore(history);
  final exitCode = proxy.hasIpinfo() ? proxy.ipinfo.countryCode : '';
  final mismatch = museRegionMismatch(nameRegion: region, exitRegion: exitCode);
  final invalidError = proxy.isGroup ? '' : museInvalidNodeError(proxy.type);
  // 1.5.0 #26 / #10: transport, TLS, ALPN, fingerprint, port hopping from the saved config
  MuseOutboundDetail? detail;
  var configRaw = '';
  if (!proxy.isGroup && invalidError.isEmpty) {
    try {
      configRaw = await ref.refresh(museActiveConfigProvider.future).timeout(const Duration(seconds: 2));
      detail = museOutboundDetail(configRaw, proxy.tag, host: proxy.host, port: proxy.port);
    } catch (_) {}
  }
  // 1.6.0 #30 / #35: share link (二维码) and the copy formats, named as the row shows the node
  final shownName = metas.displayName(proxy.tag, name, beautify: ref.read(MusePrefs.beautifyNames));
  final shareLink = configRaw.isEmpty ? null : museNodeShareLink(configRaw, proxy.tag, name: shownName);
  // 1.6.0 #36: a relay shows where traffic enters and where it leaves
  final relay = proxy.isGroup ? null : museRelayInfo(name, nameRegion: region, exitCode: exitCode);
  // 1.5.0 #24: 下载测速 for the node (or group) in use
  final inUse = running && ref.read(museNodeGroupProvider).valueOrNull?.selected == proxy.tag;
  final mixedPort = museEffectiveMixedPort(ref.read);
  if (!context.mounted) return;
  final rows = <(String, String)>[
    (
      '类型',
      proxy.isGroup
          ? (museGroupTypeLabel(proxy.type) ?? '分组')
          : invalidError.isNotEmpty
          ? museInvalidNodeSubtitle(proxy.type)
          : museProtocolName(proxy.type),
    ),
    if (relay != null) ...[
      ('入口', relay.entry.isEmpty ? '中转（入口未知）' : '${relay.entry}（中转）'),
      if (relay.exit != null)
        ('出口', '${museCountryFlag(relay.exit!) ?? ''} ${museCountryLabel(relay.exit!)}${relay.exitFromLanding ? '（落地）' : ''}'.trim()),
    ],
    if (region != null)
      ('地区', '${museCountryFlag(region) ?? ''} ${museCountryLabel(region)}${meta.region.isNotEmpty ? '（手动）' : ''}'.trim()),
    ('延迟', delayText),
    if (fail != null) ('建议', fail.advice),
    if (testedAt != null && delay != 0) ('测速时间', museUpdatedAgo(testedAt, now: DateTime.now()).replaceAll('更新', '')),
    if (!proxy.isGroup && proxy.host.isNotEmpty) ('地址', '${proxy.host}${proxy.port > 0 ? ':${proxy.port}' : ''}'),
    ...?detail?.rows,
    if (proxy.hasIpinfo() && proxy.ipinfo.ip.isNotEmpty)
      ('落地', '${proxy.ipinfo.ip} ${museCountryFlag(exitCode) ?? exitCode}${mismatch ? ' · 名不符实' : ''}'.trim()),
    if (history.samples.length >= 2)
      (
        '健康',
        '${museHealthLabel(health)} $health · 丢包 ${(history.loss * 100).round()}% · 抖动 ${history.jitter.round()} ms',
      ),
    if (meta.note.isNotEmpty) ('备注', meta.note),
    if (meta.tags.isNotEmpty) ('标签', meta.tags.join('、')),
  ];
  // 1.6.0 #29: the last 10 delays as a mini line
  final spark = museSparkline(history.samples);
  Future<void> saveMeta(MuseNodeMeta next) async {
    final cur = MuseNodeMetas.parse(ref.read(MusePrefs.nodeMeta));
    await ref.read(MusePrefs.nodeMeta.notifier).update(cur.set(proxy.tag, next).toRaw());
  }

  void toast(String text, {bool error = false}) {
    try {
      final n = ref.read(inAppNotificationControllerProvider);
      error ? n.showErrorToast(text) : n.showSuccessToast(text);
    } catch (_) {}
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: MuseColors.card(context),
    builder: (sheetContext) {
      final mt = MuseTheme.of(sheetContext);
      return SafeArea(
        // 1.5.0: scrolls when the rows don't fit (small phones, large text)
        child: SingleChildScrollView(
          key: const ValueKey('node_detail_sheet'),
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(name, style: MuseType.title(sheetContext)),
              const SizedBox(height: MuseSpace.s12),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: MuseSize.labelColumn, child: Text(k, style: MuseType.body(sheetContext).copyWith(color: mt.text2))),
                      Expanded(child: Text(v, style: MuseType.body(sheetContext))),
                    ],
                  ),
                ),
              // full core error of a node that could not start, selectable and copyable
              if (invalidError.isNotEmpty) ...[
                const SizedBox(height: MuseSpace.s8),
                Container(
                  key: const ValueKey('node_error_box'),
                  padding: const EdgeInsets.all(MuseSpace.s12),
                  decoration: BoxDecoration(color: MusePalette.red.withValues(alpha: 0.08), borderRadius: MuseRadius.smallAll),
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(child: SelectableText(invalidError, style: MuseType.caption(sheetContext))),
                ),
                const SizedBox(height: MuseSpace.s8),
                OutlinedButton.icon(
                  key: const ValueKey('node_copy_error'),
                  icon: const Icon(Icons.copy_all_outlined, size: MuseIconSize.small),
                  label: const Text('复制错误详情'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: '$name\n$invalidError'));
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                    toast('已复制');
                  },
                ),
              ],
              if (spark.length >= 2) ...[
                const SizedBox(height: MuseSpace.s8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: MuseSize.labelColumn,
                      child: Text('最近 ${spark.length} 次', style: MuseType.body(sheetContext).copyWith(color: mt.text2)),
                    ),
                    Expanded(child: MuseSparkline(points: spark)),
                  ],
                ),
              ],
              if (inUse) ...[
                const SizedBox(height: MuseSpace.s8),
                MuseDownloadTestRow(port: mixedPort),
              ],
              const SizedBox(height: MuseSpace.s16),
              if (!proxy.isGroup) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_favorite'),
                        icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outlined, size: MuseIconSize.small),
                        label: Text(isFavorite ? '取消收藏' : '收藏'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final raw = ref.read(Preferences.museFavoriteNodes);
                          await ref.read(Preferences.museFavoriteNodes.notifier).update(museToggleFavorite(raw, proxy.tag));
                        },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_test_one'),
                        icon: const Icon(Icons.speed_outlined, size: MuseIconSize.small),
                        label: const Text('只测这个节点'),
                        onPressed: !running
                            ? null
                            : () async {
                                Navigator.of(sheetContext).pop();
                                try {
                                  // the core tests a single outbound when given its tag
                                  await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(proxy.tag);
                                } catch (_) {
                                  toast('测速失败，请重试', error: true);
                                }
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_rename'),
                        icon: const Icon(Icons.edit_outlined, size: MuseIconSize.small),
                        label: const Text('重命名'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final v = await museAskText(context, '重命名', initial: meta.rename.isEmpty ? name : meta.rename);
                          if (v != null) await saveMeta(meta.copyWith(rename: v == museNodeName(proxy) ? '' : v));
                        },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_note'),
                        icon: const Icon(Icons.sticky_note_2_outlined, size: MuseIconSize.small),
                        label: const Text('备注'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final v = await museAskText(context, '备注', initial: meta.note);
                          if (v != null) await saveMeta(meta.copyWith(note: v));
                        },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_hide'),
                        icon: Icon(meta.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: MuseIconSize.small),
                        label: Text(meta.hidden ? '显示' : '隐藏'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await saveMeta(meta.copyWith(hidden: !meta.hidden));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_set_region'),
                        icon: const Icon(Icons.flag_outlined, size: MuseIconSize.small),
                        label: const Text('指定地区'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final v = await museAskRegion(context, current: meta.region);
                          if (v != null) await saveMeta(meta.copyWith(region: v));
                        },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_set_tags'),
                        icon: const Icon(Icons.sell_outlined, size: MuseIconSize.small),
                        label: const Text('标签'),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          final v = await museAskNodeTags(context, current: meta.tags, known: metas.allTags);
                          if (v != null) await saveMeta(meta.copyWith(tags: v));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s12),
              ],
              if (!proxy.isGroup && invalidError.isEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_qr'),
                        icon: const Icon(Icons.qr_code_2_outlined, size: MuseIconSize.small),
                        label: const Text('二维码'),
                        onPressed: shareLink == null
                            ? null
                            : () async {
                                Navigator.of(sheetContext).pop();
                                await showMuseQrDialog(context, title: shownName, data: shareLink, warning: museQrNodeWarning);
                              },
                      ),
                    ),
                    const SizedBox(width: MuseSpace.s12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('node_copy_as'),
                        icon: const Icon(Icons.ios_share_outlined, size: MuseIconSize.small),
                        label: const Text('复制节点'),
                        onPressed: configRaw.isEmpty
                            ? null
                            : () async {
                                Navigator.of(sheetContext).pop();
                                final copied = await museCopyNodeAs(context, raw: configRaw, tag: proxy.tag, name: shownName);
                                if (copied != null) toast('已复制${copied.label}');
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('node_copy_name'),
                      icon: const Icon(Icons.copy_outlined, size: MuseIconSize.small),
                      label: const Text('复制名称'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: name));
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        toast('已复制');
                      },
                    ),
                  ),
                  const SizedBox(width: MuseSpace.s12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('node_use'),
                      icon: const Icon(Icons.check_outlined, size: MuseIconSize.small),
                      label: const Text('使用此节点'),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await musePickNode(ref, groupTag, proxy.tag);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The node picker opened from the 首页 hero card (works while disconnected too).
Future<void> showMuseNodePicker(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: MuseTheme.of(context).bgBottom,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    builder: (_, controller) => Column(
      key: const ValueKey('node_picker_sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s8),
          child: Text('选择节点', style: MuseType.title(sheetContext)),
        ),
        Expanded(
          child: MuseNodeList(
            controller: controller,
            embedded: true,
            onPicked: () {
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            },
          ),
        ),
      ],
    ),
  ),
);
