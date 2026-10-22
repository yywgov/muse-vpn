// 穿云 1.4.0 - the core of 同步 (坚果云 WebDAV) and 备份 (pure logic, unit-tested):
//   * a snapshot is a flat map of entries `key → {v: value, t: modified ms}` (v null = deleted),
//     so two devices merge field by field and the later change of each field wins;
//   * the synced / backed-up file is encrypted with AES-256-GCM, the key derived from the user's
//     password with PBKDF2-HMAC-SHA256 (random salt and nonce per file);
//   * a backup can be redacted (subscription links and passwords taken out).
// Nothing here talks to the network or reads preferences.
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// One synced value and when it was last changed (ms since epoch).
class MuseSyncEntry {
  const MuseSyncEntry(this.value, this.at);

  /// null = deleted on the device that wrote it
  final Object? value;
  final int at;

  Map<String, dynamic> toJson() => {'v': value, 't': at};

  static MuseSyncEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'];
    if (t is! num) return null;
    return MuseSyncEntry(j['v'], t.toInt());
  }

  @override
  bool operator ==(Object other) => other is MuseSyncEntry && other.at == at && jsonEncode(other.value) == jsonEncode(value);

  @override
  int get hashCode => Object.hash(at, jsonEncode(value));
}

/// A device's state as synced entries.
class MuseSnapshot {
  const MuseSnapshot(this.entries, {this.device = '', this.version = 1});

  final Map<String, MuseSyncEntry> entries;
  final String device;
  final int version;

  static const empty = MuseSnapshot({});

  Map<String, dynamic> toJson() => {
    'chuanyun_sync': version,
    'device': device,
    'entries': {for (final e in entries.entries) e.key: e.value.toJson()},
  };

  static MuseSnapshot fromJson(Map<String, dynamic> j) {
    final raw = j['entries'];
    final out = <String, MuseSyncEntry>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final e = MuseSyncEntry.fromJson(v);
        if (e != null) out['$k'] = e;
      });
    }
    return MuseSnapshot(out, device: '${j['device'] ?? ''}', version: (j['chuanyun_sync'] as num?)?.toInt() ?? 1);
  }

  /// Values only (deleted entries left out).
  Map<String, Object?> get values => {for (final e in entries.entries) if (e.value.value != null) e.key: e.value.value};
}

/// Field-level merge: for every key the entry changed last wins (a tie keeps [local]).
MuseSnapshot museMergeSnapshots(MuseSnapshot local, MuseSnapshot remote) {
  final out = Map<String, MuseSyncEntry>.of(local.entries);
  remote.entries.forEach((k, r) {
    final l = out[k];
    if (l == null || r.at > l.at) out[k] = r;
  });
  return MuseSnapshot(out, device: local.device);
}

/// The local entries, stamped: a value that differs from what was last synced ([lastSynced])
/// gets [now] as its time (it changed here since), an unchanged one keeps its old time. Keys that
/// were synced before and are gone now become deletions.
MuseSnapshot museStampLocal({
  required Map<String, Object?> current,
  required MuseSnapshot lastSynced,
  required int now,
  String device = '',
}) {
  final out = <String, MuseSyncEntry>{};
  current.forEach((k, v) {
    final prev = lastSynced.entries[k];
    if (prev != null && jsonEncode(prev.value) == jsonEncode(v)) {
      out[k] = prev;
    } else {
      out[k] = MuseSyncEntry(v, now);
    }
  });
  lastSynced.entries.forEach((k, prev) {
    if (!current.containsKey(k)) out[k] = prev.value == null ? prev : MuseSyncEntry(null, now);
  });
  return MuseSnapshot(out, device: device);
}

/// What applying [merged] changes on this device: keys whose value differs from [current].
Map<String, Object?> museSyncChanges(Map<String, Object?> current, MuseSnapshot merged) {
  final out = <String, Object?>{};
  merged.entries.forEach((k, e) {
    final cur = current[k];
    if (jsonEncode(cur) != jsonEncode(e.value)) out[k] = e.value;
  });
  return out;
}

// ---------------------------------------------------------------- redaction

/// Keys that hold secrets (subscription links, passwords): dropped from a redacted backup.
bool museIsSecretKey(String key) =>
    key.startsWith('sub:') || key.contains('password') || key.contains('secret') || key.startsWith('webdav');

/// A backup without secrets.
MuseSnapshot museRedactSnapshot(MuseSnapshot s) =>
    MuseSnapshot({for (final e in s.entries.entries) if (!museIsSecretKey(e.key)) e.key: e.value}, device: s.device);

// ---------------------------------------------------------------- encryption

const _magic = 'chuanyun-enc';

class MuseCryptoException implements Exception {
  const MuseCryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}

Uint8List _randomBytes(int n, Random rnd) => Uint8List.fromList([for (var i = 0; i < n; i++) rnd.nextInt(256)]);

Uint8List museDeriveKey(String password, Uint8List salt, {int iterations = 60000}) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(password)));
}

/// [plain] encrypted for [password]: a JSON envelope (text, safe to store or share).
String museEncrypt(String plain, String password, {int iterations = 60000, Random? random}) {
  if (password.isEmpty) throw const MuseCryptoException('需要密码');
  final rnd = random ?? Random.secure();
  final salt = _randomBytes(16, rnd);
  final nonce = _randomBytes(12, rnd);
  final key = museDeriveKey(password, salt, iterations: iterations);
  final cipher = GCMBlockCipher(AESEngine())..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  final ct = cipher.process(Uint8List.fromList(utf8.encode(plain)));
  return jsonEncode({
    'format': _magic,
    'v': 1,
    'kdf': 'pbkdf2-sha256',
    'iter': iterations,
    'salt': base64.encode(salt),
    'nonce': base64.encode(nonce),
    'data': base64.encode(ct),
  });
}

bool museIsEncrypted(String text) {
  try {
    final j = jsonDecode(text);
    return j is Map && j['format'] == _magic;
  } catch (_) {
    return false;
  }
}

/// Decrypts a [museEncrypt] envelope; throws [MuseCryptoException] for a wrong password or a
/// damaged file.
String museDecrypt(String envelope, String password) {
  Map<String, dynamic> j;
  try {
    j = jsonDecode(envelope) as Map<String, dynamic>;
  } catch (_) {
    throw const MuseCryptoException('文件已损坏');
  }
  if (j['format'] != _magic) throw const MuseCryptoException('不是加密文件');
  try {
    final salt = base64.decode('${j['salt']}');
    final nonce = base64.decode('${j['nonce']}');
    final data = base64.decode('${j['data']}');
    final key = museDeriveKey(password, salt, iterations: (j['iter'] as num?)?.toInt() ?? 60000);
    final cipher = GCMBlockCipher(AESEngine())..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return utf8.decode(cipher.process(data));
  } on InvalidCipherTextException {
    throw const MuseCryptoException('密码不对');
  } catch (e) {
    if (e is MuseCryptoException) rethrow;
    throw const MuseCryptoException('密码不对或文件已损坏');
  }
}
