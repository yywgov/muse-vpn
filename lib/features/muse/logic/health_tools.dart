// 穿云 1.13.0 - 本地崩溃自检 / 安全模式 / 被其他 VPN 顶掉: the pure part (unit-tested).
// The Android service keeps the same bookkeeping in ChuanyunHealth.kt (files in the app's private
// storage); the desktop builds keep it in the preferences. Nothing is uploaded.
// Part of 穿云 (GPLv3).

/// Two failed starts in a row → 安全模式 (same as ChuanyunHealth.SAFE_MODE_AFTER).
const museSafeModeAfter = 2;

/// The same failure reported twice (service + app) within this window counts once.
const museSameFailure = Duration(seconds: 5);

/// The next consecutive-failure count.
int museNextFailures(int count, DateTime? lastAt, DateTime now) {
  if (lastAt != null) {
    final d = now.difference(lastAt);
    if (!d.isNegative && d < museSameFailure) return count;
  }
  return count + 1;
}

bool museEntersSafeMode(int failures) => failures >= museSafeModeAfter;

/// What 首页 shows about the app's own health.
class MuseHealthState {
  const MuseHealthState({this.crash, this.crashAt, this.safeMode = false, this.failures = 0, this.revokedAt});

  /// one line about the newest unread problem (null = none)
  final String? crash;
  final DateTime? crashAt;
  final bool safeMode;
  final int failures;

  /// when another VPN app took the VPN over (null = not, or the hint was closed)
  final DateTime? revokedAt;

  static const none = MuseHealthState();

  bool get isEmpty => crash == null && !safeMode && revokedAt == null;

  /// Reads ChuanyunHealth.state() (Android) — missing or odd values count as nothing.
  factory MuseHealthState.fromMap(Map<Object?, Object?>? m) {
    if (m == null) return none;
    DateTime? at(Object? v) => v is int && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    final crash = m['crash'];
    return MuseHealthState(
      crash: crash is String && crash.trim().isNotEmpty ? crash.trim() : null,
      crashAt: at(m['crashAt']),
      safeMode: m['safeMode'] == true,
      failures: m['failures'] is int ? m['failures']! as int : 0,
      revokedAt: at(m['revokedAt']),
    );
  }

  /// The newer of two unread problems (the service's and the app's own).
  MuseHealthState withAppCrash(({DateTime at, String text})? app) {
    if (app == null) return this;
    if (crashAt != null && crashAt!.isAfter(app.at)) return this;
    return MuseHealthState(crash: app.text, crashAt: app.at, safeMode: safeMode, failures: failures, revokedAt: revokedAt);
  }
}

/// The app's own unread crash, stored as "ms, newline, summary" (null = none or unreadable).
({DateTime at, String text})? museParseUnseen(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final i = raw.indexOf('\n');
  if (i <= 0) return null;
  final ms = int.tryParse(raw.substring(0, i));
  final text = raw.substring(i + 1).trim();
  if (ms == null || text.isEmpty) return null;
  return (at: DateTime.fromMillisecondsSinceEpoch(ms), text: text);
}

String museEncodeUnseen(DateTime at, String text) {
  final line = text.replaceAll('\n', ' ').trim();
  return '${at.millisecondsSinceEpoch}\n${line.length > 300 ? line.substring(0, 300) : line}';
}

/// 「上次异常」 time in plain Chinese.
String museWhen(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.isNegative || d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  if (d.inDays < 30) return '${d.inDays} 天前';
  return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
}

/// The text for 「复制日志」: the service's log and the app's, both already redacted by the caller.
String museHealthLogText({required String version, required String system, required String serviceLog, required String appLog}) {
  final b = StringBuffer()
    ..writeln('穿云 $version · $system')
    ..writeln('（本日志只保存在本机，已去除订阅链接与地址等敏感信息）')
    ..writeln();
  b
    ..writeln('== 服务与崩溃记录 ==')
    ..writeln(serviceLog.trim().isEmpty ? '（无）' : serviceLog.trim())
    ..writeln()
    ..writeln('== 界面异常记录 ==')
    ..writeln(appLog.trim().isEmpty ? '（无）' : appLog.trim());
  return b.toString();
}
