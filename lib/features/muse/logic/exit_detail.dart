// 穿云 1.12.0 - 出口 IP 详情：点开出口 IP 卡才查。经当前代理向免费公共接口查询运营商、ASN、
// 城市、IP 类型（机房 / 住宅 / 移动网络，接口能给时）；按 IP 缓存 1 天；并告诉用户和上次比出口
// 有没有变。不用付费接口，失败显示「暂不可用」，不影响出口 IP 卡本身。纯解析在这里（有测试）。
// Part of 穿云 (GPLv3).

import 'dart:convert';

class MuseExitDetail {
  const MuseExitDetail({
    required this.ip,
    this.country = '',
    this.region = '',
    this.city = '',
    this.isp = '',
    this.asn = '',
    this.kind = MuseIpKind.unknown,
    this.at,
  });

  final String ip;

  /// ISO 3166 alpha-2, upper case
  final String country;
  final String region;
  final String city;

  /// 运营商 / 机构
  final String isp;

  /// e.g. AS13335
  final String asn;
  final MuseIpKind kind;
  final DateTime? at;

  bool get isV6 => ip.contains(':');

  String get place => [region, city].where((e) => e.isNotEmpty).toSet().join(' · ');

  Map<String, Object?> toJson() => {
    'ip': ip,
    'c': country,
    'r': region,
    'ci': city,
    'isp': isp,
    'asn': asn,
    'k': kind.name,
    'at': at?.millisecondsSinceEpoch,
  };

  static MuseExitDetail? fromJson(Object? j) {
    if (j is! Map) return null;
    final ip = '${j['ip'] ?? ''}';
    if (ip.isEmpty) return null;
    final at = j['at'];
    return MuseExitDetail(
      ip: ip,
      country: '${j['c'] ?? ''}',
      region: '${j['r'] ?? ''}',
      city: '${j['ci'] ?? ''}',
      isp: '${j['isp'] ?? ''}',
      asn: '${j['asn'] ?? ''}',
      kind: MuseIpKind.values.where((k) => k.name == j['k']).firstOrNull ?? MuseIpKind.unknown,
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }
}

enum MuseIpKind {
  hosting('机房 IP', '数据中心的地址，部分网站（流媒体、AI 服务）可能会限制'),
  residential('住宅 IP', '家庭宽带的地址，通常不会被网站当作代理'),
  mobile('移动网络 IP', '手机运营商的地址'),
  unknown('未知', '');

  const MuseIpKind(this.title, this.hint);

  final String title;
  final String hint;
}

/// 主接口（ip-api.com，`lang=zh-CN`，带 hosting / mobile 标记）的回答。
MuseExitDetail? museParseIpApi(String body, {DateTime? at}) {
  try {
    final j = jsonDecode(body);
    if (j is! Map || j['status'] != 'success') return null;
    final ip = '${j['query'] ?? ''}';
    if (ip.isEmpty) return null;
    final as = '${j['as'] ?? ''}'.trim();
    final asn = RegExp(r'^AS\d+').firstMatch(as)?.group(0) ?? '';
    final kind = j['hosting'] == true
        ? MuseIpKind.hosting
        : j['mobile'] == true
        ? MuseIpKind.mobile
        : (j['hosting'] == false && j['proxy'] != true)
        ? MuseIpKind.residential
        : MuseIpKind.unknown;
    final isp = '${j['isp'] ?? ''}'.trim();
    final org = '${j['org'] ?? ''}'.trim();
    return MuseExitDetail(
      ip: ip,
      country: '${j['countryCode'] ?? ''}'.toUpperCase(),
      region: '${j['regionName'] ?? ''}'.trim(),
      city: '${j['city'] ?? ''}'.trim(),
      isp: isp.isNotEmpty ? isp : org,
      asn: asn,
      kind: kind,
      at: at,
    );
  } catch (_) {
    return null;
  }
}

/// 备用接口（ipwho.is）的回答：没有 IP 类型。
MuseExitDetail? museParseIpWho(String body, {DateTime? at}) {
  try {
    final j = jsonDecode(body);
    if (j is! Map || j['success'] == false) return null;
    final ip = '${j['ip'] ?? ''}';
    if (ip.isEmpty) return null;
    final conn = j['connection'] is Map ? j['connection'] as Map : const {};
    final asnNum = conn['asn'];
    return MuseExitDetail(
      ip: ip,
      country: '${j['country_code'] ?? ''}'.toUpperCase(),
      region: '${j['region'] ?? ''}'.trim(),
      city: '${j['city'] ?? ''}'.trim(),
      isp: '${conn['isp'] ?? conn['org'] ?? ''}'.trim(),
      asn: asnNum == null || '$asnNum'.isEmpty ? '' : 'AS$asnNum',
      at: at,
    );
  } catch (_) {
    return null;
  }
}

/// The detail cache: up to [max] IPs, each kept [maxAge]; plus the last IP looked up.
class MuseExitDetailCache {
  const MuseExitDetailCache({this.byIp = const {}, this.lastIp = ''});

  static const maxAge = Duration(days: 1);
  static const max = 20;

  final Map<String, MuseExitDetail> byIp;
  final String lastIp;

  static MuseExitDetailCache parse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const MuseExitDetailCache();
      final m = j['d'] is Map ? j['d'] as Map : const {};
      return MuseExitDetailCache(
        byIp: {for (final e in m.entries) if (MuseExitDetail.fromJson(e.value) case final d?) '${e.key}': d},
        lastIp: '${j['last'] ?? ''}',
      );
    } catch (_) {
      return const MuseExitDetailCache();
    }
  }

  String toRaw() => jsonEncode({
    'd': {for (final e in byIp.entries) e.key: e.value.toJson()},
    'last': lastIp,
  });

  /// A fresh detail for [ip], or null.
  MuseExitDetail? fresh(String ip, DateTime now) {
    final d = byIp[ip];
    if (d == null || d.at == null || now.difference(d.at!) > maxAge) return null;
    return d;
  }

  /// [d] stored (oldest dropped past [max]) and remembered as the last one.
  MuseExitDetailCache store(MuseExitDetail d) {
    final next = Map<String, MuseExitDetail>.of(byIp)..remove(d.ip);
    next[d.ip] = d;
    while (next.length > max) {
      next.remove(next.keys.first);
    }
    return MuseExitDetailCache(byIp: next, lastIp: d.ip);
  }
}

/// 和上次相比：null = 第一次查；true = 出口变了。
bool? museExitChanged(String previousIp, String ip) => previousIp.isEmpty ? null : previousIp != ip;
