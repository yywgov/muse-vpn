// 穿云 1.4.0 - extra core options that are not part of the generated settings model (sent with
// the settings JSON; the core ignores keys it doesn't know). Set from preferences by
// museCoreExtrasProvider (lib/features/muse/data/core_extras_provider.dart).
// Part of 穿云 (GPLv3).

/// The extra keys sent with every settings change.
Map<String, dynamic> museCoreExtras = const {};

/// [json] with the extra keys added (the extras win).
Map<String, dynamic> museApplyCoreExtras(Map<String, dynamic> json) =>
    museCoreExtras.isEmpty ? json : {...json, ...museCoreExtras};

/// The extras for the 测速 settings (workers 4–64, timeout 2–15 s, as the core clamps them).
Map<String, dynamic> museTestExtras({required int workers, required int timeoutSec}) => {
  'muse-test-workers': workers.clamp(4, 64),
  'muse-test-timeout-ms': timeoutSec.clamp(2, 15) * 1000,
};

/// Custom hosts for the core (`muse-hosts`, core 5.0.0-muse.14); nothing when empty.
Map<String, dynamic> museHostsExtras(Map<String, String> hosts) => hosts.isEmpty ? const {} : {'muse-hosts': hosts};
