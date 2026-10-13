import 'package:flutter/material.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

abstract class Preferences {
  // 穿云: no first-run intro (region is fixed to cn, language to 简体中文)
  static final introCompleted = PreferencesNotifier.create("intro_completed", true, overrideValue: true);

  // 穿云 隐私 (read by the Android side too)
  static final hideNotification = PreferencesNotifier.create<bool, bool>("hide_notification", false);
  static final excludeFromRecents = PreferencesNotifier.create<bool, bool>("exclude_from_recents", false);

  // 穿云 按网络自动开关: trusted Wi-Fi names are kept one per line (read by the Android side)
  static final netAutoEnabled = PreferencesNotifier.create<bool, bool>("net_auto_enabled", false);
  static final netTrustedSsids = PreferencesNotifier.create<String, String>("net_trusted_ssids", "");

  // 穿云: switch the main group to 自动最快 when the hand-picked node stops answering (always on since 1.1)
  static final nodeFailover = PreferencesNotifier.create<bool, bool>("node_failover", true, overrideValue: true);

  // 穿云 1.1: 后台运行/自启动 guide shown once on the first connect; 自启动 can't be read back from
  // ColorOS, so having opened its settings page once counts as done
  static final keepAliveGuideShown = PreferencesNotifier.create<bool, bool>("keep_alive_guide_shown", false);
  static final autostartVisited = PreferencesNotifier.create<bool, bool>("autostart_visited", false);

  // 穿云 1.1: 去广告 became part of the built-in default rules (turned on once for existing lists)
  static final adsDefaultMigrated = PreferencesNotifier.create<bool, bool>("ads_default_migrated", false);

  // 穿云 1.1: the last clipboard text offered for import (never offered twice)
  static final clipboardLastOffered = PreferencesNotifier.create<String, String>("clipboard_last_offered", "");

  // 穿云 1.1: subscription alerts already sent ("<profile id>:<kind>:<expire>" one per line)
  static final subscriptionAlertsSent = PreferencesNotifier.create<String, String>("subscription_alerts_sent", "");

  // 穿云 1.0: 负载均衡 used to be the default pick of the main group; moved once to 自动最快
  static final autoFastestMigrated = PreferencesNotifier.create<bool, bool>("auto_fastest_migrated", false);

  // Null means that auto selection has not been performed yet.
  static final autoAppsSelectionRegion = PreferencesNotifier.create<Region?, String?>(
    "auto_apps_selection_region",
    null,
    mapFrom: (value) => value == null || value.isEmpty ? null : Region.values.byName(value),
    mapTo: (value) => value == null ? '' : value.name,
  );

  static final autoAppsSelectionLastUpdate = PreferencesNotifier.create<DateTime?, String?>(
    "auto_apps_selection_last_update",
    null,
    mapFrom: (value) => value == null ? null : DateTime.tryParse(value),
    mapTo: (value) => value?.toIso8601String(),
  );

  // Set when the user turns auto selection off by hand. Until then it comes on by itself when App-based routing
  // is turned on or its mode changes.
  static final autoAppsSelectionOffByUser = PreferencesNotifier.create<bool, bool>(
    "auto_apps_selection_off_by_user",
    false,
  );

  static final includeApps = PreferencesNotifier.create<List<String>, List<String>>(
    "per_app_proxy_include_list",
    <String>[],
  );

  static final excludeApps = PreferencesNotifier.create<List<String>, List<String>>(
    "per_app_proxy_exclude_list",
    <String>[],
  );

  static final windowMaximized = PreferencesNotifier.create<bool, bool>("window_maximized", false);

  static final windowPosition = PreferencesNotifier.create<Offset?, String?>(
    "window_position",
    null,
    mapFrom: (value) {
      if (value == null) return null;
      final list = value.split(',').map((e) => double.tryParse(e)).toList();
      return Offset(list[0]!, list[1]!);
    },
    mapTo: (value) {
      if (value == null) return null;
      return "${value.dx},${value.dy}";
    },
  );

  static final windowSize = PreferencesNotifier.create<Size, String>(
    "window_size",
    defaultWindowSize,
    mapFrom: (value) {
      final list = value.split(',').map((e) => double.tryParse(e)).toList();
      return Size(list[0]!, list[1]!);
    },
    mapTo: (value) => "${value.width},${value.height}",
  );

  static final silentStart = PreferencesNotifier.create<bool, bool>("silent_start", false);

  static final disableMemoryLimit = PreferencesNotifier.create<bool, bool>(
    "disable_memory_limit",
    // disable memory limit on desktop by default
    PlatformUtils.isDesktop,
  );

  // 穿云: on by default, with the built-in 「常用国内 App 不走代理」 preset (see AppBasedRouting)
  static final perAppProxyEnabled = PreferencesNotifier.create<bool, bool>("per_app_proxy_enabled", true);

  // 穿云: set once the first-run per-app defaults were written
  static final cnAppPresetInitialized = PreferencesNotifier.create<bool, bool>("cn_app_preset_initialized", false);

  // Kept while App-based routing is off, for when it is turned on again.
  static final perAppProxyMode = PreferencesNotifier.create<AppProxyMode, String>(
    "per_app_proxy_mode",
    AppProxyMode.exclude,
    mapFrom: AppProxyMode.values.byName,
    mapTo: (value) => value.name,
  );

  // The mode in use, or null while App-based routing is off.
  static final perAppProxyModeInUse = Provider<AppProxyMode?>(
    (ref) => ref.watch(perAppProxyEnabled) ? ref.watch(perAppProxyMode) : null,
  );

  static final markNewProfileActive = PreferencesNotifier.create<bool, bool>("mark_new_profile_active", true);


  static final autoCheckIp = PreferencesNotifier.create<bool, bool>("auto_check_ip", true);

  static final startedByUser = PreferencesNotifier.create<bool, bool>("started_by_user", false);

  static final storeReviewedByUser = PreferencesNotifier.create<bool, bool>("store_reviewed_by_user", false);

  static final actionAtClose = PreferencesNotifier.create<ActionsAtClosing, String>(
    "action_at_close",
    ActionsAtClosing.hide, // 穿云: closing the window keeps 穿云 running in the tray
    mapFrom: ActionsAtClosing.values.byName,
    mapTo: (value) => value.name,
  );

  static final warpConsentGiven = PreferencesNotifier.create<bool, bool>("warp-consent-given", false);

  static final psiphonConsentGiven = PreferencesNotifier.create<bool, bool>("psiphon-consent-given", false);

  /// How many records the in-memory log ring keeps. Saved, so a size picked
  /// once while chasing a bug is still there on the next run.
  static final logBufferSize = PreferencesNotifier.create<int, int>("log-buffer-size", 1000);

  static final profilesSort = PreferencesNotifier.create<({ProfilesSort by, SortMode mode}), String>(
    "profiles_sort",
    (by: ProfilesSort.lastUpdate, mode: SortMode.descending),
    mapFrom: (value) {
      final parts = value.split(":");
      return (by: ProfilesSort.values.byName(parts.first), mode: SortMode.values.byName(parts.last));
    },
    mapTo: (value) => "${value.by.name}:${value.mode.name}",
  );
}
