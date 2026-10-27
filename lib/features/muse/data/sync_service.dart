// 穿云 1.4.0 - 同步 and 本地备份 / 恢复. 1.4.1: 局域网同步 first (data/lan_sync_service.dart);
// WebDAV (any server) is the secondary option.
// What is synced: the settings in [museSyncedPrefs] and the subscription links (`sub:<url>` →
// name). Subscriptions are only ever added by a sync, never deleted. The file on the server is
// always encrypted (AES-GCM, logic/sync_core.dart) with the sync password (or the app password).
// 1.4.1: the Dio client is closed after each sync, PBKDF2 runs off the UI thread, a device that
// never synced takes the existing values, a subscription deleted elsewhere is not resurrected.
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Settings that go into 同步 / 备份, with the provider to refresh after a change.
final museSyncedPrefs = <String, ProviderOrFamily>{
  'muse_accent': MusePrefs.accent,
  'muse_dock_style': MusePrefs.dockStyle,
  'muse_blocked_hosts': MusePrefs.blockedHosts,
  'muse_tab_animation': MusePrefs.tabAnimation,
  'muse_text_size': MusePrefs.textSize,
  'muse_text_scale_on': MusePrefs.textScaleOn,
  'muse_text_scale_pct': MusePrefs.textScalePct,
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
};

const museSyncFileName = 'chuanyun-sync.json';
const museSyncFolder = 'chuanyun';

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
      return all.fold((_) => const [], (l) => l.whereType<RemoteProfileEntity>().toList());
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

  /// The last merged state this device knows (shared by LAN and WebDAV sync).
  MuseSnapshot lastSynced() {
    try {
      final raw = ref.read(MusePrefs.syncLast);
      if (raw.isNotEmpty) return MuseSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    return MuseSnapshot.empty;
  }

  /// This device's values stamped against [lastSynced] ([remoteKeys]: what the other side has,
  /// for a first sync).
  Future<MuseSnapshot> stampedLocal({Set<String> remoteKeys = const {}, int? now}) async => museStampLocal(
    current: await localValues(),
    lastSynced: lastSynced(),
    now: now ?? DateTime.now().millisecondsSinceEpoch,
    device: deviceId,
    remoteKeys: remoteKeys,
  );

  /// Applies [merged] here and remembers it as the last synced state.
  Future<MuseSyncResult> applyMerged(MuseSnapshot merged) async {
    final result = await apply(museSyncChanges(await localValues(), merged));
    await ref.read(MusePrefs.syncLast.notifier).update(jsonEncode(merged.toJson()));
    await ref.read(MusePrefs.syncLastAt.notifier).update(DateTime.now().millisecondsSinceEpoch);
    return result;
  }

  /// A readable name for this device (shown to the other side when pairing).
  static String get deviceName {
    String host;
    try {
      host = Platform.localHostname;
    } catch (_) {
      host = '';
    }
    final kind = Platform.isAndroid ? 'Android' : (Platform.isWindows ? 'Windows' : Platform.operatingSystem);
    return host.isEmpty || host == 'localhost' ? kind : '$kind · $host';
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

  String get _password {
    final own = ref.read(MusePrefs.syncPassphrase);
    return own.isNotEmpty ? own : ref.read(MusePrefs.webdavPassword);
  }

  Dio _dio() {
    final user = ref.read(MusePrefs.webdavUser).trim();
    final pass = ref.read(MusePrefs.webdavPassword);
    if (user.isEmpty || pass.isEmpty) throw const MuseSyncException('请先填写账号和应用密码');
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {'Authorization': 'Basic ${base64.encode(utf8.encode('$user:$pass'))}'},
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );
  }

  String _base() {
    var url = ref.read(MusePrefs.webdavUrl).trim();
    if (url.isEmpty) throw const MuseSyncException('请先填写服务器地址');
    if (!url.endsWith('/')) url = '$url/';
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) throw const MuseSyncException('服务器地址需以 https:// 开头');
    return url;
  }

  static String _httpError(int? code) => switch (code) {
    401 => '账号或应用密码不对',
    403 => '没有权限（部分服务需使用「应用密码」）',
    404 => '服务器上没有这个目录',
    507 => '服务器空间已满',
    _ => '服务器返回 $code',
  };

  /// Download → merge (last change per field wins) → apply here → upload.
  Future<MuseSyncResult> syncNow() async {
    final dio = _dio();
    try {
      final base = _base();
      final password = _password;
      final folder = '$base$museSyncFolder/';
      final fileUrl = '$folder$museSyncFileName';

      // remote
      MuseSnapshot remote = const MuseSnapshot({});
      final Response<String> got;
      try {
        got = await dio.get<String>(fileUrl);
      } on DioException catch (e) {
        throw MuseSyncException('连接服务器失败：${e.message ?? e.type.name}');
      }
      if (got.statusCode == 200 && (got.data ?? '').isNotEmpty) {
        try {
          remote = MuseSnapshot.fromJson(jsonDecode(await museDecryptAsync(got.data!, password)) as Map<String, dynamic>);
        } on MuseCryptoException catch (e) {
          throw MuseSyncException('解密同步文件失败：$e（两台设备的同步密码需相同）');
        } catch (_) {
          throw const MuseSyncException('同步文件已损坏');
        }
      } else if (got.statusCode != 404) {
        throw MuseSyncException(_httpError(got.statusCode));
      }

      // local, stamped against what was synced last time
      final local = await stampedLocal(remoteKeys: remote.entries.keys.toSet());
      final merged = museMergeSnapshots(local, remote);
      final body = await museEncryptAsync(jsonEncode(merged.toJson()), password);

      // upload first, then apply: a failed upload leaves this device unchanged
      try {
        await dio.request<String>(folder, options: Options(method: 'MKCOL'));
        final put = await dio.put<String>(fileUrl, data: body, options: Options(contentType: 'application/json'));
        if (put.statusCode == null || put.statusCode! >= 300) throw MuseSyncException(_httpError(put.statusCode));
      } on DioException catch (e) {
        throw MuseSyncException('上传失败：${e.message ?? e.type.name}');
      }
      return applyMerged(merged);
    } finally {
      dio.close(force: true);
    }
  }

  /// A backup file's text. [password] empty = plain JSON; [redact] drops subscription links.
  Future<String> exportBackup({String password = '', bool redact = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var snap = MuseSnapshot({for (final e in (await localValues()).entries) e.key: MuseSyncEntry(e.value, now)}, device: _deviceId);
    if (redact) snap = museRedactSnapshot(snap);
    final plain = const JsonEncoder.withIndent('  ').convert(snap.toJson());
    return password.isEmpty ? plain : museEncryptAsync(plain, password);
  }

  /// Restores a backup file's text (asks for nothing: [password] is needed for an encrypted file).
  Future<MuseSyncResult> importBackup(String text, {String password = ''}) async {
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
    // 1.5.0 #197: what is there now is kept first, so a wrong file can be undone
    await autoBackup('restore');
    final current = await localValues();
    return apply(museSyncChanges(current, snap));
  }

  /// 1.5.0 #197 / #206: the current settings and subscriptions saved as an automatic backup
  /// (newest 5 kept). Null when it could not be written; never throws.
  Future<File?> autoBackup(String reason) async {
    try {
      final dir = await museAutoBackupDir();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}${museAutoBackupName(reason, DateTime.now())}');
      await file.writeAsString(await exportBackup());
      final names = [for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last];
      for (final old in museAutoBackupsToPrune(names)) {
        try {
          File('${dir.path}${Platform.pathSeparator}$old').deleteSync();
        } catch (_) {}
      }
      return file;
    } catch (_) {
      return null;
    }
  }
}

Future<Directory> museAutoBackupDir() async => Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}backups');

/// The automatic backups, newest first.
Future<List<File>> museListAutoBackups() async {
  try {
    final dir = await museAutoBackupDir();
    if (!dir.existsSync()) return const [];
    final files = [for (final f in dir.listSync().whereType<File>()) if (museParseAutoBackupName(f.uri.pathSegments.last) != null) f];
    files.sort((a, b) => museParseAutoBackupName(b.uri.pathSegments.last)!.at.compareTo(museParseAutoBackupName(a.uri.pathSegments.last)!.at));
    return files;
  } catch (_) {
    return const [];
  }
}

final museSyncServiceProvider = Provider<MuseSyncService>(MuseSyncService.new);
