// 穿云 1.18.0 P6 - 动效三档：外观 › 动效（跟随系统 / 标准 / 精简 / 关闭）+ Android 省电模式。
// 省电模式由 Kotlin ChuanyunPowerWatch 推送（动态注册 ACTION_POWER_SAVE_MODE_CHANGED，只在订阅时注册，
// 不轮询）；只有选「跟随系统」时才订阅。系统「移除动画」在界面里读（museMotionLevel）。
// Part of 穿云 (GPLv3).

import 'package:flutter/services.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/widget/muse_motion.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const musePowerChannel = 'com.chuanyun.app/power';

/// Android：省电模式开关事件（订阅时先推一次当前值）；其他平台没有；测试可覆盖。
final musePowerSaveEventsProvider = Provider<Stream<Object?>>((ref) {
  if (!PlatformUtils.isAndroid) return const Stream.empty();
  return const EventChannel(musePowerChannel).receiveBroadcastStream();
});

final museMotionChoiceProvider = Provider<MuseMotionChoice>((ref) => MuseMotionChoice.fromKey(ref.watch(MusePrefs.motionLevel)));

/// 省电模式是否开启；手动选了档位时不订阅（系统广播接收器也随之注销）。
final musePowerSaveProvider = StreamProvider<bool>((ref) {
  if (ref.watch(museMotionChoiceProvider) != MuseMotionChoice.auto) return Stream.value(false);
  return ref.watch(musePowerSaveEventsProvider).map((e) => e == true || e == 'on');
});

/// 应用层档位（不含系统「移除动画」，那个由界面的 MediaQuery 决定）。
final museAppMotionLevelProvider = Provider<MuseMotionLevel>((ref) {
  final choice = ref.watch(museMotionChoiceProvider);
  final powerSave = ref.watch(musePowerSaveProvider).valueOrNull ?? false;
  return museResolveMotionLevel(choice: choice, systemDisable: false, powerSave: powerSave);
});
