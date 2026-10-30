// 穿云 1.6.0 C1: versioned preference migrations (#217). Idempotent; a failing step rolls back
// and leaves the stored version unchanged.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/home_tiles.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:shared_preferences/shared_preferences.dart';

const musePrefsVersionKey = 'muse_prefs_version';
const musePrefsVersionCurrent = 3;

typedef MusePrefsStep = void Function(Map<String, Object?> prefs);

/// Steps keyed by the version they migrate FROM.
/// 1→2 (1.6.0): the new dashboard cards start hidden for a saved 首页 layout; 字体大小 becomes
/// 文字缩放 (C7: 小 90 % / 大 110 % / 特大 120 % turn it on; 标准 leaves it off; an existing
/// 文字缩放 is never overwritten).
/// 2→3 (1.7.1): 配色风格 标准 (the old default, never picked on purpose) becomes 忠实; the four
/// replaced 主题色 move to the nearest new colour (苤蓝→宝蓝, 月白→松花, 苍蝇灰→胭脂, 朱瑾→枣红).
final Map<int, MusePrefsStep> musePrefsSteps = {1: museMigrate1to2, 2: museMigrate2to3};

/// 1.7.1: replaced 1.6.2 主题色 keys → their 1.7.1 successor.
const museAccentRenames171 = <String, String>{
  'pielan': 'baolan',
  'yuebai': 'songhua',
  'cangyinghui': 'yanzhi',
  'zhujin': 'zaohong',
};

void museMigrate2to3(Map<String, Object?> prefs) {
  if (prefs['muse_color_style'] == 'tonalSpot') prefs['muse_color_style'] = museDefaultColorStyle;
  final accent = prefs['muse_accent'];
  final renamed = accent is String ? museAccentRenames171[accent] : null;
  if (renamed != null) prefs['muse_accent'] = renamed;
}

void museMigrate1to2(Map<String, Object?> prefs) {
  final hidden = prefs['muse_home_tiles_hidden'];
  if (hidden is String) prefs['muse_home_tiles_hidden'] = museHideNewTiles16(hidden);
  final pct = museLegacyTextSizePct(prefs['muse_text_size']);
  if (pct != null && !prefs.containsKey('muse_text_scale_on') && !prefs.containsKey('muse_text_scale_pct')) {
    prefs['muse_text_scale_on'] = true;
    prefs['muse_text_scale_pct'] = pct;
  }
}

/// Runs the migrations on [sp] (only muse_* keys are read and written back). Never throws.
Future<int> musePrefsMigrateStore(SharedPreferences sp) async {
  try {
    final keys = sp.getKeys().where((k) => k.startsWith('muse_')).toList();
    final map = <String, Object?>{for (final k in keys) k: sp.get(k)};
    final before = Map<String, Object?>.of(map);
    final v = musePrefsMigrate(map);
    for (final e in map.entries) {
      if (before[e.key] == e.value) continue;
      final val = e.value;
      if (val is String) {
        await sp.setString(e.key, val);
      } else if (val is int) {
        await sp.setInt(e.key, val);
      } else if (val is bool) {
        await sp.setBool(e.key, val);
      } else if (val is double) {
        await sp.setDouble(e.key, val);
      }
    }
    return v;
  } catch (_) {
    return 0;
  }
}

/// Migrates [prefs] in place to [musePrefsVersionCurrent]. Returns the final version.
/// A missing/corrupt version counts as 1. On error the map is restored and the old version kept.
int musePrefsMigrate(Map<String, Object?> prefs, {Map<int, MusePrefsStep>? steps, int target = musePrefsVersionCurrent}) {
  final table = steps ?? musePrefsSteps;
  final raw = prefs[musePrefsVersionKey];
  var v = raw is int && raw >= 1 ? raw : 1;
  if (v >= target) return v;
  final backup = Map<String, Object?>.of(prefs);
  try {
    while (v < target) {
      table[v]?.call(prefs);
      v++;
    }
    prefs[musePrefsVersionKey] = v;
    return v;
  } catch (_) {
    prefs
      ..clear()
      ..addAll(backup);
    return raw is int && raw >= 1 ? raw : 1;
  }
}
