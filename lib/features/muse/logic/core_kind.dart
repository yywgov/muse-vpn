// 穿云 1.7.0 M3 - which core runs the connection: 标准内核 (the default, unchanged since 1.6.1) or
// 兼容内核 (new in 1.7.0). Pure logic + the one selection read at start-up (unit-tested).
//
// Windows loads the core library once per process, so a change takes effect after the app is
// restarted; Android starts the chosen core with each connection, so there it takes effect on the
// next connect. The choice stays on this device (not synced, not in backups): another device's
// engine choice must never switch this one behind the user's back.
// Part of 穿云 (GPLv3).

enum MuseCoreKind {
  standard('standard', '标准内核', '默认，稳定，支持的节点类型最全'),
  compat('compat', '兼容内核', '新：原生读取订阅里的代理组与规则');

  const MuseCoreKind(this.key, this.title, this.blurb);

  /// stored in the preference `muse_core_kind`
  final String key;
  final String title;
  final String blurb;

  /// Unknown / missing values are the default core, so nothing changes for anyone who never chose.
  static MuseCoreKind fromKey(Object? key) => switch (key) {
    'compat' => MuseCoreKind.compat,
    _ => MuseCoreKind.standard,
  };
}

/// Preference key of the choice (device-local).
const museCoreKindPrefKey = 'muse_core_kind';

/// Engine version of 兼容内核 (built from the core repository's rel-1.7.0 source, pinned there).
const museCompatEngineVersion = '1.19.33';

/// The core this process runs with. Windows reads it once when the app starts (the core library
/// is loaded once per process); Android reads the preference again at every connect.
abstract final class MuseCoreSelection {
  static MuseCoreKind _startup = MuseCoreKind.standard;

  /// The choice the app started with.
  static MuseCoreKind get startup => _startup;

  /// Called once after the preferences are loaded, before the core is set up.
  static void init(Object? key) => _startup = MuseCoreKind.fromKey(key);
}

/// Android: what the app hands the platform side with every connect. `coreKind` picks the service
/// (兼容内核 runs in its own process; a build without its library keeps the standard core), and
/// `ipv6` tells 兼容内核's VPN service whether to route IPv6 into its TUN (the standard core takes
/// that from its own configuration and ignores it).
Map<String, Object> museAndroidStartExtras({required MuseCoreKind kind, required bool ipv6}) => {
  'coreKind': kind.key,
  'ipv6': ipv6,
};

/// Android: port of the background core's control service. Both cores' services listen there
/// (兼容内核 in its own process), so the app's background client never changes.
const museAndroidBackgroundPort = 17079;

/// Android library of 兼容内核 (arm64-v8a, built by the client CI from the pinned core source).
const museCompatAndroidLibrary = 'libmusecompat.so';

/// Windows library of 兼容内核 (next to the app; same C functions as the standard core's library).
const museCompatLibrary = 'muse-compat.dll';

/// Path of the 兼容内核 library to load, or null for the standard core: not chosen, or missing.
String? museCompatLibraryPath(String dir, MuseCoreKind kind, {required bool Function(String path) exists}) {
  if (kind != MuseCoreKind.compat) return null;
  final path = dir.isEmpty ? museCompatLibrary : '$dir\\$museCompatLibrary';
  return exists(path) ? path : null;
}

/// What happens when the user picks [picked] while [current] is saved.
enum MuseCoreSwitchStep {
  /// same core: nothing to do
  none,

  /// connected (or connecting): disconnect first, nothing is saved
  disconnectFirst,

  /// saved; Windows: restart the app to use it
  restartApp,

  /// saved; Android: used from the next connect
  nextConnect,
}

MuseCoreSwitchStep museCoreSwitchStep({
  required MuseCoreKind current,
  required MuseCoreKind picked,
  required bool disconnected,
  required bool desktop,
}) {
  if (picked == current) return MuseCoreSwitchStep.none;
  if (!disconnected) return MuseCoreSwitchStep.disconnectFirst;
  return desktop ? MuseCoreSwitchStep.restartApp : MuseCoreSwitchStep.nextConnect;
}

/// Desktop: the saved choice differs from the one this process loaded → "重启后生效".
bool museCoreRestartPending({required MuseCoreKind saved, required MuseCoreKind running, required bool desktop}) =>
    desktop && saved != running;
