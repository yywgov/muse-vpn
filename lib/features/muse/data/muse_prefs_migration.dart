// 穿云 1.6.0 C1: versioned preference migrations (#217). Idempotent; a failing step rolls back
// and leaves the stored version unchanged.
// Part of 穿云 (GPLv3).

const musePrefsVersionKey = 'muse_prefs_version';
const musePrefsVersionCurrent = 2;

typedef MusePrefsStep = void Function(Map<String, Object?> prefs);

/// Steps keyed by the version they migrate FROM. 1→2 is empty for now (C7 fills it).
final Map<int, MusePrefsStep> musePrefsSteps = {1: (prefs) {}};

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
