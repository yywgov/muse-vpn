// 穿云 1.2.5 - node list order (延迟 / 订阅顺序 / 按地区) and the region sections, pure for tests.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/features/muse/home/node_label.dart';

/// How 首页 orders the nodes; stored as [key] in the `muse_node_sort` preference.
enum MuseNodeSort {
  /// fastest first, untested next, timeouts last (the 1.1 – 1.2.4 order)
  delay('delay'),

  /// as the subscription lists them
  original('original'),

  /// grouped by region (first appearance order), fastest first inside a region
  region('region');

  const MuseNodeSort(this.key);

  final String key;

  static MuseNodeSort fromKey(String key) =>
      MuseNodeSort.values.firstWhere((e) => e.key == key, orElse: () => MuseNodeSort.delay);

  String get title => switch (this) {
    delay => '按延迟',
    original => '订阅顺序',
    region => '按地区',
  };
}

/// [items] in the order [sort] asks for. Groups (自动最快 …) always stay on top.
/// [region] gives a node's region code (null = not recognised, those go last as 其他).
List<T> museOrderNodes<T>(
  List<T> items, {
  required MuseNodeSort sort,
  required bool Function(T) isGroup,
  required int Function(T) delay,
  required bool Function(int) isValidDelay,
  required String? Function(T) region,
}) {
  switch (sort) {
    case MuseNodeSort.original:
      return [...items.where(isGroup), ...items.where((e) => !isGroup(e))];
    case MuseNodeSort.delay:
      return museSortNodes<T>(items, isGroup: isGroup, delay: delay, isValidDelay: isValidDelay);
    case MuseNodeSort.region:
      final byDelay = museSortNodes<T>(items, isGroup: isGroup, delay: delay, isValidDelay: isValidDelay);
      // region order: as they first appear in the subscription; unrecognised last
      final order = <String?>[];
      for (final e in items) {
        if (isGroup(e)) continue;
        final r = region(e);
        if (r != null && !order.contains(r)) order.add(r);
      }
      order.add(null);
      return [
        ...byDelay.where(isGroup),
        for (final r in order) ...byDelay.where((e) => !isGroup(e) && region(e) == r),
      ];
  }
}

/// Consecutive runs of the same region in an already ordered list: where 「🇭🇰 香港 · 5」 headers
/// go in 按地区 mode. Groups are left out (no header). Each section holds the items in order.
List<({String? region, List<T> items})> museRegionSections<T>(
  List<T> ordered, {
  required bool Function(T) isGroup,
  required String? Function(T) region,
}) {
  final sections = <({String? region, List<T> items})>[];
  for (final e in ordered) {
    if (isGroup(e)) continue;
    final r = region(e);
    if (sections.isNotEmpty && sections.last.region == r) {
      sections.last.items.add(e);
    } else {
      sections.add((region: r, items: [e]));
    }
  }
  return sections;
}

/// Short byte size for 首页 / 订阅 lines: 512 B, 12 KB, 3.4 MB, 12.3 GB, 120 GB.
String museBytes(int value) {
  final bytes = value < 0 ? 0 : value;
  const k = 1024;
  if (bytes < k) return '$bytes B';
  if (bytes < k * k) return '${(bytes / k).toStringAsFixed(0)} KB';
  if (bytes < k * k * k) {
    final mb = bytes / (k * k);
    return '${mb >= 100 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1)} MB';
  }
  final gb = bytes / (k * k * k);
  return '${gb >= 100 ? gb.toStringAsFixed(0) : gb.toStringAsFixed(1)} GB';
}

/// The one-line summary under a subscription's bar on 配置 (Clash Verge Rev style):
/// 「已用 12.3 GB / 100 GB · 剩 23 天 · 3 小时前更新」. Parts the subscription doesn't report are left
/// out; a cap above 10 TB counts as unlimited, an expiry more than 10 years away as none.
String museSubscriptionSummary({
  required int upload,
  required int download,
  required int total,
  required DateTime expire,
  required DateTime lastUpdate,
  required DateTime now,
}) {
  final parts = <String>[];
  const tenTB = 10 * 1024 * 1024 * 1024 * 1024;
  if (total > 0 && total <= tenTB) {
    final used = upload + download;
    parts.add(used >= total ? '流量已用完' : '已用 ${museBytes(used)} / ${museBytes(total)}');
  }
  final year = expire.year;
  if (year > 1971 && year < 2100) {
    final left = expire.difference(now);
    if (left.isNegative || left == Duration.zero) {
      parts.add('已到期');
    } else if (left.inDays < 1) {
      parts.add('今天到期');
    } else if (left.inDays <= 3650) {
      parts.add('剩 ${left.inDays} 天');
    }
  }
  parts.add(museUpdatedAgo(lastUpdate, now: now));
  return parts.join(' · ');
}

/// 「刚刚更新」/「5 分钟前更新」/「3 小时前更新」/「2 天前更新」.
String museUpdatedAgo(DateTime at, {required DateTime now}) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return '刚刚更新';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前更新';
  if (d.inDays < 1) return '${d.inHours} 小时前更新';
  return '${d.inDays} 天前更新';
}

/// What the 首页 「当前节点」 line says: the node, or for a group the group and what it picked
/// (「自动最快 → 🇯🇵 东京 02」). Empty when nothing is selected.
String museCurrentNodeText({required String name, String groupPick = '', String? groupLabel}) {
  if (name.isEmpty) return '';
  String withFlag(String n) {
    final flag = museFlagEmoji(n);
    return flag == null || n.contains(flag) ? n : '$flag $n';
  }

  if (groupLabel != null) {
    final pick = groupPick.trim();
    return pick.isEmpty ? groupLabel : '$groupLabel → ${withFlag(pick)}';
  }
  return withFlag(name);
}
