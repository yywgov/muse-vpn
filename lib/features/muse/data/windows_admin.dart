// 穿云 Windows: TUN mode (wintun) only works when the app runs as administrator.
// The app defaults to 系统代理; TUN is offered as an option that relaunches 穿云 elevated.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:io';

import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';

abstract final class WindowsAdmin {
  static final _logger = infraLogger('WindowsAdmin');

  static bool _elevated = false;

  /// Whether this process runs elevated (Windows only; false elsewhere or before [detect]).
  static bool get isElevated => _elevated;

  /// Reads the process token's integrity level once at start-up ("High" = elevated).
  static Future<void> detect() async {
    if (!PlatformUtils.isWindows) return;
    try {
      final result = await Process.run('whoami', ['/groups']).timeout(const Duration(seconds: 5));
      // S-1-16-12288 = High Mandatory Level, S-1-16-16384 = System
      final out = result.stdout.toString();
      _elevated = out.contains('S-1-16-12288') || out.contains('S-1-16-16384');
    } catch (e) {
      _logger.warning('could not read the integrity level', e);
      _elevated = false;
    }
    _logger.info('running elevated: $_elevated');
  }

  /// 1.7.0 M3: starts a new copy of 穿云 a moment after this one quits (内核 switch). An elevated
  /// run starts the new copy through its own (elevated) PowerShell, so it stays elevated.
  static Future<bool> relaunch() async {
    if (!PlatformUtils.isWindows) return false;
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    try {
      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "Start-Sleep -Milliseconds 2500; Start-Process -FilePath '$exe'",
        ],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      _logger.warning('could not relaunch', e);
      return false;
    }
  }

  /// Starts a second, elevated copy of 穿云 (UAC prompt) a moment after this one quits.
  /// The caller quits the app right after; the delay lets the single-instance check pass.
  static Future<bool> relaunchElevated() async {
    if (!PlatformUtils.isWindows) return false;
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    try {
      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "Start-Sleep -Milliseconds 2500; Start-Process -FilePath '$exe' -Verb RunAs",
        ],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      _logger.warning('could not relaunch elevated', e);
      return false;
    }
  }
}
