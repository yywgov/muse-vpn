// 穿云 1.2.3 - 出口检测: which IP / region the traffic leaves from, and whether the services the
// user cares about answer from there. Pure parsing here (tested); the requests live in
// home/exit_card.dart.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

/// One service's verdict from the current exit.
enum MuseServiceState {
  /// still checking
  checking,

  /// reachable and usable
  ok,

  /// reachable, but only partly (Netflix: originals only)
  partial,

  /// the service refuses this region / IP
  blocked,

  /// no answer (timeout, connection error)
  failed,
}

class MuseExitInfo {
  const MuseExitInfo({required this.ip, required this.country});

  final String ip;

  /// ISO 3166 alpha-2, upper case ('' when unknown)
  final String country;
}

/// Cloudflare's /cdn-cgi/trace: `ip=1.2.3.4\nloc=JP\n...`.
MuseExitInfo? museParseCfTrace(String body) {
  final map = <String, String>{};
  for (final line in body.split('\n')) {
    final i = line.indexOf('=');
    if (i > 0) map[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  final ip = map['ip'];
  if (ip == null || ip.isEmpty) return null;
  final loc = (map['loc'] ?? '').toUpperCase();
  return MuseExitInfo(ip: ip, country: RegExp(r'^[A-Z]{2}$').hasMatch(loc) && loc != 'XX' ? loc : '');
}

/// OpenAI's compliance endpoint answers `unsupported_country` (or a VPN notice) from regions
/// ChatGPT does not serve.
MuseServiceState museChatGptVerdict(int? status, String body) {
  if (status == null) return MuseServiceState.failed;
  final b = body.toLowerCase();
  if (b.contains('unsupported_country') || b.contains('unsupported country') || b.contains('vpn')) {
    return MuseServiceState.blocked;
  }
  if (status >= 200 && status < 500) return MuseServiceState.ok;
  return MuseServiceState.failed;
}

/// Netflix: a licensed title (70143836) opens only where the full catalogue is available,
/// an original (81280792) wherever Netflix serves at all.
MuseServiceState museNetflixVerdict(int? licensedStatus, int? originalStatus) {
  if (licensedStatus == null && originalStatus == null) return MuseServiceState.failed;
  if (licensedStatus == 200) return MuseServiceState.ok;
  if (originalStatus == 200) return MuseServiceState.partial;
  if (licensedStatus == 403 || originalStatus == 403 || licensedStatus == 404 || originalStatus == 404) {
    return MuseServiceState.blocked;
  }
  return MuseServiceState.failed;
}

/// Google's 204 check: up or not.
MuseServiceState museGoogleVerdict(int? status) => switch (status) {
  null => MuseServiceState.failed,
  204 || 200 => MuseServiceState.ok,
  _ => MuseServiceState.failed,
};

/// `1.2.3.4` -> `1.2.*.*`, IPv6 keeps its first two groups: enough to tell exits apart on a
/// screen someone else might see.
String museMaskIp(String ip) {
  if (ip.contains('.')) {
    final p = ip.split('.');
    if (p.length == 4) return '${p[0]}.${p[1]}.*.*';
  }
  if (ip.contains(':')) {
    final p = ip.split(':').where((e) => e.isNotEmpty).toList();
    if (p.length >= 2) return '${p[0]}:${p[1]}:…';
  }
  return ip;
}

/// Regions shown by name; others show their code.
const museCountryNames = <String, String>{
  'CN': '中国',
  'HK': '香港',
  'TW': '台湾',
  'MO': '澳门',
  'JP': '日本',
  'KR': '韩国',
  'SG': '新加坡',
  'US': '美国',
  'CA': '加拿大',
  'GB': '英国',
  'DE': '德国',
  'FR': '法国',
  'NL': '荷兰',
  'RU': '俄罗斯',
  'IN': '印度',
  'ID': '印尼',
  'MY': '马来西亚',
  'TH': '泰国',
  'VN': '越南',
  'PH': '菲律宾',
  'AU': '澳大利亚',
  'NZ': '新西兰',
  'TR': '土耳其',
  'AE': '阿联酋',
  'IT': '意大利',
  'ES': '西班牙',
  'CH': '瑞士',
  'SE': '瑞典',
  'BR': '巴西',
  'AR': '阿根廷',
  'MX': '墨西哥',
  'UA': '乌克兰',
  'PL': '波兰',
  'IE': '爱尔兰',
  'FI': '芬兰',
  'NO': '挪威',
  'DK': '丹麦',
  'AT': '奥地利',
  'BE': '比利时',
  'IL': '以色列',
  'ZA': '南非',
};

String museCountryLabel(String code) {
  if (code.isEmpty) return '未知地区';
  return museCountryNames[code] ?? code;
}

String? museCountryFlag(String code) {
  if (code.length != 2) return null;
  final a = code.codeUnitAt(0), b = code.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return null;
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

/// The short word under each service chip.
String museServiceStateLabel(MuseServiceState s, {String partial = '部分'}) => switch (s) {
  MuseServiceState.checking => '检测中',
  MuseServiceState.ok => '可用',
  MuseServiceState.partial => partial,
  MuseServiceState.blocked => '不可用',
  MuseServiceState.failed => '无响应',
};

/// Case-insensitive node search over the name; a region word (日本/JP/东京…) also finds nodes
/// whose name only carries the flag or another spelling of that region.
bool museNodeMatches(String name, String query, {String? Function(String)? regionOf}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final n = name.toLowerCase();
  final words = q.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
  final nodeRegion = regionOf?.call(name);
  for (final w in words) {
    if (n.contains(w)) continue;
    if (nodeRegion != null && regionOf != null) {
      final wRegion = regionOf(w);
      if (wRegion != null && wRegion == nodeRegion) continue;
      if (w.length == 2 && w.toUpperCase() == nodeRegion) continue;
    }
    return false;
  }
  return true;
}
