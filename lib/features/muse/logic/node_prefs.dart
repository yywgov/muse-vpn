// 穿云 1.2.8 - node list helpers (pure, unit-tested): 非节点条目过滤, 收藏置顶, 每个订阅记住上次的节点,
// 去广告 温和 / 强力.
// Part of 穿云 (GPLv3).

import 'dart:convert';

import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

// ---------------------------------------------------------------- 非节点条目

/// Words that mark a subscription's info line posing as a node
/// (「剩余流量：12 GB」「套餐到期：2026-12-01」「官网 xxx.com」…).
const museInfoNodeWords = [
  '剩余流量',
  '已用流量',
  '流量重置',
  '下次重置',
  '距离下次',
  '到期',
  '过期',
  '有效期',
  '官网',
  '网址',
  '套餐',
  '公告',
  '客服',
  '交流群',
  '续费',
  '最新地址',
  '发布页',
  'expire',
  'remaining',
  'traffic',
  'website',
];

/// Whether [name] is a subscription info line rather than a real node.
bool museIsInfoNode(String name) {
  final n = name.toLowerCase();
  return museInfoNodeWords.any(n.contains);
}

// ---------------------------------------------------------------- 收藏

/// Stored as one tag per line.
Set<String> museParseFavorites(String raw) => raw.split('\n').where((e) => e.isNotEmpty).toSet();

String museToggleFavorite(String raw, String tag) {
  final s = museParseFavorites(raw);
  if (!s.remove(tag)) s.add(tag);
  return s.join('\n');
}

/// Groups first (as they came), then favourites, then the rest; each part keeps [items]' order.
List<T> museFavoritesFirst<T>(
  List<T> items, {
  required bool Function(T) isGroup,
  required String Function(T) tag,
  required Set<String> favorites,
}) {
  if (favorites.isEmpty) return items;
  return [
    ...items.where(isGroup),
    ...items.where((e) => !isGroup(e) && favorites.contains(tag(e))),
    ...items.where((e) => !isGroup(e) && !favorites.contains(tag(e))),
  ];
}

// ---------------------------------------------------------------- 每个订阅记住上次的节点

/// `{profileId: tag}` as JSON; anything unreadable is an empty map.
Map<String, String> museParseLastNodes(String raw) {
  try {
    final m = jsonDecode(raw);
    if (m is Map) return {for (final e in m.entries) '${e.key}': '${e.value}'};
  } catch (_) {}
  return {};
}

/// Remembers [tag] for [profileId]; keeps at most 50 subscriptions.
String museRememberNode(String raw, String profileId, String tag) {
  final m = museParseLastNodes(raw)
    ..remove(profileId)
    ..[profileId] = tag;
  final keep = m.entries.toList();
  final trimmed = keep.length > 50 ? keep.sublist(keep.length - 50) : keep;
  return jsonEncode({for (final e in trimmed) e.key: e.value});
}

/// The node to bring back for [profileId], or null when nothing is saved, it is already
/// selected, or the subscription no longer has it.
String? museNodeToRestore(String raw, String profileId, {required String selected, required Iterable<String> tags}) {
  final saved = museParseLastNodes(raw)[profileId];
  if (saved == null || saved == selected) return null;
  return tags.contains(saved) ? saved : null;
}

// ---------------------------------------------------------------- 去广告 温和 / 强力

enum MuseAdBlockLevel {
  // 1.3.0: 关 (the malware / phishing lists stay on)
  off('off', '关', '不拦广告，恶意和钓鱼网站仍会拦截'),
  gentle('gentle', '温和', '只拦明确的广告和追踪域名，不影响 App 正常使用（推荐）'),
  strong('strong', '强力', '使用完整广告规则库，拦得更多，个别 App 可能打不开');

  const MuseAdBlockLevel(this.key, this.title, this.explain);

  final String key;
  final String title;
  final String explain;

  static MuseAdBlockLevel fromKey(String key) =>
      values.firstWhere((e) => e.key == key, orElse: () => MuseAdBlockLevel.gentle);
}

/// 温和: well-known ad / tracking domains only (none that apps need to work).
const museGentleAdDomains = [
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'google-analytics.com',
  'adservice.google.com',
  'pagead2.googlesyndication.com',
  'admob.com',
  'adnxs.com',
  'adsrvr.org',
  'criteo.com',
  'criteo.net',
  'taboola.com',
  'outbrain.com',
  'pubmatic.com',
  'rubiconproject.com',
  'openx.net',
  'moatads.com',
  'scorecardresearch.com',
  'quantserve.com',
  'adcolony.com',
  'applovin.com',
  'unityads.unity3d.com',
  'inmobi.com',
  'mopub.com',
  'ads.yahoo.com',
  'analytics.yahoo.com',
  'ads.twitter.com',
  'ads-api.twitter.com',
  'an.facebook.com',
  'ads.tiktok.com',
  'analytics.tiktok.com',
  'pangolin-sdk-toutiao.com',
  'pglstatp-toutiao.com',
  'gdt.qq.com',
  'e.qq.com',
  'mmstat.com',
  'tanx.com',
  'cpro.baidu.com',
  'pos.baidu.com',
  'hm.baidu.com',
  'cnzz.com',
  'adkwai.com',
];

/// The 去广告 rule for [level]: 强力 keeps the full ad rule-set; 温和 drops it and adds a separate
/// block rule for the [museGentleAdDomains] list right after (a rule of its own, so it never
/// depends on how domain lists and rule-sets combine). The malware / phishing lists stay in both.
List<Rule> museApplyAdBlockLevel(List<Rule> rules, MuseAdBlockLevel level) {
  if (level == MuseAdBlockLevel.strong) return rules;
  final out = <Rule>[];
  for (final r in rules) {
    if (r.name != 'builtin:blockAds') {
      out.add(r);
      continue;
    }
    final rest = r.deepCopy()..ruleSets.removeWhere((s) => s.contains('category-ads'));
    if (level == MuseAdBlockLevel.off) {
      // a rule left with nothing to match is dropped rather than sent to the core
      if (rest.ruleSets.isNotEmpty) out.add(rest);
      continue;
    }
    out.add(rest);
    out.add(
      Rule(
        name: 'builtin:blockAds:gentle',
        listOrder: r.listOrder,
        enabled: r.enabled,
        outbound: r.outbound,
        domainSuffixes: museGentleAdDomains,
      ),
    );
  }
  return out;
}
