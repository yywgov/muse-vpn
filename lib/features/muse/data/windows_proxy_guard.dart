// 穿云 Windows: when 穿云 was killed (crash, task manager, installer upgrade) while 系统代理 was on,
// Windows keeps pointing at the dead local port and nothing loads. At start-up, before the core
// runs, a system proxy that still points at 穿云's own port is switched off again.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:io';

import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';

abstract final class WindowsProxyGuard {
  static final _logger = infraLogger('WindowsProxyGuard');
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// Whether [server] (the ProxyServer value) points at 127.0.0.1:[port] / localhost:[port].
  static bool pointsAtUs(String server, int port) {
    final s = server.toLowerCase();
    return s.contains('127.0.0.1:$port') || s.contains('localhost:$port');
  }

  static Future<void> clearStale(int mixedPort) async {
    if (!PlatformUtils.isWindows) return;
    try {
      final q = await Process.run('reg', ['query', _key]).timeout(const Duration(seconds: 5));
      final out = q.stdout.toString();
      final enabled = RegExp(r'ProxyEnable\s+REG_DWORD\s+0x0*1\b').hasMatch(out);
      final server = RegExp(r'ProxyServer\s+REG_SZ\s+(.*)').firstMatch(out)?.group(1)?.trim() ?? '';
      if (!enabled || !pointsAtUs(server, mixedPort)) return;
      _logger.info('system proxy still points at $server from an earlier run: switching it off');
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
    } catch (e) {
      _logger.warning('could not check the system proxy', e);
    }
  }
}
