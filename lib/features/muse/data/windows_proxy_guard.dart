// 穿云 Windows 1.2.1 - never leave the PC offline because of 穿云.
//
// In 系统代理 mode Windows points every app at 127.0.0.1:<mixed port>. sing-box only blanks that
// setting when the core stops cleanly; when 穿云 dies (crash, kill) or its core breaks while the
// setting is in place, nothing loads anywhere. ChuanyunGuard.exe (windows/guard/guard.cpp) does
// the WinINet work:
// - before every connect the user's own proxy settings are saved (proxy-backup.txt),
// - after a stop, a failed recovery and at start-up they are restored (not just blanked),
// - a watcher process restores them the moment Chuanyun.exe exits while the proxy still points
//   at us, and relaunches the app after a crash exit so it reconnects.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:io';

import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:path/path.dart' as p;

abstract final class WindowsProxyGuard {
  static final _logger = infraLogger('WindowsProxyGuard');
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// <working dir>\data: next to the core's stderr logs (set at start-up).
  static String? stateDir;

  /// The mixed port the system proxy points at while 穿云 is connected.
  static int port = 12334;

  static String get _guardExe => p.join(File(Platform.resolvedExecutable).parent.path, 'ChuanyunGuard.exe');

  static bool get available => PlatformUtils.isWindows && stateDir != null && File(_guardExe).existsSync();

  /// Whether [server] (the ProxyServer value) points at 127.0.0.1:[port] / localhost:[port].
  static bool pointsAtUs(String server, int port) {
    final s = server.toLowerCase();
    return RegExp('(127\\.0\\.0\\.1|localhost|\\[::1\\]):$port(?!\\d)').hasMatch(s);
  }

  static Future<({int code, String out})> _run(String cmd, [List<String> extra = const []]) async {
    final r = await Process.run(_guardExe, [cmd, stateDir!, '$port', ...extra]).timeout(const Duration(seconds: 8));
    return (code: r.exitCode, out: r.stdout.toString().trim());
  }

  /// Start-up, before the core runs: settings left pointing at our port by an earlier run that
  /// was killed are put back, then the watcher for this process is started.
  static Future<void> startUp({required String dataDir, required int mixedPort}) async {
    if (!PlatformUtils.isWindows) return;
    stateDir = dataDir;
    port = mixedPort;
    await restore('startup');
    await startWatcher();
  }

  static Future<void> startWatcher() async {
    if (!available) return;
    try {
      await Process.start(
        _guardExe,
        ['watch', stateDir!, '$port', '$pid', Platform.resolvedExecutable],
        mode: ProcessStartMode.detached,
        workingDirectory: File(_guardExe).parent.path,
      );
      _logger.info('proxy guard watching pid $pid (port $port)');
    } catch (e) {
      _logger.warning('could not start the proxy guard', e);
    }
  }

  /// Saves the user's own settings before 穿云 switches the system proxy on (kept while a
  /// session's backup exists; never saves settings that point at us).
  static Future<void> saveBeforeConnect(int mixedPort) async {
    if (!available) return;
    port = mixedPort;
    try {
      final r = await _run('save');
      _logger.info('proxy settings before connect: ${r.out} (${r.code})');
    } catch (e) {
      _logger.warning('could not save the proxy settings', e);
    }
  }

  /// Puts the user's own settings back when the system proxy still points at 穿云 (or sing-box
  /// blanked a different setting). True when something was changed.
  static Future<bool> restore(String why) async {
    if (!PlatformUtils.isWindows) return false;
    if (!available) return _clearStaleByRegistry();
    try {
      final r = await _run('restore', [why]);
      if (r.code == 0) _logger.info('system proxy restored ($why): ${r.out}');
      return r.code == 0;
    } catch (e) {
      _logger.warning('could not restore the proxy settings ($why)', e);
      return _clearStaleByRegistry();
    }
  }

  /// Whether the system proxy points at 穿云 right now (null when it can't be read).
  static Future<bool?> pointsAtUsNow() async {
    final s = await systemProxyNow();
    return switch (s) {
      MuseSystemProxy.ours => true,
      MuseSystemProxy.unknown => null,
      _ => false,
    };
  }

  /// 穿云 1.2.2: what the system proxy is set to right now, as far as the keeper cares.
  static Future<MuseSystemProxy> systemProxyNow() async {
    if (!PlatformUtils.isWindows) return MuseSystemProxy.unknown;
    try {
      if (available) {
        final r = await _run('status');
        // exit code 0 = ours, 1 = not ours, anything else (2, a crash) = could not be read
        if (r.code != 0 && r.code != 1) return MuseSystemProxy.unknown;
        return museParseGuardStatus(r.out);
      }
      final q = await Process.run('reg', ['query', _key]).timeout(const Duration(seconds: 5));
      final out = q.stdout.toString();
      final enabled = RegExp(r'ProxyEnable\s+REG_DWORD\s+0x0*1\b').hasMatch(out);
      final server = RegExp(r'ProxyServer\s+REG_SZ\s+(.*)').firstMatch(out)?.group(1)?.trim() ?? '';
      if (!out.contains('ProxyEnable')) return MuseSystemProxy.unknown;
      if (enabled && pointsAtUs(server, port)) return MuseSystemProxy.ours;
      final pac = RegExp(r'AutoConfigURL\s+REG_SZ\s+\S').hasMatch(out);
      return enabled || pac ? MuseSystemProxy.other : MuseSystemProxy.direct;
    } catch (_) {
      return MuseSystemProxy.unknown;
    }
  }

  /// Fallback when ChuanyunGuard.exe is missing: switch off a ProxyEnable that points at us.
  static Future<bool> _clearStaleByRegistry() async {
    try {
      final q = await Process.run('reg', ['query', _key]).timeout(const Duration(seconds: 5));
      final out = q.stdout.toString();
      final enabled = RegExp(r'ProxyEnable\s+REG_DWORD\s+0x0*1\b').hasMatch(out);
      final server = RegExp(r'ProxyServer\s+REG_SZ\s+(.*)').firstMatch(out)?.group(1)?.trim() ?? '';
      if (!enabled || !pointsAtUs(server, port)) return false;
      _logger.info('system proxy still points at $server: switching it off');
      await Process.run('reg', [
        'add',
        _key,
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '0',
        '/f',
      ]).timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      _logger.warning('could not check the system proxy', e);
      return false;
    }
  }
}

/// 穿云 1.2.2: the system proxy as the connection keeper sees it.
enum MuseSystemProxy {
  /// points at 穿云's mixed port
  ours,

  /// exactly what ChuanyunGuard last put back (it restored the user's settings): reconnect
  restoredByGuard,

  /// no proxy, no PAC (sing-box blanked it, or nothing is set): reconnect
  direct,

  /// another proxy / PAC the guard did not set: the user changed it on purpose, leave it alone
  other,

  /// the guard / registry could not be read: decide nothing
  unknown,
}

/// Parses `ChuanyunGuard status` ("ours=0 flags=0x3 server=.. bypass=.. pac=.. backup=1 restored=0").
MuseSystemProxy museParseGuardStatus(String out) {
  final line = out.trim();
  final ours = RegExp(r'^ours=([01])\b').firstMatch(line)?.group(1);
  if (ours == null) return MuseSystemProxy.unknown;
  if (ours == '1') return MuseSystemProxy.ours;
  if (RegExp(r'\brestored=1\b').hasMatch(line)) return MuseSystemProxy.restoredByGuard;
  final flags = int.tryParse(RegExp(r'\bflags=(0x[0-9a-fA-F]+|\d+)').firstMatch(line)?.group(1) ?? '');
  if (flags == null) return MuseSystemProxy.unknown;
  // PROXY_TYPE_PROXY 0x2, PROXY_TYPE_AUTO_PROXY_URL 0x4
  return flags & 0x6 == 0 ? MuseSystemProxy.direct : MuseSystemProxy.other;
}
