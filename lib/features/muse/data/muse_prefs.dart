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

  /// small / normal / large / huge — 1.4.0–1.5.x 字体大小; 1.6.0 C7 migrates it into 文字缩放 and
  /// no longer reads it (kept so an older device's backup still restores).
  static final textSize = PreferencesNotifier.create<String, String>("muse_text_size", "normal");

  /// 1.6.0 C7 文字缩放: on/off and the factor in percent (80–140, steps of 5), independent of the
  /// system font size.
  static final textScaleOn = PreferencesNotifier.create<bool, bool>("muse_text_scale_on", false);
  static final textScalePct = PreferencesNotifier.create<int, int>("muse_text_scale_pct", 100);

  /// 1.6.0 C7: saved custom 主题色 ("#RRGGBB,…", newest first)
  static final customAccents = PreferencesNotifier.create<String, String>("muse_custom_accents", "");

  /// 隐私模式: 首页 numbers blurred
  static final privacyMask = PreferencesNotifier.create<bool, bool>("muse_privacy_mask", false);

  /// 节假日云朵小彩蛋
  static final holidayClouds = PreferencesNotifier.create<bool, bool>("muse_holiday_clouds", true);
  static final onboardingDone = PreferencesNotifier.create<bool, bool>("muse_onboarding_done", false);

  /// 1.5.0: the version whose 更新内容 the user has seen (dialog or 关于 › 更新内容)
  static final changelogSeen = PreferencesNotifier.create<String, String>("muse_changelog_seen", "");

  /// Android: a short vibration when connected (off: 震动 was removed on request in 1.1)
  static final haptics = PreferencesNotifier.create<bool, bool>("muse_haptics", false);

  // ---- 1.6.0 外壳与外观
  /// bottom bar on a phone: floating (default) / docked
  static final dockStyle = PreferencesNotifier.create<String, String>("muse_dock_style", "floating");

  /// tab switch: fade (default) / slide
  static final tabAnimation = PreferencesNotifier.create<String, String>("muse_tab_animation", "fade");

  /// the wide-window sidebar shows labels
  static final sidebarExpanded = PreferencesNotifier.create<bool, bool>("muse_sidebar_expanded", true);

  /// 日志记录: live logs are only collected (and 日志 only shown) while this is on
  static final logCapture = PreferencesNotifier.create<bool, bool>("muse_log_capture", false);

  /// 1.6.0 C3: hosts blocked from 连接 › 屏蔽此域名 (JSON list), one 拦截 rule
  static final blockedHosts = PreferencesNotifier.create<String, String>("muse_blocked_hosts", "[]");

  /// 1.6.0 C3 (G72): switching node closes the connections still on the old one
  static final autoCloseConnections = PreferencesNotifier.create<bool, bool>("muse_auto_close_connections", true);

  // ---- 节点
  /// rename / note / hidden by tag (logic/node_tools.dart MuseNodeMetas)
  static final nodeMeta = PreferencesNotifier.create<String, String>("muse_node_meta", "");
  static final beautifyNames = PreferencesNotifier.create<bool, bool>("muse_beautify_names", false);
  static final includeRegex = PreferencesNotifier.create<String, String>("muse_node_include", "");
  static final excludeRegex = PreferencesNotifier.create<String, String>("muse_node_exclude", "");
  static final hideDuplicates = PreferencesNotifier.create<bool, bool>("muse_hide_duplicates", false);
  /// 1.6.0 #31: what makes two nodes duplicates: protocol (+ address + port, the default) /
  /// address (address + port) / full (every setting)
  static final dedupMode = PreferencesNotifier.create<String, String>("muse_dedup_mode", "protocol");

  /// 1.6.0 C5: 节点 layout (list / grid) and density (compact / standard / loose)
  static final nodeLayout = PreferencesNotifier.create<String, String>("muse_node_layout", "list");
  static final nodeDensity = PreferencesNotifier.create<String, String>("muse_node_density", "standard");

  /// 1.6.0 #34: favourites follow the user's own order (the order of muse_favorite_nodes)
  static final favoriteManualOrder = PreferencesNotifier.create<bool, bool>("muse_favorite_manual_order", false);

  /// 1.6.0 C6: the user's order of subscriptions (comma list of ids; never deletes one)
  static final profileOrder = PreferencesNotifier.create<String, String>("muse_profile_order", "");
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

  /// Wi‑Fi rules (Windows; experimental). 1.6.0 C8 按需运行 keeps its Wi‑Fi list here as
  /// `{"SSID": "disconnect"}` entries.
  static final wifiRules = PreferencesNotifier.create<String, String>("muse_wifi_rules", "");

  // ---- 1.6.0 C9 Android (per device, not synced)
  /// 自动运行: connect when 穿云 is opened (cold start only, once per launch)
  static final autoRun = PreferencesNotifier.create<bool, bool>("muse_auto_run", false);

  /// 通知栏「断开」按钮 (read by the Android notification, flutter.muse_notify_stop_button)
  static final notifyStopButton = PreferencesNotifier.create<bool, bool>("muse_notify_stop_button", true);

  /// 分应用代理 list: sort (selected / name / installed) and 只看联网应用
  static final appSort = PreferencesNotifier.create<String, String>("muse_app_sort", "selected");
  static final appInternetOnly = PreferencesNotifier.create<bool, bool>("muse_app_internet_only", false);

  // ---- 1.6.0 C8 电脑 (Windows; per device, not synced)
  /// 按需运行: pause the connection on the listed Wi‑Fi, resume after leaving it
  static final onDemand = PreferencesNotifier.create<bool, bool>("muse_on_demand", false);

  /// 全局快捷键: master switch + bindings (desktop/hotkeys.dart, JSON action → "ctrl+shift+0x70004")
  static final hotkeysOn = PreferencesNotifier.create<bool, bool>("muse_hotkeys_on", true);
  static final hotkeys = PreferencesNotifier.create<String, String>("muse_hotkeys", "");

  /// 自绘标题栏 (off = the system title bar); 窗口置顶 is [alwaysOnTop] below
  static final customTitleBar = PreferencesNotifier.create<bool, bool>("muse_custom_title_bar", true);

  /// 开机自启时静默: a start by 开机自启 (`--autostart`) stays in the tray
  static final autostartSilent = PreferencesNotifier.create<bool, bool>("muse_autostart_silent", false);

  // ---- 同步 (1.4.1: 局域网同步 first; WebDAV — any server — under 更多)
  static final webdavUrl = PreferencesNotifier.create<String, String>("muse_webdav_url", "");
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

  // ---- 1.4.1
  /// the VPN start (connectedSince) already reported as killed in the background
  static final killReported = PreferencesNotifier.create<int, int>("muse_kill_reported", 0);

  /// times 穿云 was found killed in the background
  static final killCount = PreferencesNotifier.create<int, int>("muse_kill_count", 0);

  /// the app version of the previous start (an update kills the service too)
  static final lastRunVersion = PreferencesNotifier.create<String, String>("muse_last_run_version", "");

  /// the slot the schedule fired last (logic/net_tools.dart museScheduleDue)
  static final scheduleLastFired = PreferencesNotifier.create<int, int>("muse_schedule_last_fired", -1);

  // ---- 更新
  // 1.5.1: the 1.4.1 Beta 通道 switch is gone (no prereleases are published); a stored
  // "muse_beta_channel" value is simply no longer read.

  // ---- 1.6.0 C10
  /// 开发者选项 shown in 设置 (tap 关于 › 版本 7 times); this device only, never synced
  static final devMode = PreferencesNotifier.create<bool, bool>("muse_dev_mode", false);

  // ---- Windows (1.6.0 C8: 窗口置顶, used by the title bar and 设置 › 电脑)
  static final alwaysOnTop = PreferencesNotifier.create<bool, bool>("muse_always_on_top", false);

  /// last window bounds "x,y,w,h"
  static final windowBounds = PreferencesNotifier.create<String, String>("muse_window_bounds", "");
  static final proxyBypass = PreferencesNotifier.create<String, String>("muse_proxy_bypass", "");

  // ---- 1.5.0 (chunk 2); network-affecting ones start off and sit under 设置 › 高级
  /// IPv6: off / prefer_v4 / prefer_v6 (logic/net_tools.dart MuseIpv6Policy)
  static final ipv6Policy = PreferencesNotifier.create<String, String>("muse_ipv6_policy", "off");

  /// 1.5.0 #9: refuse QUIC (UDP 443) so sites fall back to TCP; off by default.
  static final blockQuic = PreferencesNotifier.create<bool, bool>("muse_block_quic", false);

  /// subscription download: auto / proxy / direct (logic/sub_tools.dart MuseSubFetch)
  static final subFetch = PreferencesNotifier.create<String, String>("muse_sub_fetch", "auto");

  /// 只显示 / 排除 per subscription: JSON {profileId: {include, exclude}}
  static final subFilters = PreferencesNotifier.create<String, String>("muse_sub_filters", "{}");

  /// the core's last log lines when it stopped with an error (redacted), for 诊断
  static final coreTail = PreferencesNotifier.create<String, String>("muse_core_tail", "");

  /// 1.5.3: last 出口 results (logic/exit_check.dart MuseExitCache); local only, never synced
  static final exitCache = PreferencesNotifier.create<String, String>("muse_exit_cache", "");
}

/// 1.6.0 C7 文字缩放 range (percent).
const museTextScaleMin = 80;
const museTextScaleMax = 140;
const museTextScaleStep = 5;

/// [pct] clamped to the range and snapped to the step.
int museClampTextScalePct(int pct) {
  final c = pct.clamp(museTextScaleMin, museTextScaleMax);
  return ((c / museTextScaleStep).round() * museTextScaleStep).clamp(museTextScaleMin, museTextScaleMax);
}

/// The app's own text factor (on top of the system's): 1.0 while 文字缩放 is off.
double museTextScale(bool on, int pct) => on ? museClampTextScalePct(pct) / 100 : 1.0;

/// The 1.4.0 字体大小 value as a 文字缩放 percent (null = 标准 / unknown: leave 文字缩放 off).
int? museLegacyTextSizePct(Object? key) => switch (key) {
  'small' => 90,
  'large' => 110,
  'huge' => 120,
  _ => null,
};

/// "1.10×"
String museTextScaleLabel(int pct) => '${(museClampTextScalePct(pct) / 100).toStringAsFixed(2)}×';

/// Preference keys that go into 同步 / 备份 (settings that make sense on another device).
const museSyncedPrefKeys = [
  'muse_accent',
  'muse_text_size',
  'muse_text_scale_on',
  'muse_text_scale_pct',
  'muse_custom_accents',
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
  'muse_sub_fetch',
  'muse_dock_style',
  'muse_blocked_hosts',
  'muse_tab_animation',
];
