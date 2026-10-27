// 穿云 - Android bits for the privacy and keep-alive settings.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/utils/platform_utils.dart';

abstract final class ChuanyunPlatform {
  static const _channel = MethodChannel('com.chuanyun.app/system');

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (!PlatformUtils.isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> isLauncherIconHidden() async => await _call<bool>('is_launcher_icon_hidden') ?? false;

  static Future<bool> setLauncherIconHidden(bool hidden) async =>
      await _call<bool>('set_launcher_icon_hidden', {'hidden': hidden}) ?? false;

  static Future<void> setExcludeFromRecents(bool exclude) =>
      _call<bool>('set_exclude_from_recents', {'exclude': exclude});

  static Future<bool> openNotificationSettings() async => await _call<bool>('open_notification_settings') ?? false;

  static Future<bool> openAppDetails() async => await _call<bool>('open_app_details') ?? false;

  static Future<bool> openDateSettings() async => await _call<bool>('open_date_settings') ?? false;

  static Future<bool> openAutostartSettings() async => await _call<bool>('open_autostart_settings') ?? false;

  /// 1.6.0 C9 按需运行: the Wi‑Fi name ({ok, ssid} / {ok: false, reason: permission | location_off | unknown}).
  static Future<Map<Object?, Object?>?> wifiSsid() => _call<Map<Object?, Object?>>('wifi_ssid');

  /// granted / denied / blocked (null when not Android)
  static Future<String?> wifiPermission() => _call<String>('wifi_permission');

  /// Asks for 「位置信息」 (only when the user turns 按需运行 on); same answers as [wifiPermission].
  static Future<String?> requestWifiPermission() => _call<String>('request_wifi_permission');

  /// 1.6.0 C9 分应用代理 › 只看联网应用: packages that asked for INTERNET (null when unknown).
  static Future<Set<String>?> internetPackages() async {
    final l = await _call<List<Object?>>('internet_packages');
    return l == null ? null : {for (final p in l) '$p'};
  }

  /// Epoch millis when the VPN service last came up (0/null when stopped or not Android).
  static Future<int?> connectedSince() => _call<int>('get_connected_since');

  /// 1.4.1: manufacturer / brand / boot time (epoch ms) — null when not Android.
  static Future<({String manufacturer, String brand, int bootTime})?> deviceInfo() async {
    final m = await _call<Map<Object?, Object?>>('device_info');
    if (m == null) return null;
    return (
      manufacturer: '${m['manufacturer'] ?? ''}',
      brand: '${m['brand'] ?? ''}',
      bootTime: (m['boot_time'] as num?)?.toInt() ?? 0,
    );
  }

  /// 穿云: what the Android side keeps for 导出诊断 (device facts, disconnect reasons, crash traces).
  static Future<Map<Object?, Object?>?> nativeDiagnostics() => _call<Map<Object?, Object?>>('diagnostics_native');

  /// Adds a line to the disconnect log: kept by the VPN service on Android, in
  /// <working dir>/data/disconnect.log on Windows (穿云 1.2.1; 导出诊断 includes it).
  static Future<void> recordDisconnect(String reason) async {
    if (PlatformUtils.isAndroid) {
      await _call<bool>('record_disconnect', {'reason': reason});
      return;
    }
    final dir = desktopDataDir;
    if (dir == null) return;
    try {
      final f = File('$dir${Platform.pathSeparator}disconnect.log');
      if (f.existsSync() && f.lengthSync() > 256 * 1024) {
        f.renameSync('$dir${Platform.pathSeparator}disconnect.old.log');
      }
      final now = DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
      await f.writeAsString('$now $reason\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // diagnostics only
    }
  }

  /// Desktop: <working dir>/data, set at start-up.
  static String? desktopDataDir;

  /// 穿云 1.1: a one-off system notification (subscription running out, 穿云已断开 …).
  static Future<void> showAlert({required int id, required String title, required String text}) =>
      _call<bool>('show_alert', {'id': id, 'title': title, 'text': text});

  /// 穿云 1.1: hands a downloaded APK to the system installer (asks for 「安装未知应用」 first if needed).
  /// 1.2.4: true / false, null when unknown (see ChuanyunHandler.apk_signature_matches).
  static Future<bool?> apkSignatureMatches(String path) => _call<bool>('apk_signature_matches', {'path': path});

  static Future<bool> installApk(String path) async => await _call<bool>('install_apk', {'path': path}) ?? false;
}
