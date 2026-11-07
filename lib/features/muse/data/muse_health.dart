// 穿云 1.13.0 - 本地崩溃自检 / 安全模式 / 被其他 VPN 顶掉: where the state lives.
// Android: the VPN service's own bookkeeping (ChuanyunHealth.kt, app-private files), so a failed
// 小组件 / 快捷开关 / 开机 start counts even with no app UI; plus the app's own unread crash here.
// Desktop: all of it in the preferences. Read when 首页 opens and when the connection status
// changes — no timer, no polling. Nothing is uploaded.
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/logic/health_tools.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class MuseHealth {
  static const unseenKey = 'muse_crash_unseen';
  static const failuresKey = 'muse_start_failures';
  static const lastFailKey = 'muse_start_last_fail';
  static const safeModeKey = 'muse_safe_mode';
  static const startLogKey = 'muse_start_fail_log';

  /// the desktop start-failure log stays under this size (oldest lines dropped)
  static const startLogMax = 32 * 1024;

  static SharedPreferences? _prefs;

  static void attach(SharedPreferences prefs) => _prefs = prefs;

  static bool get _android => PlatformUtils.isAndroid;

  /// An uncaught error of the app itself: 首页 shows 「上次异常」 next time.
  static void markAppCrash(String summary) {
    try {
      _prefs?.setString(unseenKey, museEncodeUnseen(DateTime.now(), summary));
    } catch (_) {}
  }

  static Future<MuseHealthState> load() async {
    final prefs = _prefs;
    final app = museParseUnseen(prefs?.getString(unseenKey));
    if (_android) return MuseHealthState.fromMap(await ChuanyunPlatform.healthState()).withAppCrash(app);
    return MuseHealthState(
      safeMode: prefs?.getBool(safeModeKey) ?? false,
      failures: prefs?.getInt(failuresKey) ?? 0,
    ).withAppCrash(app);
  }

  /// A connect failed. Android: counted by the service (the same failure reported by the service
  /// and the app within 5 s counts once).
  static Future<void> startFailed(String reason) async {
    if (_android) return ChuanyunPlatform.healthStartFailed(reason);
    final prefs = _prefs;
    if (prefs == null) return;
    final now = DateTime.now();
    final last = prefs.getInt(lastFailKey);
    final count = museNextFailures(prefs.getInt(failuresKey) ?? 0, last == null ? null : DateTime.fromMillisecondsSinceEpoch(last), now);
    await prefs.setInt(failuresKey, count);
    await prefs.setInt(lastFailKey, now.millisecondsSinceEpoch);
    var log = '${prefs.getString(startLogKey) ?? ''}${now.toIso8601String()}  启动失败（连续第 $count 次）：$reason\n';
    if (museEntersSafeMode(count) && prefs.getBool(safeModeKey) != true) {
      await prefs.setBool(safeModeKey, true);
      log += '${now.toIso8601String()}  连续 $count 次启动失败，下次以安全模式启动（停用自定义规则）\n';
    }
    if (log.length > startLogMax) log = log.substring(log.length - startLogMax);
    await prefs.setString(startLogKey, log);
    await prefs.setString(unseenKey, museEncodeUnseen(now, '启动失败：$reason'));
  }

  /// Connected: the failure streak ends (安全模式 stays until the user leaves it).
  static Future<void> startOk() async {
    if (_android) return ChuanyunPlatform.healthStartOk();
    await _prefs?.remove(failuresKey);
    await _prefs?.remove(lastFailKey);
  }

  static Future<void> exitSafeMode() async {
    if (_android) await ChuanyunPlatform.healthExitSafeMode();
    await _prefs?.remove(safeModeKey);
    await _prefs?.remove(failuresKey);
    await _prefs?.remove(lastFailKey);
  }

  static Future<void> dismissCrash() async {
    if (_android) await ChuanyunPlatform.healthDismissCrash();
    await _prefs?.remove(unseenKey);
  }

  static Future<void> dismissRevoked() async {
    if (_android) await ChuanyunPlatform.healthDismissRevoked();
  }

  /// The service's crash / start-failure log (Android) or the desktop start-failure log.
  static Future<String> serviceLog() async => _android ? ChuanyunPlatform.healthLog() : (_prefs?.getString(startLogKey) ?? '');
}

class MuseHealthNotifier extends AsyncNotifier<MuseHealthState> {
  @override
  Future<MuseHealthState> build() => MuseHealth.load();

  Future<void> refresh() async {
    try {
      state = AsyncData(await MuseHealth.load());
    } catch (_) {}
  }

  Future<void> exitSafeMode() async {
    await MuseHealth.exitSafeMode();
    await refresh();
  }

  Future<void> dismissCrash() async {
    await MuseHealth.dismissCrash();
    await refresh();
  }

  Future<void> dismissRevoked() async {
    await MuseHealth.dismissRevoked();
    await refresh();
  }
}

final museHealthProvider = AsyncNotifierProvider<MuseHealthNotifier, MuseHealthState>(MuseHealthNotifier.new);

/// 1.13.0 安全模式: the config leaves out the user's own rules (分流规则、远程规则集、从连接加的规则、
/// 屏蔽域名、订阅覆写) until the user leaves it on 首页.
final museSafeModeProvider = Provider<bool>((ref) => ref.watch(museHealthProvider).valueOrNull?.safeMode ?? false);
