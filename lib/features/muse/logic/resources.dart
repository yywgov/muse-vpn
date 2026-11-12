// 穿云 1.6.0 C10 - 资源 page and 关于 › 内核版本 (pure logic, unit-tested): the rule-sets the app
// ships and the ones the user added, with their size, source and when the copy on this device
// was written; the core release this build bundles.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:path/path.dart' as p;

/// The core release this build bundles (dependencies.properties `muse.core.version`; a test keeps
/// the two equal). 1.20.4: release names are `5.0.0-chuanyun.N` from 25 on (`5.0.0-muse.N` up to
/// 24); only the name changed — repository yywgov/muse-core, branch muse and the asset names stay.
const museCoreRelease = '5.0.0-chuanyun.25';

/// A core release name, new (`5.0.0-chuanyun.25`) or old (`5.0.0-muse.24`), with or without the
/// tag's leading `v`.
final museCoreReleasePattern = RegExp(r'^v?(\d+\.\d+\.\d+)-(chuanyun|muse)\.(\d+)$');

/// The release number of [release] (25 for `5.0.0-chuanyun.25`, 24 for `v5.0.0-muse.24`), or null.
/// Both prefixes count as one series, so chuanyun.25 is newer than muse.24.
int? museCoreReleaseNumber(String release) {
  final m = museCoreReleasePattern.firstMatch(release.trim());
  return m == null ? null : int.parse(m.group(3)!);
}

/// 1.20.4: how 设置 › 内核与资源 › 内核版本 shows the standard core: 「内核 chuanyun.25」.
String museCoreDisplay([String release = museCoreRelease]) => '内核 ${museCoreShort(release)}';

/// While connected the core refreshes every rule-set in the background this often.
const museRuleSetUpdateDays = 5;

/// A readable name for a bundled rule-set file name (without .srs).
String museRuleSetTitle(String name) => switch (name) {
  'geosite-cn' => '国内网站',
  'geoip-cn' => '国内 IP',
  'geosite-category-ads-all' => '广告',
  'geosite-malware' => '恶意网站',
  'geosite-phishing' => '钓鱼网站',
  'geosite-cryptominers' => '挖矿网站',
  'geoip-malware' => '恶意 IP',
  'geoip-phishing' => '钓鱼 IP',
  _ when name.startsWith('geosite-') => name.substring('geosite-'.length),
  _ when name.startsWith('geoip-') => '${name.substring('geoip-'.length)} IP',
  _ => name,
};

/// 网站 / IP list.
String museRuleSetKind(String name) => name.startsWith('geoip-') ? 'IP' : '域名';

/// One rule-set file on this device.
class MuseRuleSetFile {
  const MuseRuleSetFile(this.name, {this.size, this.modified});

  final String name;

  /// null = not on this device yet (the core downloads it on the next connect)
  final int? size;
  final DateTime? modified;

  bool get present => size != null;
}

/// The bundled rule-set copies under [baseDir]/rule-sets, in [names] order. Never throws.
List<MuseRuleSetFile> museReadRuleSetFiles(String baseDir, Iterable<String> names) {
  final out = <MuseRuleSetFile>[];
  for (final n in names) {
    try {
      final f = File(p.join(baseDir, 'rule-sets', '$n.srs'));
      if (f.existsSync()) {
        final st = f.statSync();
        out.add(MuseRuleSetFile(n, size: st.size, modified: st.modified));
        continue;
      }
    } catch (_) {}
    out.add(MuseRuleSetFile(n));
  }
  return out;
}

/// Total size of the present files.
int museRuleSetTotal(Iterable<MuseRuleSetFile> files) => files.fold(0, (a, f) => a + (f.size ?? 0));

/// The version number in the core's own version string ("xyz 1.12.3" → "1.12.3"); null when
/// there is none.
String? museEngineVersion(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.\-]+)?').firstMatch(raw);
  return m?.group(0);
}

/// 「5.0.0-muse.17 · 引擎 1.12.3」 (the engine part only while connected).
String museCoreVersionLabel({String release = museCoreRelease, String? engine}) =>
    engine == null || engine.isEmpty ? release : '$release · 引擎 $engine';

/// A remote rule-set link's host and file ("example.com · ads.srs").
String museRemoteRuleSetSource(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  final file = u.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  return file == null ? u.host : '${u.host} · $file';
}

/// 1.10.0: the core release as 关于 shows it ('5.0.0-muse.20' → 'muse.20'; 1.20.4:
/// '5.0.0-chuanyun.25' → 'chuanyun.25').
String museCoreShort([String release = museCoreRelease]) {
  final i = release.lastIndexOf('-');
  return i < 0 || i == release.length - 1 ? release : release.substring(i + 1);
}

/// 1.10.0: the one small line under the name on 关于. 1.20.3: just 「1.20.2（215）」 — the 「 · 内核 muse.xx」
/// part is gone (the core version stays on 设置 › 内核与资源 › 内核版本, Windows and Android).
String museAboutVersionLine({required String version, required String build}) => '$version${build.isEmpty ? '' : '（$build）'}';

// ---------------------------------------------------------------- 关于 › 图标 ×7 (#127; 1.10.0: the icon, the version line checks for updates)

/// Taps on 关于's icon needed to turn 开发者选项 on.
const museDevTapsNeeded = 7;

/// Counts taps on the version; a pause longer than [gap] starts over.
class MuseDevTaps {
  MuseDevTaps({this.gap = const Duration(seconds: 2)});

  final Duration gap;
  int _count = 0;
  DateTime? _last;

  /// Taps still needed after this one (0 = turn it on now; the count starts over).
  int tap(DateTime now) {
    final last = _last;
    if (last == null || now.difference(last) > gap) _count = 0;
    _last = now;
    _count++;
    final left = museDevTapsNeeded - _count;
    if (left <= 0) {
      _count = 0;
      _last = null;
      return 0;
    }
    return left;
  }
}
