// 穿云 1.9.0 (batch 2) - small helpers for the 1.9.0 settings (pure logic, unit-tested).
// 1.10.0: the 帮助与隐私 page and its texts (glossary, what is stored / never sent) were removed.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/logic/stats_tools.dart';

/// 1.9.0 #179: the traffic log as CSV (日期,上传,下载,合计 — bytes), oldest day first.
String museTrafficCsv(MuseTrafficLog log) {
  final keys = log.days.keys.toList()..sort();
  final b = StringBuffer('日期,上传(字节),下载(字节),合计(字节)\r\n');
  for (final k in keys) {
    final v = log.days[k]!;
    b.write('$k,${v.$1},${v.$2},${v.$1 + v.$2}\r\n');
  }
  return b.toString();
}

/// 1.9.0 #200: whether a weekly snapshot is due: none yet, or the newest is 7 days old or more.
bool museWeeklySnapshotDue(Iterable<DateTime> weeklyTimes, DateTime now) {
  DateTime? newest;
  for (final t in weeklyTimes) {
    if (newest == null || t.isAfter(newest)) newest = t;
  }
  if (newest == null) return true;
  if (newest.isAfter(now)) return false; // clock went back: do not take one every start
  return now.difference(newest) >= const Duration(days: 7);
}

/// 1.9.0 #209: a download size in words (「42.3 MB」); empty when unknown.
String museFileSizeText(int bytes) {
  if (bytes <= 0) return '';
  const k = 1024;
  if (bytes < k * k) return '${(bytes / k).toStringAsFixed(0)} KB';
  if (bytes < k * k * k) return '${(bytes / (k * k)).toStringAsFixed(1)} MB';
  return '${(bytes / (k * k * k)).toStringAsFixed(2)} GB';
}
