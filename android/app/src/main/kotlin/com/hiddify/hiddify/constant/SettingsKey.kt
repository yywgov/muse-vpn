package com.hiddify.hiddify.constant

object SettingsKey {
    private const val KEY_PREFIX = "flutter."

    const val SERVICE_MODE = "${KEY_PREFIX}service-mode"
    const val ACTIVE_CONFIG_PATH = "${KEY_PREFIX}active_config_path"
    const val ACTIVE_PROFILE_NAME = "${KEY_PREFIX}active_profile_name"

    const val PER_APP_PROXY_ENABLED = "${KEY_PREFIX}per_app_proxy_enabled"
    const val PER_APP_PROXY_MODE = "${KEY_PREFIX}per_app_proxy_mode"
    const val PER_APP_PROXY_INCLUDE_LIST = "${KEY_PREFIX}per_app_proxy_include_list"
    const val PER_APP_PROXY_EXCLUDE_LIST = "${KEY_PREFIX}per_app_proxy_exclude_list"

    const val DEBUG_MODE = "${KEY_PREFIX}debug_mode"
    const val DISABLE_MEMORY_LIMIT = "${KEY_PREFIX}disable_memory_limit"
    const val DYNAMIC_NOTIFICATION = "${KEY_PREFIX}dynamic_notification"
    const val SYSTEM_PROXY_ENABLED = "${KEY_PREFIX}system_proxy_enabled"

    // 穿云 privacy / automation (written by the Flutter side, read here)
    const val HIDE_NOTIFICATION = "${KEY_PREFIX}hide_notification"
    const val EXCLUDE_FROM_RECENTS = "${KEY_PREFIX}exclude_from_recents"
    // 穿云 1.6.0 C9: the 「断开」 button on the connection notification (default on)
    const val NOTIFY_STOP_BUTTON = "${KEY_PREFIX}muse_notify_stop_button"
    // 穿云 1.7.0: 内核 (standard | compat), written by the Flutter side
    const val CORE_KIND = "${KEY_PREFIX}muse_core_kind"
    // 穿云 1.2.1: 按网络自动开关 removed; these keys are only deleted (RemovedFeatures)
    const val NET_AUTO_ENABLED = "${KEY_PREFIX}net_auto_enabled"
    const val NET_TRUSTED_SSIDS = "${KEY_PREFIX}net_trusted_ssids"
    const val NET_AUTO_PAUSED = "${KEY_PREFIX}net_auto_paused"
    const val CONNECTED_SINCE = "${KEY_PREFIX}connected_since"

    // cache

    const val STARTED_BY_USER = "${KEY_PREFIX}started_by_user"
    const val CONFIG_OPTIONS = "config_options_json"

    const val START_CORE_ON_STARTING_SERVICE = "${KEY_PREFIX}starting_core_on_starting_service"

    const val WORKING_DIR = "working_dir"
    const val BASE_DIR = "base_dir"
    const val TMP_DIR = "tmp_dir"

    const val GRPC_PORT = "grpc_port"
    const val GRPC_FLUTTER_PUBLIC_KEY = "grpc_flutter_public_key"
}