// 穿云 - labels for node rows: region flags, Chinese group names (the one mapping every screen
// uses), and the node order.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
//
// The Android notification has a copy of the group-name table in
// android/.../bg/ChuanyunLabels.kt (native code can't call Dart); keep the two in step.

/// ISO 3166 code of the region a node name points at ("香港 01" -> HK, "🇯🇵 Tokyo" -> JP), or null.
String? museRegionCode(String name) {
  final flag = _flagCode(name);
  if (flag != null) return flag == 'UK' ? 'GB' : flag;
  for (final (pattern, code) in _byKeyword) {
    if (pattern.hasMatch(name)) return code;
  }
  return null;
}

/// Flag emoji for a node name ("香港 01" -> 🇭🇰), or null when no region is recognised (show a globe).
String? museFlagEmoji(String name) {
  final code = museRegionCode(name);
  if (code == null || code.length != 2) return null;
  final a = code.codeUnitAt(0), b = code.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return null;
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

String? _flagCode(String name) {
  final runes = name.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final a = runes[i], b = runes[i + 1];
    if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
      return String.fromCharCodes([a - 0x1F1E6 + 65, b - 0x1F1E6 + 65]);
    }
  }
  return null;
}

// Order matters: more specific names first (澳门 before 澳洲, 印尼 before 印度 …).
final _byKeyword = <(RegExp, String)>[
  (RegExp(r'香港|\bHK\b|\bHKG\b|Hong ?Kong', caseSensitive: false), 'HK'),
  (RegExp(r'台湾|台灣|台北|新北|彰化|\bTW\b|Taiwan|Taipei', caseSensitive: false), 'TW'),
  (RegExp(r'澳门|澳門|Macao|Macau', caseSensitive: false), 'MO'),
  (RegExp(r'日本|东京|東京|大阪|埼玉|\bJP\b|Japan|Tokyo|Osaka', caseSensitive: false), 'JP'),
  (RegExp(r'新加坡|狮城|獅城|\bSG\b|Singapore', caseSensitive: false), 'SG'),
  (RegExp(r'美国|美國|洛杉矶|硅谷|西雅图|纽约|圣何塞|芝加哥|达拉斯|凤凰城|\bUS\b|\bUSA\b|United States|America|Los ?Angeles|San ?Jose|Seattle', caseSensitive: false), 'US'),
  (RegExp(r'韩国|韓國|首尔|首爾|春川|\bKR\b|Korea|Seoul', caseSensitive: false), 'KR'),
  (RegExp(r'英国|英國|伦敦|倫敦|\bUK\b|\bGB\b|London|United Kingdom|Britain', caseSensitive: false), 'GB'),
  (RegExp(r'德国|德國|法兰克福|\bDE\b|Germany|Frankfurt', caseSensitive: false), 'DE'),
  (RegExp(r'法国|法國|巴黎|\bFR\b|France|Paris', caseSensitive: false), 'FR'),
  (RegExp(r'俄罗斯|俄羅斯|莫斯科|\bRU\b|Russia|Moscow', caseSensitive: false), 'RU'),
  (RegExp(r'加拿大|多伦多|温哥华|\bCA\b|Canada|Toronto|Vancouver', caseSensitive: false), 'CA'),
  (RegExp(r'澳大利亚|澳洲|悉尼|墨尔本|\bAU\b|Australia|Sydney|Melbourne', caseSensitive: false), 'AU'),
  (RegExp(r'印尼|印度尼西亚|雅加达|Indonesia|Jakarta', caseSensitive: false), 'ID'),
  (RegExp(r'印度|孟买|India|Mumbai', caseSensitive: false), 'IN'),
  (RegExp(r'土耳其|\bTR\b|Turkey|Türkiye|Istanbul', caseSensitive: false), 'TR'),
  (RegExp(r'荷兰|荷蘭|阿姆斯特丹|\bNL\b|Netherlands|Amsterdam', caseSensitive: false), 'NL'),
  (RegExp(r'越南|\bVN\b|Vietnam', caseSensitive: false), 'VN'),
  (RegExp(r'泰国|泰國|曼谷|\bTH\b|Thailand|Bangkok', caseSensitive: false), 'TH'),
  (RegExp(r'马来|馬來|吉隆坡|\bMY\b|Malaysia|Kuala', caseSensitive: false), 'MY'),
  (RegExp(r'菲律宾|菲律賓|马尼拉|\bPH\b|Philippines|Manila', caseSensitive: false), 'PH'),
  (RegExp(r'阿根廷|\bAR\b|Argentina', caseSensitive: false), 'AR'),
  (RegExp(r'巴西|\bBR\b|Brazil', caseSensitive: false), 'BR'),
  (RegExp(r'意大利|義大利|米兰|Italy|Milan', caseSensitive: false), 'IT'),
  (RegExp(r'西班牙|马德里|Spain|Madrid', caseSensitive: false), 'ES'),
  (RegExp(r'瑞士|Switzerland|Zurich', caseSensitive: false), 'CH'),
  (RegExp(r'瑞典|Sweden|Stockholm', caseSensitive: false), 'SE'),
  (RegExp(r'波兰|Poland|Warsaw', caseSensitive: false), 'PL'),
  (RegExp(r'爱尔兰|愛爾蘭|Ireland|Dublin', caseSensitive: false), 'IE'),
  (RegExp(r'阿联酋|迪拜|\bUAE\b|Dubai|Emirates', caseSensitive: false), 'AE'),
  (RegExp(r'以色列|Israel', caseSensitive: false), 'IL'),
  (RegExp(r'南非|South Africa', caseSensitive: false), 'ZA'),
  (RegExp(r'墨西哥|Mexico', caseSensitive: false), 'MX'),
  (RegExp(r'智利|Chile', caseSensitive: false), 'CL'),
  (RegExp(r'乌克兰|烏克蘭|Ukraine', caseSensitive: false), 'UA'),
  (RegExp(r'芬兰|Finland', caseSensitive: false), 'FI'),
  (RegExp(r'挪威|Norway', caseSensitive: false), 'NO'),
  (RegExp(r'丹麦|Denmark', caseSensitive: false), 'DK'),
  (RegExp(r'奥地利|Austria|Vienna', caseSensitive: false), 'AT'),
  (RegExp(r'柬埔寨|Cambodia', caseSensitive: false), 'KH'),
  (RegExp(r'哈萨克|Kazakhstan', caseSensitive: false), 'KZ'),
  (RegExp(r'蒙古|Mongolia', caseSensitive: false), 'MN'),
  (RegExp(r'尼日利亚|Nigeria', caseSensitive: false), 'NG'),
  (RegExp(r'埃及|Egypt', caseSensitive: false), 'EG'),
  (RegExp(r'沙特|Saudi', caseSensitive: false), 'SA'),
  (RegExp(r'新西兰|紐西蘭|New Zealand', caseSensitive: false), 'NZ'),
  (RegExp(r'中国|中國|大陆|回国|China', caseSensitive: false), 'CN'),
];

/// Strategy names the core reports for a load balancer (shown instead of a node).
const _balanceStrategies = <String, String>{
  'round-robin': '轮询',
  'consistent-hashing': '一致性哈希',
  'consistent-hash': '一致性哈希',
  'sticky-sessions': '粘性会话',
  'sticky-session': '粘性会话',
  'random': '随机',
};

String _bareType(String type) => type.split('→').first.trim().toLowerCase();

/// Chinese name for a common English group/outbound name ("lowest" -> 自动最快), or null.
String? museKnownGroupName(String name) {
  final n = name.trim().toLowerCase();
  return switch (n) {
    'lowest' || 'lowest-delay' || 'auto' || 'fastest' || 'urltest' || 'url-test' || 'best' => '自动最快',
    'balance' || 'balancer' || 'loadbalance' || 'load-balance' || 'round-robin' => '负载均衡',
    'select' || 'selector' || 'proxy' || 'proxies' || 'manual' => '手动选择',
    'fallback' || 'failover' => '故障切换',
    'direct' => '直连',
    'block' || 'reject' => '拦截',
    _ => null,
  };
}

/// Chinese name of a load-balancer strategy ("round-robin" -> 轮询), or null.
String? museBalanceStrategyName(String strategy) => _balanceStrategies[strategy.trim().toLowerCase()];

/// How a group behaves, in plain Chinese: 自动最快 / 负载均衡 / 手动选择 / 故障切换 (null for non-groups).
///
/// The core reports a load balancer as type "Balancer"; with the lowest-delay strategy it
/// picks the fastest node (and reports that node), otherwise it reports the strategy name.
String? museGroupKind({required String type, required String name, String? selectedDisplay}) {
  final t = _bareType(type);
  final sel = selectedDisplay?.trim().toLowerCase() ?? '';
  switch (t) {
    case 'urltest' || 'url-test':
      return '自动最快';
    case 'selector' || 'select':
      return '手动选择';
    case 'fallback':
      return '故障切换';
    case 'balancer' || 'loadbalance' || 'load-balance' || 'round-robin':
      if (sel == 'lowest-delay') return '自动最快';
      if (_balanceStrategies.containsKey(sel)) return '负载均衡';
      if (sel.isNotEmpty) return '自动最快'; // lowest-delay balancer reports the node it picked
      return museKnownGroupName(name) == '自动最快' ? '自动最快' : '负载均衡';
  }
  return null;
}

/// Display name for a group row/title: common English names become Chinese, user names stay.
String museGroupName(String name) => museKnownGroupName(name) ?? name;

/// Subtitle of a group row on the 首页: the node 自动最快 picked (just its name), the node count
/// for a balancer (1.2.1: 「负载均衡 · 轮询」 only repeated the row title), 「手动选择 → 节点」
/// for a selector.
String museGroupSubtitle({
  required String type,
  required String name,
  String? selectedDisplay,
  int? nodeCount,
  String Function(String raw)? shown,
}) {
  final kind = museGroupKind(type: type, name: name, selectedDisplay: selectedDisplay) ?? '分组';
  final sel = selectedDisplay?.trim() ?? '';
  if (kind == '负载均衡') return nodeCount != null && nodeCount > 0 ? '$nodeCount 个节点' : '';
  if (sel.isEmpty || sel.toLowerCase() == 'lowest-delay') return kind;
  // 1.5.3: the pick reads like its own row (renamed / tidied)
  final node = museKnownGroupName(sel) ?? (shown == null ? sel : shown(sel));
  // 1.1: 「自动最快 → 节点」 repeated the row title; only the node is shown
  if (kind == '自动最快') return node;
  return '$kind → $node';
}

/// 1.2.1: each group kind has its own icon (负载均衡 used to share 自动最快's lightning).
enum MuseGroupIcon { autoFastest, loadBalance, manual, fallback, other }

MuseGroupIcon museGroupIconKind({required String type, required String name, String? selectedDisplay}) =>
    switch (museGroupKind(type: type, name: name, selectedDisplay: selectedDisplay)) {
      '自动最快' => MuseGroupIcon.autoFastest,
      '负载均衡' => MuseGroupIcon.loadBalance,
      '手动选择' => MuseGroupIcon.manual,
      '故障切换' => MuseGroupIcon.fallback,
      _ => MuseGroupIcon.other,
    };

/// The core's "current outbound" text ("lowest → 香港 01", "balance→round-robin", "香港 01")
/// in Chinese: 「自动最快 · 香港 01」 / 「负载均衡 · 轮询」 / 「香港 01」.
String museCurrentOutboundLabel(String raw) {
  final parts = raw.split(RegExp(r'\s*→\s*')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return raw;
  if (parts.length == 1) return museGroupName(parts.first);
  final group = parts.first;
  final selected = parts.last;
  final strategy = museBalanceStrategyName(selected);
  if (strategy != null) return '负载均衡 · $strategy';
  var groupName = museGroupName(group);
  // a lowest-delay balancer reports the node it picked, whatever the group is called
  if (groupName == '负载均衡') groupName = '自动最快';
  if (selected.toLowerCase() == 'lowest-delay') return groupName;
  return '$groupName · ${museGroupName(selected)}';
}

/// Readable name of a proxy group type.
String? museGroupTypeLabel(String type) => switch (_bareType(type)) {
  'urltest' || 'url-test' => '自动最快',
  'selector' || 'select' => '手动选择',
  'loadbalance' || 'load-balance' || 'balancer' || 'round-robin' => '负载均衡',
  'fallback' => '故障切换',
  _ => null,
};

/// 1.1 node order on the 首页: groups (自动最快, 负载均衡 …) first in their own order, then nodes by
/// latency (fastest first); nodes not tested yet follow, timed-out nodes go to the bottom. The sort
/// is stable, so equal nodes keep the subscription's order.
List<T> museSortNodes<T>(
  List<T> items, {
  required bool Function(T) isGroup,
  required int Function(T) delay,
  required bool Function(int) isValidDelay,
}) {
  int rank(T e) {
    if (isGroup(e)) return 0;
    final d = delay(e);
    if (d > 0 && isValidDelay(d)) return 1;
    if (d == 0) return 2; // not tested yet
    return 3; // timed out
  }

  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final ra = rank(a.$2), rb = rank(b.$2);
    if (ra != rb) return ra.compareTo(rb);
    if (ra == 1) {
      final c = delay(a.$2).compareTo(delay(b.$2));
      if (c != 0) return c;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
