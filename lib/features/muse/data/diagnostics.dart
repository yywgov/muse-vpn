// 穿云 - 设置 › 关于 › 导出诊断: one text file with why the connection dropped (kept by the VPN
// service), the core's crash traces and the recent app/core log, shared through the system sheet.
// Nothing is sent anywhere unless the user shares the file.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:io';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/logger/logger_setup.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

abstract final class MuseDiagnostics {
  /// Writes the diagnostics file and opens the share sheet. False when the file could not be written.
  static Future<bool> export(WidgetRef ref) async {
    try {
      await _export(ref);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _export(WidgetRef ref) async {
    final appInfo = ref.read(appInfoProvider).valueOrNull;
    final native = Platform.isAndroid ? await ChuanyunPlatform.nativeDiagnostics() : await _desktopDiagnostics();
    final now = DateTime.now();
    final b = StringBuffer()
      ..writeln('穿云 诊断信息  ${now.toIso8601String()}')
      ..writeln(appInfo?.format() ?? '')
      ..writeln()
      ..writeln('===== 设备 =====')
      ..writeln(native?['device'] ?? '(不可用)')
      ..writeln('===== 断开 / 恢复记录 =====')
      ..writeln((native?['disconnects'] as String?)?.trim().isNotEmpty == true ? native!['disconnects'] : '(无记录)')
      ..writeln()
      ..writeln('===== 内核崩溃输出 =====')
      ..writeln((native?['crash'] as String?)?.trim().isNotEmpty == true ? native!['crash'] : '(无)')
      ..writeln()
      ..writeln('===== 最近日志（应用 + 内核）=====');
    for (final r in logRing.records) {
      b.writeln(formatRecord(r));
    }
    // 穿云 Windows: no share sheet worth using — save to 下载 and show the file in Explorer
    final dir = Platform.isWindows
        ? (await getDownloadsDirectory() ?? await getTemporaryDirectory())
        : await getTemporaryDirectory();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final file = File('${dir.path}/chuanyun-diagnostics-$stamp.txt');
    await file.writeAsString(b.toString());
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,', file.path]);
      return;
    }
    // the share sheet being dismissed is not a failure
    await UriUtils.tryShareFile(Uri.file(file.path), mimeType: 'text/plain');
  }

  /// 穿云 Windows 1.2.1: the same sections from <working dir>/data — disconnect.log (why the
  /// connection dropped / recovered), guard.log (the system-proxy guard) and the core's
  /// stderr*.log (Go panics / fatal errors; *.old.log is the run before).
  static Future<Map<Object?, Object?>> _desktopDiagnostics() async {
    final dir = ChuanyunPlatform.desktopDataDir;
    String read(List<String> names) {
      if (dir == null) return '';
      final b = StringBuffer();
      for (final n in names) {
        final f = File('$dir${Platform.pathSeparator}$n');
        if (!f.existsSync() || f.lengthSync() == 0) continue;
        var text = f.readAsStringSync();
        if (text.length > 64 * 1024) text = text.substring(text.length - 64 * 1024);
        b
          ..writeln('--- $n ---')
          ..writeln(text.trim());
      }
      return b.toString();
    }

    final stderrNames = <String>[];
    if (dir != null && Directory(dir).existsSync()) {
      for (final e in Directory(dir).listSync()) {
        final n = e.uri.pathSegments.last;
        if (n.startsWith('stderr') && n.endsWith('.log')) stderrNames.add(n);
      }
      stderrNames.sort();
    }
    return {
      'device': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'disconnects': read(['disconnect.old.log', 'disconnect.log', 'guard.old.log', 'guard.log']),
      'crash': read(stderrNames),
    };
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
