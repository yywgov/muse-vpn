// 穿云 1.4.1 - 崩溃记录: uncaught errors are kept on the device (the newest 30, stack traces cut
// short) for 诊断 › 导出崩溃记录, redacted. Nothing is uploaded.
// Part of 穿云 (GPLv3).

import 'package:flutter/foundation.dart';
import 'package:hiddify/features/muse/logic/redact.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class MuseCrashRecorder {
  static const key = 'muse_crash_log';
  static SharedPreferences? _prefs;
  static DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  static void attach(SharedPreferences prefs) => _prefs = prefs;

  /// Records one error (at most one write per second, so an error loop can't hammer storage).
  static void record(Object error, StackTrace? stack) {
    final prefs = _prefs;
    if (prefs == null) return;
    final now = DateTime.now();
    if (now.difference(_lastWrite) < const Duration(seconds: 1)) return;
    _lastWrite = now;
    try {
      final log = museAddCrash(museParseCrashes(prefs.getString(key) ?? ''), MuseCrash(now, '$error', '${stack ?? ''}'));
      prefs.setString(key, museCrashesToRaw(log));
    } catch (_) {}
  }

  static void onFlutterError(FlutterErrorDetails d) => record(d.exception, d.stack);

  /// The crash log as text, redacted, newest first ('' = none).
  static String exportText(SharedPreferences prefs) {
    final log = museParseCrashes(prefs.getString(key) ?? '');
    if (log.isEmpty) return '';
    return [
      for (final c in log.reversed) '[${c.at.toIso8601String()}] ${museRedact(c.message)}\n${museRedact(c.stack)}',
    ].join('\n\n');
  }
}
