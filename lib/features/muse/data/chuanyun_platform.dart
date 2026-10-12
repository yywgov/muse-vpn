// 穿云 - Android bits for the privacy, keep-alive and 按网络自动开关 settings.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/services.dart';
import 'package:hiddify/utils/platform_utils.dart';

typedef LocationStatus = ({bool granted, bool background, bool enabled});

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

  static Future<bool> openAutostartSettings() async => await _call<bool>('open_autostart_settings') ?? false;

  static Future<bool> openLocationSettings() async => await _call<bool>('open_location_settings') ?? false;

  /// Epoch millis when the VPN service last came up (0/null when stopped or not Android).
  static Future<int?> connectedSince() => _call<int>('get_connected_since');

  static Future<String?> wifiSsid() => _call<String>('get_wifi_ssid');

  static Future<LocationStatus> locationStatus() async {
    final map = await _call<Map<Object?, Object?>>('location_status');
    return (
      granted: map?['granted'] == true,
      background: map?['background'] == true,
      enabled: map?['enabled'] == true,
    );
  }

  static Future<bool> requestLocationPermission() async =>
      await _call<bool>('request_location_permission') ?? false;

  /// Re-reads the 按网络自动开关 settings on the Android side and acts on the current network.
  static Future<void> applyNetworkAuto() => _call<bool>('apply_network_auto');

  /// 穿云: what the Android side keeps for 导出诊断 (device facts, disconnect reasons, crash traces).
  static Future<Map<Object?, Object?>?> nativeDiagnostics() => _call<Map<Object?, Object?>>('diagnostics_native');

  /// Adds a line to the disconnect log kept on the Android side.
  static Future<void> recordDisconnect(String reason) => _call<bool>('record_disconnect', {'reason': reason});
}
