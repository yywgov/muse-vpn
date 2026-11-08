// 穿云 1.15.0 R16 - 连接列表显示发起的应用（图标 + 名称）。
// 只在内核已报告进程信息时显示（标准内核 processPath：Android 是包名「com.x.y (10123)」，Windows
// 是程序路径；兼容内核 process）。名称表在连接页打开时读一次，图标按需读、最多缓存
// [museAppIconCacheMax] 个且缩小解码；离开页面即释放，不新增任何后台读取。
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 一条连接的发起者。
@immutable
class MuseConnApp {
  const MuseConnApp({required this.id, required this.name, this.package});

  /// 包名或程序路径（用于聚合）
  final String id;

  /// 显示名：应用名，取不到时是包名 / 程序文件名
  final String name;

  /// Android 包名（有图标可取）
  final String? package;
}

final _pkg = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+$');

/// 内核报告的进程字段 → 包名（Android）；不是包名时为 null。
String? museProcessPackage(String process) {
  var p = process.trim();
  final paren = p.indexOf(' (');
  if (paren > 0) p = p.substring(0, paren).trim();
  if (p.isEmpty || p.contains('/') || p.contains(r'\')) return null;
  if (p.toLowerCase().endsWith('.exe')) return null;
  return _pkg.hasMatch(p) ? p : null;
}

/// 内核报告的进程字段 → 发起者；只有 UID 数字或为空时为 null（不显示）。
MuseConnApp? museConnApp(String process, Map<String, String> labels) {
  final raw = process.trim();
  if (raw.isEmpty) return null;
  final pkg = museProcessPackage(raw);
  if (pkg != null) return MuseConnApp(id: pkg, name: labels[pkg] ?? pkg, package: pkg);
  var p = raw;
  final paren = p.indexOf(' (');
  if (paren > 0) p = p.substring(0, paren).trim();
  if (p.isEmpty || RegExp(r'^\d+$').hasMatch(p)) return null;
  final base = p.split(RegExp(r'[\\/]')).last;
  return MuseConnApp(id: p, name: base.isEmpty ? p : base);
}

/// get_installed_packages 的回答（JSON 数组，每项 package-name / name）→ 包名 → 应用名。
Map<String, String> museParseAppLabels(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    final list = jsonDecode(json);
    if (list is! List) return const {};
    return {
      for (final e in list)
        if (e is Map && e['package-name'] is String && '${e['name'] ?? ''}'.trim().isNotEmpty && e['name'] != 'null')
          e['package-name'] as String: '${e['name']}'.trim(),
    };
  } catch (_) {
    return const {};
  }
}

const _platform = MethodChannel('com.hiddify.app/platform');

/// 是否读应用名与图标（只有 Android 的连接带包名）；测试可覆盖。
final museConnAppsEnabledProvider = Provider<bool>((ref) => Platform.isAndroid);

/// 包名 → 应用名。连接页打开时读一次，离开页面后释放。
final museAppLabelsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  if (!ref.watch(museConnAppsEnabledProvider)) return const {};
  try {
    return museParseAppLabels(await _platform.invokeMethod<String>('get_installed_packages'));
  } catch (_) {
    return const {};
  }
});

/// 图标缓存上限（PNG 字节，最近用过的留下）。
const museAppIconCacheMax = 48;

/// 小型最近使用缓存。
class MuseLru<K, V> {
  MuseLru(this.max);

  final int max;
  final _m = <K, V>{};

  int get length => _m.length;

  V? get(K k) {
    final v = _m.remove(k);
    if (v != null) _m[k] = v;
    return v;
  }

  void put(K k, V v) {
    _m.remove(k);
    _m[k] = v;
    while (_m.length > max) {
      _m.remove(_m.keys.first);
    }
  }
}

final _iconCache = MuseLru<String, Uint8List>(museAppIconCacheMax);

/// 一个应用的图标（PNG）；取不到为 null。只在连接行显示时读。
final museAppIconProvider = FutureProvider.autoDispose.family<Uint8List?, String>((ref, pkg) async {
  if (!ref.watch(museConnAppsEnabledProvider)) return null;
  final hit = _iconCache.get(pkg);
  if (hit != null) return hit;
  try {
    final b64 = await _platform.invokeMethod<String>('get_package_icon', {'packageName': pkg});
    if (b64 == null || b64.isEmpty) return null;
    final bytes = base64Decode(b64);
    _iconCache.put(pkg, bytes);
    return bytes;
  } catch (_) {
    return null;
  }
});
