// 穿云 1.6.0 C10 - 资源 page and 关于 › 内核版本 (pure logic, unit-tested): the rule-sets the app
// ships and the ones the user added, with their size, source and when the copy on this device
// was written; the core release this build bundles.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:path/path.dart' as p;

/// The core release this build bundles (dependencies.properties `muse.core.version`; a test keeps
/// the two equal).
const museCoreRelease = '5.0.0-muse.18';

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

// ---------------------------------------------------------------- 关于 › 版本 ×7 (#127)

/// Taps on 关于 › 版本 needed to turn 开发者选项 on.
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
