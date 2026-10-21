import 'dart:async';

import 'package:dartx/dartx.dart';
import 'package:hiddify/features/muse/data/notify.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:meta/meta.dart';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_update_notifier.g.dart';

typedef ProfileUpdateStatus = ({String name, bool success});

/// 穿云 1.1: subscriptions update at least every 12 hours (sooner when the provider asks for it);
/// a failed update keeps the old nodes (the new config is validated before it replaces the old).
/// 1.2.8: the 12 hours are a setting (设置 › 订阅自动更新: 关闭 / 6 / 12 / 24 小时).
const museSubscriptionUpdateInterval = Duration(hours: 12);

/// Choices offered in 设置 (0 = 关闭).
const museAutoUpdateChoices = [0, 6, 12, 24];

String museAutoUpdateLabel(int hours) => hours <= 0 ? '关闭' : '每 $hours 小时';

/// How often a subscription updates on its own; null when the user switched it off.
Duration? museEffectiveUpdateInterval(Duration? fromProvider, {int hours = 12}) {
  if (hours <= 0) return null;
  final mine = Duration(hours: hours);
  return fromProvider == null || fromProvider <= Duration.zero || fromProvider > mine ? mine : fromProvider;
}

@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const prefKey = "profiles_update_check";
  static const interval = Duration(minutes: 15);

  @override
  Stream<ProfileUpdateStatus?> build() {
    var cycleCount = 0;
    _scheduler = NeatPeriodicTaskScheduler(
      name: 'profiles update worker',
      interval: interval,
      timeout: const Duration(minutes: 5),
      task: () async {
        loggy.debug("cycle [${cycleCount++}]");
        await updateProfiles();
      },
    );

    ref.onDispose(() async {
      await _scheduler?.stop();
      _scheduler = null;
    });

    if (ref.watch(Preferences.introCompleted)) {
      loggy.debug("intro done, starting");
      _scheduler?.start();
    } else {
      loggy.debug("intro in process, skipping");
    }
    return const Stream.empty();
  }

  NeatPeriodicTaskScheduler? _scheduler;
  bool _forceNextRun = false;

  Future<void> trigger() async {
    loggy.debug("triggering update");
    _forceNextRun = true;
    await _scheduler?.trigger();
  }

  @visibleForTesting
  Future<void> updateProfiles() async {
    var force = false;
    if (_forceNextRun) {
      force = true;
      _forceNextRun = false;
    }

    try {
      final previousRun = DateTime.tryParse(ref.read(sharedPreferencesProvider).requireValue.getString(prefKey) ?? "");

      if (!force && previousRun != null && previousRun.add(interval) > DateTime.now()) {
        loggy.debug("too soon! previous run: [$previousRun]");
        return;
      }
      loggy.debug("${force ? "[FORCED] " : ""}running, previous run: [$previousRun]");

      final remoteProfiles = await ref
          .read(profileRepositoryProvider)
          .requireValue
          .watchAll()
          .map(
            (event) => event.getOrElse((f) {
              loggy.error("error getting profiles");
              throw f;
            }).whereType<RemoteProfileEntity>(),
          )
          .first;

      final toUpdate = remoteProfiles.where((profile) {
        final updateInterval = museEffectiveUpdateInterval(
          profile.options?.updateInterval,
          hours: ref.read(Preferences.museAutoUpdateHours),
        );
        final shouldUpdate =
            force || (updateInterval != null && updateInterval <= DateTime.now().difference(profile.lastUpdate));
        if (!shouldUpdate) {
          loggy.debug(
            "skipping profile [${profile.id}] update. last successful update: [${profile.lastUpdate}] - interval: [${profile.options?.updateInterval}]",
          );
        }
        return shouldUpdate;
      }).toList();

      var successCount = 0;
      final failedNames = <String>[];
      // Sequential on purpose: validation and the active-profile reconnect share
      // one native core that is not safe to call concurrently (it can hang).
      for (final profile in toUpdate) {
        await ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile, isBulk: true);
        if (ref.read(updateProfileNotifierProvider(profile.id)).hasError) {
          failedNames.add(profile.name);
        } else {
          successCount++;
        }
      }

      if (successCount > 0 || failedNames.isNotEmpty) {
        final t = ref.read(translationsProvider).requireValue;
        final notification = ref.read(inAppNotificationControllerProvider);
        if (failedNames.isEmpty) {
          notification.showSuccessToast(t.pages.profiles.msg.update.bulkSuccess(count: successCount));
        } else {
          // 1.2.8: a system notification too (the window may be hidden in the tray)
          unawaited(museNotify(id: 2103, title: '订阅更新失败', text: '${failedNames.join('、')}，已保留原有节点'));
          // 1.2.8: say plainly that the old nodes are kept
          notification.showErrorToast(
            '${t.pages.profiles.msg.update.bulkPartial(
              success: successCount,
              failed: failedNames.length,
              names: failedNames.join(", "),
            )}（已保留原有节点）',
          );
        }
      }
    } finally {
      await ref.read(sharedPreferencesProvider).requireValue.setString(prefKey, DateTime.now().toIso8601String());
    }
  }
}
