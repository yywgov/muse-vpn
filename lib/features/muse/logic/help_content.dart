// 穿云 1.9.0 (batch 2) - the text of 设置 › 帮助与隐私 (offline, ships with the app, so it always
// matches this version): plain-words glossary (#234 / #135 / #238), what is stored and what is
// never sent (#192), plus small helpers for the 1.9.0 settings (pure logic, unit-tested).
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/logic/stats_tools.dart';

/// One glossary card: the word as the app shows it, and what it means in one or two sentences.
class MuseTerm {
  const MuseTerm(this.term, this.meaning, {this.also = const []});

  final String term;
  final String meaning;

  /// other names people look it up by (for search)
  final List<String> also;
}

/// The words used across the app, in the order they are met. One term = one word everywhere:
/// 节点 (a server), 订阅 (a list of nodes from a link), 规则 / 全局 (模式), 分流 (which traffic goes where).
const museGlossary = <MuseTerm>[
  MuseTerm('节点', '一台能帮你连上外网的服务器。订阅里有很多个，点一个就用它。', also: ['服务器', '线路']),
  MuseTerm('订阅', '服务商给你的一条链接，穿云从里面取回节点列表，并按设置定时更新。', also: ['机场', '链接']),
  MuseTerm('规则模式', '按分流规则决定：国内网站直连，需要的网站走节点，其他按预设处理。平时用这个。', also: ['规则']),
  MuseTerm('全局模式', '所有流量都走当前节点，不看规则。排查问题或规则不准时临时用。', also: ['全局']),
  MuseTerm('分流', '决定某个网站或应用走节点、直连还是被拦截。可在「分流」里用预设或自己加规则。', also: ['路由', '规则']),
  MuseTerm('系统代理', '只让支持代理的软件（浏览器等）走穿云，Windows 默认用它，不需要管理员权限。', also: ['代理']),
  MuseTerm('TUN 模式', '建一块虚拟网卡，让整台电脑（含不支持代理的软件和游戏）都经过穿云。Windows 需要管理员权限。', also: ['虚拟网卡', 'VPN']),
  MuseTerm('延迟', '到节点再返回所需的时间，越小越快；「超时」表示这次没连通，不一定永远不能用。', also: ['ping', '测速']),
  MuseTerm('出口 IP', '网站看到的你的地址，也就是节点所在的位置，用来确认真的走了节点。', also: ['落地', 'IP']),
  MuseTerm('DNS', '把网址翻译成服务器地址的服务。国内网址用国内 DNS，其他网址用远程 DNS，避免被污染。', also: ['域名解析']),
  MuseTerm('Fake-IP', '先给每个域名一个临时假地址，由节点那边再去真正解析，能减少 DNS 泄漏。默认关，在「高级」里。', also: ['假 IP']),
  MuseTerm('内核', '真正转发流量的程序。标准内核适合绝大多数订阅；兼容内核用来原样使用订阅里的代理组和规则。', also: ['核心']),
  MuseTerm('去广告', '在本机拦截已知广告和追踪域名：温和档误拦少，强力档拦得多但个别 App 可能打不开。', also: ['广告']),
];

/// Glossary cards matching [query] (term, meaning or other names), all of them for an empty query.
List<MuseTerm> museGlossarySearch(String query, {List<MuseTerm> terms = museGlossary}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return terms;
  return [
    for (final t in terms)
      if (t.term.toLowerCase().contains(q) || t.meaning.toLowerCase().contains(q) || t.also.any((a) => a.toLowerCase().contains(q))) t,
  ];
}

/// What 穿云 keeps on the device and what it never sends (shown on 帮助与隐私).
const musePrivacyStored = <(String, String)>[
  ('订阅和节点', '只保存在本机。订阅链接含密钥，界面里默认打码，导出的日志和诊断也会打码。'),
  ('设置、规则、收藏', '保存在本机；只有你开启同步（局域网或 WebDAV）才会发给你自己的设备或网盘，并且加密。'),
  ('流量统计、连接记录', '只在本机，用来画图表和月报，不会上传。'),
  ('崩溃记录', '只在本机；你点「反馈问题」时才会复制出来，由你决定发不发。'),
];

const musePrivacyNever = <String>[
  '不收集使用习惯，没有统计 SDK，没有广告。',
  '不上传你访问的网站、订阅、节点或日志。',
  '联网只做你要它做的事：下载订阅、检查更新、测速、检测出口 IP。',
];

/// 1.9.0 #179: the traffic log as CSV (日期,上传,下载,合计 — bytes), oldest day first.
String museTrafficCsv(MuseTrafficLog log) {
  final keys = log.days.keys.toList()..sort();
  final b = StringBuffer('日期,上传(字节),下载(字节),合计(字节)\r\n');
  for (final k in keys) {
    final v = log.days[k]!;
    b.write('$k,${v.$1},${v.$2},${v.$1 + v.$2}\r\n');
  }
  return b.toString();
}

/// 1.9.0 #200: whether a weekly snapshot is due: none yet, or the newest is 7 days old or more.
bool museWeeklySnapshotDue(Iterable<DateTime> weeklyTimes, DateTime now) {
  DateTime? newest;
  for (final t in weeklyTimes) {
    if (newest == null || t.isAfter(newest)) newest = t;
  }
  if (newest == null) return true;
  if (newest.isAfter(now)) return false; // clock went back: do not take one every start
  return now.difference(newest) >= const Duration(days: 7);
}

/// 1.9.0 #209: a download size in words (「42.3 MB」); empty when unknown.
String museFileSizeText(int bytes) {
  if (bytes <= 0) return '';
  const k = 1024;
  if (bytes < k * k) return '${(bytes / k).toStringAsFixed(0)} KB';
  if (bytes < k * k * k) return '${(bytes / (k * k)).toStringAsFixed(1)} MB';
  return '${(bytes / (k * k * k)).toStringAsFixed(2)} GB';
}
