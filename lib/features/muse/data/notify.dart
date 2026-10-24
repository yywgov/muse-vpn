// 穿云 1.2.8 - one system notification on both platforms: Android through the app's own channel
// (ChuanyunPlatform.showAlert), Windows as a toast shown by PowerShell (no extra package; the
// text goes in base64-encoded, so quotes and Chinese can't break the script).
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/muse/data/chuanyun_platform.dart';

/// 1.5.0 #140: the app id the installer gives the Start-menu shortcut, so toasts say 「穿云」.
const museWindowsAppId = 'Chuanyun.App';
const _powershellAppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe';

/// The installed app's id when the installer's Start-menu shortcut exists (Windows only shows a
/// toast for an id some shortcut carries); otherwise PowerShell's own (the portable zip).
String museWindowsToastAppId(Map<String, String> env, bool Function(String path) exists) {
  for (final base in [env['APPDATA'], env['ProgramData']]) {
    if (base == null || base.isEmpty) continue;
    if (exists('$base\\Microsoft\\Windows\\Start Menu\\Programs\\穿云.lnk')) return museWindowsAppId;
  }
  return _powershellAppId;
}

/// The PowerShell that shows a Windows toast with [title] / [text] (for tests).
String museWindowsToastScript(String title, String text, {String appId = _powershellAppId}) {
  String b64(String s) => base64.encode(utf8.encode(s));
  return '''
\$ErrorActionPreference = 'Stop'
\$t = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${b64(title)}'))
\$m = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${b64(text)}'))
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
\$x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$n = \$x.GetElementsByTagName('text')
\$n.Item(0).AppendChild(\$x.CreateTextNode(\$t)) | Out-Null
\$n.Item(1).AppendChild(\$x.CreateTextNode(\$m)) | Out-Null
\$app = '$appId'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$app).Show([Windows.UI.Notifications.ToastNotification]::new(\$x))
''';
}

/// Shows a system notification; never throws.
Future<void> museNotify({required int id, required String title, required String text}) async {
  try {
    if (Platform.isAndroid) {
      await ChuanyunPlatform.showAlert(id: id, title: title, text: text);
    } else if (Platform.isWindows) {
      final appId = museWindowsToastAppId(Platform.environment, (p) => File(p).existsSync());
      final script = museWindowsToastScript(title, text, appId: appId);
      final units = script.codeUnits;
      final bytes = <int>[for (final u in units) ...[u & 0xff, u >> 8]];
      await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        base64.encode(bytes),
      ]).timeout(const Duration(seconds: 15));
    }
  } catch (_) {
    // a missing notification is not worth an error
  }
}
