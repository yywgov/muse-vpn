// 穿云 1.4.0 - 同步 and 本地备份 / 恢复. 1.11.0: WebDAV 同步, 局域网同步, 自动备份 and 每周本地快照 were
// removed; this is the backup file behind 关于 › 导出 / 导入配置 (same format as before).
// What is synced: the settings in [museSyncedPrefs] and the subscription links (`sub:<url>` →
// name). Subscriptions are only ever added by a sync, never deleted. The file on the server is
// always encrypted (AES-GCM, logic/sync_core.dart) with the sync password (or the app password).
// 1.4.1: the Dio client is closed after each sync, PBKDF2 runs off the UI thread, a device that
// never synced takes the existing values, a subscription deleted elsewhere is not resurrected.
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:math';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/restore_plan.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Settings that go into 备份 (导出 / 导入配置), with the provider to refresh after a change.
/// 1.11.0: 配色风格 and 文字缩放 (muse_color_style, muse_text_size, muse_text_scale_on / _pct) are no
/// longer settings: an older backup that has them still imports, and those entries are skipped.
final museSyncedPrefs = <String, ProviderOrFamily>{
  'muse_accent': MusePrefs.accent,
  'muse_dock_style': MusePrefs.dockStyle,
  'muse_blocked_hosts': MusePrefs.blockedHosts,
  'muse_tab_animation': MusePrefs.tabAnimation,
  'muse_custom_accents': MusePrefs.customAccents,
  'muse_privacy_mask': MusePrefs.privacyMask,
  'muse_node_meta': MusePrefs.nodeMeta,
  'muse_beautify_names': MusePrefs.beautifyNames,
  'muse_node_include': MusePrefs.includeRegex,
  'muse_node_exclude': MusePrefs.excludeRegex,
  'muse_hide_duplicates': MusePrefs.hideDuplicates,
  'muse_dedup_mode': MusePrefs.dedupMode,
  'muse_node_layout': MusePrefs.nodeLayout,
  'muse_node_density': MusePrefs.nodeDensity,
  'muse_favorite_manual_order': MusePrefs.favoriteManualOrder,
  'muse_rule_presets': MusePrefs.rulePresets,
  'muse_hosts': MusePrefs.hosts,
  'muse_dns_preset': MusePrefs.dnsPreset,
  'muse_test_workers': MusePrefs.testWorkers,
  'muse_test_timeout_sec': MusePrefs.testTimeoutSec,
  'muse_favorite_nodes': Preferences.museFavoriteNodes,
  'muse_node_sort': Preferences.museNodeSort,
  'muse_ad_block_level': Preferences.museAdBlockLevel,
  'muse_keep_alive': Preferences.museKeepAlive,
  'muse_auto_update_hours': Preferences.museAutoUpdateHours,
  'muse_home_tile_order': Preferences.museHomeTileOrder,
  'muse_home_tiles_hidden': Preferences.museHomeTilesHidden,
  'muse-route-mode': ConfigOptions.museRouteMode,
  // 1.4.1
  'muse_node_rules': MusePrefs.nodeRules,
  'muse_remote_rule_sets': MusePrefs.remoteRuleSets,
  'muse_sub_user_agent': MusePrefs.subUserAgent,
  // 1.5.0
  'muse_sub_fetch': MusePrefs.subFetch,
  // 1.9.0 #15
  'muse_sub_overrides': MusePrefs.subOverrides,
};


class MuseSyncException implements Exception {
  const MuseSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a sync / restore did.
class MuseSyncResult {
  const MuseSyncResult({this.changed = 0, this.subsAdded = 0});

  final int changed;
  final int subsAdded;

  String get summary {
    if (changed == 0 && subsAdded == 0) return '已是最新';
    return [if (changed > 0) '$changed 项设置已更新', if (subsAdded > 0) '新增 $subsAdded 个订阅'].join('，');
  }
}

class MuseSyncService {
  MuseSyncService(this.ref);

  final Ref ref;

  /// Current local values: synced settings + subscription links.
  Future<Map<String, Object?>> localValues() async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    final out = <String, Object?>{};
    for (final k in museSyncedPrefs.keys) {
      final v = prefs.get(k);
      if (v != null) out[k] = v;
    }
    for (final p in await _remoteProfiles()) {
      out['sub:${p.url}'] = p.name;
    }
    return out;
  }

  Future<List<RemoteProfileEntity>> _remoteProfiles() async {
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      final all = await repo.watchAll().first;
      return all.fold<List<RemoteProfileEntity>>((_) => const [], (l) => l.whereType<RemoteProfileEntity>().toList());
    } catch (_) {
      return const [];
    }
  }

  /// Writes [changes] (from a merge or a backup) on this device.
  Future<MuseSyncResult> apply(Map<String, Object?> changes) async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    var changed = 0;
    var added = 0;
    final have = {for (final p in await _remoteProfiles()) p.url};
    for (final e in changes.entries) {
      final k = e.key;
      final v = e.value;
      if (k.startsWith('sub:')) {
        // subscriptions are only added (a deletion elsewhere never removes one here)
        final url = k.substring(4);
        if (v == null || have.contains(url)) continue;
        try {
          final repo = await ref.read(profileRepositoryProvider.future);
          final name = '$v'.trim();
          final res = await repo.upsertRemote(url, userOverride: name.isEmpty ? null : UserOverride(name: name)).run();
          if (res.isRight()) added++;
        } catch (_) {}
        continue;
      }
      final provider = museSyncedPrefs[k];
      if (provider == null) continue;
      switch (v) {
        case null:
          await prefs.remove(k);
        case final bool b:
          await prefs.setBool(k, b);
        case final int i:
          await prefs.setInt(k, i);
        case final double d:
          await prefs.setDouble(k, d);
        case final String s:
          await prefs.setString(k, s);
        default:
          continue;
      }
      changed++;
      ref.invalidate(provider);
    }
    return MuseSyncResult(changed: changed, subsAdded: added);
  }

  String get deviceId => _deviceId;

  String get _deviceId {
    var id = ref.read(MusePrefs.deviceId);
    if (id.isEmpty) {
      final r = Random.secure();
      id = List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      ref.read(MusePrefs.deviceId.notifier).update(id);
    }
    return id;
  }

  /// A backup file's text. [password] empty = plain JSON; [redact] drops subscription links.
  Future<String> exportBackup({String password = '', bool redact = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var snap = MuseSnapshot({for (final e in (await localValues()).entries) e.key: MuseSyncEntry(e.value, now)}, device: _deviceId);
    if (redact) snap = museRedactSnapshot(snap);
    final plain = const JsonEncoder.withIndent('  ').convert(snap.toJson());
    return password.isEmpty ? plain : museEncryptAsync(plain, password);
  }

  /// 1.6.0 C10: a backup file's text read into a snapshot (decrypted with [password] when it is
  /// encrypted). Throws [MuseSyncException] with a readable message; changes nothing.
  Future<MuseSnapshot> readBackup(String text, {String password = ''}) async {
    String plain = text;
    if (museIsEncrypted(text)) {
      if (password.isEmpty) throw const MuseSyncException('这个备份已加密，请输入密码');
      try {
        plain = await museDecryptAsync(text, password);
      } on MuseCryptoException catch (e) {
        throw MuseSyncException('$e');
      }
    }
    final MuseSnapshot snap;
    try {
      snap = MuseSnapshot.fromJson(jsonDecode(plain) as Map<String, dynamic>);
    } catch (_) {
      throw const MuseSyncException('不是穿云的备份文件');
    }
    if (snap.entries.isEmpty) throw const MuseSyncException('备份里没有内容');
    return snap;
  }

  /// 1.6.0 C10: what restoring [snap] would change here (nothing is written).
  Future<MuseRestorePlan> planRestore(
    MuseSnapshot snap, {
    MuseRestoreScope scope = MuseRestoreScope.all,
    MuseRestoreStrategy strategy = MuseRestoreStrategy.merge,
  }) async => museRestorePlan(
    current: await localValues(),
    backup: snap.values,
    settingKeys: museSyncedPrefs.keys.toSet(),
    scope: scope,
    strategy: strategy,
  );

  /// 1.6.0 C10: carries out [plan] (1.11.0: no automatic backup first — 自动备份 was removed).
  /// Subscriptions are only added (the plan never holds a removal).
  Future<MuseSyncResult> applyRestore(MuseRestorePlan plan) async {
    if (plan.isEmpty) return const MuseSyncResult();
    return apply(plan.changes);
  }

  /// Restores a backup file's text: everything in it, merged (asks for nothing: [password] is
  /// needed for an encrypted file).
  Future<MuseSyncResult> importBackup(String text, {String password = ''}) async {
    final snap = await readBackup(text, password: password);
    return applyRestore(await planRestore(snap));
  }
}

final museSyncServiceProvider = Provider<MuseSyncService>(MuseSyncService.new);
