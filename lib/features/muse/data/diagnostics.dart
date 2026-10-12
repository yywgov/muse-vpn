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
    final native = await ChuanyunPlatform.nativeDiagnostics();
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
    final dir = await getTemporaryDirectory();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final file = File('${dir.path}/chuanyun-diagnostics-$stamp.txt');
    await file.writeAsString(b.toString());
    // the share sheet being dismissed is not a failure
    await UriUtils.tryShareFile(Uri.file(file.path), mimeType: 'text/plain');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
