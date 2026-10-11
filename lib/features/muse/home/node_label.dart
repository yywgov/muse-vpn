// 穿云 - region badge and labels for node rows.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

/// One-character region badge derived from a node name ("香港 01" -> 港, "🇯🇵 Tokyo" -> 日), or null.
String? museRegionBadge(String name) {
  final flag = _flagCode(name);
  if (flag != null && _byCode[flag] != null) return _byCode[flag];
  for (final (pattern, badge) in _byKeyword) {
    if (pattern.hasMatch(name)) return badge;
  }
  return null;
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

const _byCode = <String, String>{
  'HK': '港', 'TW': '台', 'MO': '澳', 'JP': '日', 'SG': '新', 'US': '美', 'KR': '韩', 'GB': '英', 'UK': '英',
  'DE': '德', 'FR': '法', 'RU': '俄', 'CA': '加', 'AU': '澳', 'IN': '印', 'TR': '土', 'NL': '荷', 'VN': '越',
  'TH': '泰', 'MY': '马', 'PH': '菲', 'ID': '印', 'AR': '阿', 'BR': '巴', 'IT': '意', 'ES': '西', 'CN': '中',
};

final _byKeyword = <(RegExp, String)>[
  (RegExp(r'香港|港|\bHK\b|Hong ?Kong', caseSensitive: false), '港'),
  (RegExp(r'台湾|台灣|台北|\bTW\b|Taiwan', caseSensitive: false), '台'),
  (RegExp(r'澳门|澳門|Macao|Macau'), '澳'),
  (RegExp(r'日本|东京|東京|大阪|\bJP\b|Japan|Tokyo|Osaka', caseSensitive: false), '日'),
  (RegExp(r'新加坡|狮城|獅城|\bSG\b|Singapore', caseSensitive: false), '新'),
  (RegExp(r'美国|美國|洛杉矶|硅谷|西雅图|纽约|圣何塞|\bUS\b|\bUSA\b|United States|America', caseSensitive: false), '美'),
  (RegExp(r'韩国|韓國|首尔|\bKR\b|Korea|Seoul', caseSensitive: false), '韩'),
  (RegExp(r'英国|英國|伦敦|\bUK\b|\bGB\b|London|United Kingdom', caseSensitive: false), '英'),
  (RegExp(r'德国|德國|法兰克福|\bDE\b|Germany|Frankfurt', caseSensitive: false), '德'),
  (RegExp(r'法国|法國|巴黎|\bFR\b|France|Paris', caseSensitive: false), '法'),
  (RegExp(r'俄罗斯|俄羅斯|莫斯科|\bRU\b|Russia', caseSensitive: false), '俄'),
  (RegExp(r'加拿大|\bCA\b|Canada', caseSensitive: false), '加'),
  (RegExp(r'澳大利亚|澳洲|悉尼|\bAU\b|Australia|Sydney', caseSensitive: false), '澳'),
  (RegExp(r'印度|\bIN\b|India', caseSensitive: false), '印'),
  (RegExp(r'土耳其|\bTR\b|Turkey', caseSensitive: false), '土'),
  (RegExp(r'荷兰|荷蘭|\bNL\b|Netherlands', caseSensitive: false), '荷'),
  (RegExp(r'越南|\bVN\b|Vietnam', caseSensitive: false), '越'),
  (RegExp(r'泰国|泰國|\bTH\b|Thailand', caseSensitive: false), '泰'),
  (RegExp(r'马来|馬來|\bMY\b|Malaysia', caseSensitive: false), '马'),
  (RegExp(r'菲律宾|\bPH\b|Philippines', caseSensitive: false), '菲'),
  (RegExp(r'阿根廷|\bAR\b|Argentina', caseSensitive: false), '阿'),
];

/// Readable name of a proxy group type.
String? museGroupTypeLabel(String type) => switch (type.toLowerCase()) {
  'urltest' || 'url-test' => '自动最快',
  'selector' || 'select' => '手动选择',
  'loadbalance' || 'load-balance' || 'balancer' || 'round-robin' => '负载均衡',
  'fallback' => '故障转移',
  _ => null,
};
