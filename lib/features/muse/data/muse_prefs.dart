// 穿云 1.4.0 - preferences added in 1.4 (one place, so sync / backup can list them).
// Conservative defaults: anything experimental or network-affecting starts off.
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';

abstract final class MusePrefs {
  // ---- 测速
  /// last delay per node of the active subscription (logic/latency_cache.dart)
  static final latencyCache = PreferencesNotifier.create<String, String>("muse_latency_cache", "");
  static final testWorkers = PreferencesNotifier.create<int, int>("muse_test_workers", museTestWorkersDefault);
  static final testTimeoutSec = PreferencesNotifier.create<int, int>("muse_test_timeout_sec", museTestTimeoutDefault);
  /// recent delays per node (logic/node_tools.dart MuseDelayHistories)
  static final delayHistory = PreferencesNotifier.create<String, String>("muse_delay_history", "");

  // ---- 外观
  static final accent = PreferencesNotifier.create<String, String>("muse_accent", "blue");

  /// small / normal / large / huge
  static final textSize = PreferencesNotifier.create<String, String>("muse_text_size", "normal");

  /// 隐私模式: 首页 numbers blurred
  static final privacyMask = PreferencesNotifier.create<bool, bool>("muse_privacy_mask", false);

  /// 节假日云朵小彩蛋
  static final holidayClouds = PreferencesNotifier.create<bool, bool>("muse_holiday_clouds", true);
  static final onboardingDone = PreferencesNotifier.create<bool, bool>("muse_onboarding_done", false);

  /// Android: a short vibration when connected (off: 震动 was removed on request in 1.1)
  static final haptics = PreferencesNotifier.create<bool, bool>("muse_haptics", false);

  // ---- 节点
  /// rename / note / hidden by tag (logic/node_tools.dart MuseNodeMetas)
  static final nodeMeta = PreferencesNotifier.create<String, String>("muse_node_meta", "");
  static final beautifyNames = PreferencesNotifier.create<bool, bool>("muse_beautify_names", false);
  static final includeRegex = PreferencesNotifier.create<String, String>("muse_node_include", "");
  static final excludeRegex = PreferencesNotifier.create<String, String>("muse_node_exclude", "");
  static final hideDuplicates = PreferencesNotifier.create<bool, bool>("muse_hide_duplicates", false);
  static final recentNodes = PreferencesNotifier.create<String, String>("muse_recent_nodes", "");

  /// protocol filter on 节点 ('' = all)
  static final protocolFilter = PreferencesNotifier.create<String, String>("muse_protocol_filter", "");

  /// collapsed country groups on 节点 (comma list of codes, 'other')
  static final collapsedRegions = PreferencesNotifier.create<String, String>("muse_collapsed_regions", "");

  /// sites / apps through one node: JSON list of {"domain_suffix": [...], "process_name": [...],
  /// "package_name": [...], "outbound": tag}
  static final nodeRules = PreferencesNotifier.create<String, String>("muse_node_rules", "[]");

  // ---- 订阅
  /// subscription download user agent (logic/sub_tools.dart museUserAgents)
  static final subUserAgent = PreferencesNotifier.create<String, String>("muse_sub_user_agent", "auto");

  /// last node names per subscription, for 「新增 / 移除」 after an update
  static final subNodeNames = PreferencesNotifier.create<String, String>("muse_sub_node_names", "{}");

  // ---- 分流
  /// enabled presets with their way (logic/rules_tools.dart)
  static final rulePresets = PreferencesNotifier.create<String, String>("muse_rule_presets", "");
  static final hosts = PreferencesNotifier.create<String, String>("muse_hosts", "");

  /// remote rule-sets: JSON list of {"url": …, "outbound": "proxy|direct|block"}
  static final remoteRuleSets = PreferencesNotifier.create<String, String>("muse_remote_rule_sets", "[]");

  /// 全局模式 also sends 中国大陆 direct
  static final globalBypassCn = PreferencesNotifier.create<bool, bool>("muse_global_bypass_cn", false);

  /// UDP: on (default) / off (blocked, e.g. to force TCP)
  static final udpEnabled = PreferencesNotifier.create<bool, bool>("muse_udp_enabled", true);

  // ---- 连接
  /// connect when the app starts (Windows sign-in / Android after a reboot open the app)
  static final connectOnStart = PreferencesNotifier.create<bool, bool>("muse_connect_on_start", false);
  static final dnsPreset = PreferencesNotifier.create<String, String>("muse_dns_preset", "default");

  /// 定时连接 / 断开 ("connectMinute,disconnectMinute", -1 = off)
  static final schedule = PreferencesNotifier.create<String, String>("muse_schedule", "-1,-1");
  static final qualityAlert = PreferencesNotifier.create<bool, bool>("muse_quality_alert", false);

  /// Wi‑Fi rules (Windows; experimental)
  static final wifiRules = PreferencesNotifier.create<String, String>("muse_wifi_rules", "");

  // ---- 同步 (坚果云 WebDAV)
  static final webdavUrl = PreferencesNotifier.create<String, String>("muse_webdav_url", "https://dav.jianguoyun.com/dav/");
  static final webdavUser = PreferencesNotifier.create<String, String>("muse_webdav_user", "");
  static final webdavPassword = PreferencesNotifier.create<String, String>("muse_webdav_password", "");

  /// separate encryption password ('' = the app password above)
  static final syncPassphrase = PreferencesNotifier.create<String, String>("muse_sync_passphrase", "");
  static final syncAuto = PreferencesNotifier.create<bool, bool>("muse_sync_auto", false);
  static final syncLast = PreferencesNotifier.create<String, String>("muse_sync_last", "");
  static final syncLastAt = PreferencesNotifier.create<int, int>("muse_sync_last_at", 0);
  static final deviceId = PreferencesNotifier.create<String, String>("muse_device_id", "");

  // ---- 统计
  static final trafficLog = PreferencesNotifier.create<String, String>("muse_traffic_log", "");
  static final connectStats = PreferencesNotifier.create<String, String>("muse_connect_stats", "");
  static final crashLog = PreferencesNotifier.create<String, String>("muse_crash_log", "");

  // ---- 安全
  /// 应用锁: '' = off, otherwise 'pin' / 'bio'
  static final appLock = PreferencesNotifier.create<String, String>("muse_app_lock", "");

  /// salted SHA-256 of the PIN
  static final appLockPin = PreferencesNotifier.create<String, String>("muse_app_lock_pin", "");

  // ---- 更新
  static final betaChannel = PreferencesNotifier.create<bool, bool>("muse_beta_channel", false);

  // ---- Windows
  static final alwaysOnTop = PreferencesNotifier.create<bool, bool>("muse_always_on_top", false);

  /// last window bounds "x,y,w,h"
  static final windowBounds = PreferencesNotifier.create<String, String>("muse_window_bounds", "");
  static final proxyBypass = PreferencesNotifier.create<String, String>("muse_proxy_bypass", "");
}

/// 字体大小 choices.
const museTextSizes = [('small', '小'), ('normal', '标准'), ('large', '大'), ('huge', '特大')];

double museTextScale(String key) => switch (key) {
  'small' => 0.92,
  'large' => 1.1,
  'huge' => 1.2,
  _ => 1.0,
};

/// Preference keys that go into 同步 / 备份 (settings that make sense on another device).
const museSyncedPrefKeys = [
  'muse_accent',
  'muse_text_size',
  'muse_privacy_mask',
  'muse_holiday_clouds',
  'muse_node_meta',
  'muse_beautify_names',
  'muse_node_include',
  'muse_node_exclude',
  'muse_hide_duplicates',
  'muse_node_rules',
  'muse_sub_user_agent',
  'muse_rule_presets',
  'muse_hosts',
  'muse_remote_rule_sets',
  'muse_global_bypass_cn',
  'muse_udp_enabled',
  'muse_dns_preset',
  'muse_quality_alert',
  'muse_test_workers',
  'muse_test_timeout_sec',
  'muse_favorite_nodes',
  'muse_node_sort',
  'muse_ad_block_level',
  'muse_keep_alive',
  'muse_auto_update_hours',
  'muse_home_tile_order',
  'muse_home_tiles_hidden',
  'muse_route_mode',
];
