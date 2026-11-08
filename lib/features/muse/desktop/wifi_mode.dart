// 穿云 1.15.0 R23 - 按 Wi‑Fi 切换模式：在列出的 Wi‑Fi 下自动切到「规则」或「全局」，离开后恢复你原来的
// 模式；你手动改了模式就以你的为准。只在网络变化时检查（Android：系统 Wi‑Fi 连上 / 断开事件，只在列表
// 不为空时注册；两个平台都在回到穿云时检查一次），不轮询。读 Wi‑Fi 名称需要「位置信息」权限：先说明再
// 请求，拒绝时功能不切换模式、其余照常。完全不走代理请用「按需运行」（暂停连接）。
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// `{"SSID": "rule" | "global"}` → SSID → 模式（坏值当作没有）。
Map<String, MuseRouteMode> museParseWifiModes(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return const {};
    return {
      for (final e in j.entries)
        if ('${e.key}'.trim().isNotEmpty && MuseRouteMode.values.any((m) => m.key == e.value)) '${e.key}': MuseRouteMode.fromKey('${e.value}'),
    };
  } catch (_) {
    return const {};
  }
}

String museWifiModesToRaw(Map<String, MuseRouteMode> m) => m.isEmpty ? '' : jsonEncode({for (final e in m.entries) e.key: e.value.key});

/// 一次检查的结果：[setTo] 要切到的模式（null = 不动），以及更新后的 saved / applied。
class MuseWifiModeStep {
  const MuseWifiModeStep({this.setTo, required this.saved, required this.applied});

  final MuseRouteMode? setTo;
  final String saved;
  final String applied;
}

/// 纯逻辑：[read] 读到的 Wi‑Fi、[current] 当前模式、[saved] 我们切换前用户的模式、[applied] 我们切到的模式。
MuseWifiModeStep museWifiModeStep({
  required Map<String, MuseRouteMode> modes,
  required MuseSsidRead read,
  required MuseRouteMode current,
  required String saved,
  required String applied,
}) {
  if (!read.ok) return MuseWifiModeStep(saved: saved, applied: applied); // 读不到：保持现状
  if (applied.isNotEmpty && current.key != applied) {
    // 用户在我们切换后手动改了模式：以用户为准，不再恢复
    saved = '';
    applied = '';
  }
  final ssid = read.ssid;
  final target = ssid == null ? null : modes[ssid];
  if (target != null) {
    if (current == target) return MuseWifiModeStep(saved: saved, applied: applied.isEmpty ? '' : target.key);
    return MuseWifiModeStep(setTo: target, saved: saved.isEmpty ? current.key : saved, applied: target.key);
  }
  if (saved.isNotEmpty) {
    final back = MuseRouteMode.fromKey(saved);
    return MuseWifiModeStep(setTo: back == current ? null : back, saved: '', applied: '');
  }
  return MuseWifiModeStep(saved: saved, applied: applied);
}

/// Android：Wi‑Fi 连上 / 断开事件（Kotlin ChuanyunWifiWatch，只在订阅时注册）；测试可覆盖。
final museWifiEventsProvider = Provider<Stream<Object?>>((ref) {
  if (!PlatformUtils.isAndroid) return const Stream.empty();
  return const EventChannel('com.chuanyun.app/network').receiveBroadcastStream();
});

/// 事件到检查之间等一下（Wi‑Fi 刚连上时名称可能还读不到）；只是一次性的延迟，不是轮询。
const museWifiModeSettle = Duration(seconds: 2);

final museWifiModeProvider = Provider<void>((ref) {
  if (!PlatformUtils.isWindows && !PlatformUtils.isAndroid && !ref.watch(museOnDemandForceProvider)) return;
  final modes = museParseWifiModes(ref.watch(MusePrefs.wifiModes));
  if (modes.isEmpty) {
    // 列表清空：把我们切过的模式还回去
    final saved = ref.read(MusePrefs.wifiModeSaved);
    if (saved.isNotEmpty) {
      Future.microtask(() async {
        if (ref.read(ConfigOptions.museRouteMode).key == ref.read(MusePrefs.wifiModeApplied)) {
          await ref.read(ConfigOptions.museRouteMode.notifier).update(MuseRouteMode.fromKey(saved));
        }
        await ref.read(MusePrefs.wifiModeSaved.notifier).update('');
        await ref.read(MusePrefs.wifiModeApplied.notifier).update('');
      });
    }
    return;
  }
  final read = ref.read(museSsidReaderProvider);
  var busy = false;
  Future<void> check() async {
    if (busy) return;
    busy = true;
    try {
      final r = await read();
      final step = museWifiModeStep(
        modes: modes,
        read: r,
        current: ref.read(ConfigOptions.museRouteMode),
        saved: ref.read(MusePrefs.wifiModeSaved),
        applied: ref.read(MusePrefs.wifiModeApplied),
      );
      await ref.read(MusePrefs.wifiModeSaved.notifier).update(step.saved);
      await ref.read(MusePrefs.wifiModeApplied.notifier).update(step.applied);
      final to = step.setTo;
      if (to != null) {
        await ref.read(ConfigOptions.museRouteMode.notifier).update(to);
        try {
          ref
              .read(inAppNotificationControllerProvider)
              .showInfoToast(r.ssid != null && modes.containsKey(r.ssid) ? '已连接 Wi‑Fi「${r.ssid}」，切换为${to.title}模式' : '已离开指定 Wi‑Fi，恢复为${to.title}模式');
        } catch (_) {}
      }
    } catch (_) {
      // 下次网络变化再试
    } finally {
      busy = false;
    }
  }

  Timer? settle;
  void soon() {
    settle?.cancel();
    settle = Timer(museWifiModeSettle, check);
  }

  soon(); // 打开穿云 / 列表变化时检查一次
  final sub = ref.read(museWifiEventsProvider).listen((_) => soon(), onError: (_) {});
  AppLifecycleListener? lifecycle;
  try {
    lifecycle = AppLifecycleListener(onResume: soon);
  } catch (_) {}
  ref.onDispose(() {
    settle?.cancel();
    unawaited(sub.cancel());
    lifecycle?.dispose();
  });
});
