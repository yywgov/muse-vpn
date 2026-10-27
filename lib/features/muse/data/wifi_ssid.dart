// 穿云 1.6.0 C8 - the Wi‑Fi this Windows computer is on, read from `netsh wlan show interfaces`
// (works on Chinese and English Windows: the field names SSID / BSSID are never translated).
// Used by 按需运行. Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:io';

/// What one read gave: [ok] false when netsh failed (no wireless service, location access off on
/// Windows 11 24H2+…) — the caller then keeps its last state instead of treating it as "left the
/// Wi‑Fi". [ssid] null = not connected to any Wi‑Fi.
class MuseSsidRead {
  const MuseSsidRead.ok(this.ssid) : ok = true, hint = null;
  const MuseSsidRead.failed(this.hint) : ok = false, ssid = null;

  final bool ok;
  final String? ssid;

  /// why it failed, for the 按需运行 sheet
  final String? hint;
}

const museWifiLocationHint = '读不到 Wi‑Fi 名称：请在 Windows 设置 › 隐私和安全性 › 位置 中打开「定位服务」和「允许桌面应用访问你的位置」';

/// Parses netsh output. The first interface whose block has an `SSID : name` line (connected) wins.
MuseSsidRead museParseNetshInterfaces(String output) {
  final lower = output.toLowerCase();
  if (lower.contains('location permission') ||
      lower.contains('位置权限') ||
      lower.contains('ms-settings:privacy-location')) {
    return const MuseSsidRead.failed(museWifiLocationHint);
  }
  final ssidLine = RegExp(r'^\s*SSID\s*:\s?(.*)$', multiLine: true);
  final hasInterface = RegExp(r'^\s*(Name|名称)\s*:', multiLine: true).hasMatch(output);
  for (final m in ssidLine.allMatches(output)) {
    final name = m.group(1)!.trimRight();
    if (name.isNotEmpty) return MuseSsidRead.ok(name);
  }
  if (hasInterface || lower.contains('there is no wireless interface') || output.contains('没有无线接口')) {
    return const MuseSsidRead.ok(null);
  }
  return const MuseSsidRead.failed('读不到 Wi‑Fi 状态');
}

/// Runs netsh (Windows only; 5 s at most).
Future<MuseSsidRead> museReadWindowsSsid() async {
  if (!Platform.isWindows) return const MuseSsidRead.ok(null);
  try {
    // stdout / stderr in the system code page (default)
    final r = await Process.run('netsh', ['wlan', 'show', 'interfaces']).timeout(const Duration(seconds: 5));
    final out = '${r.stdout}\n${r.stderr}';
    return museParseNetshInterfaces(out);
  } catch (e) {
    return MuseSsidRead.failed('读不到 Wi‑Fi 状态（$e）');
  }
}

/// `{"A": "disconnect", "B": "disconnect"}` ⇄ the 按需运行 list (other rule kinds are kept as is).
List<String> museOnDemandSsids(String rawRules) {
  if (rawRules.trim().isEmpty) return const [];
  try {
    final m = jsonDecode(rawRules) as Map<String, dynamic>;
    return [
      for (final e in m.entries)
        if (e.value == 'disconnect') e.key,
    ];
  } catch (_) {
    return const [];
  }
}

String museOnDemandWithSsids(String rawRules, List<String> ssids) {
  var m = <String, dynamic>{};
  try {
    if (rawRules.trim().isNotEmpty) m = Map<String, dynamic>.from(jsonDecode(rawRules) as Map);
  } catch (_) {}
  m.removeWhere((_, v) => v == 'disconnect');
  for (final s in ssids) {
    final t = s.trim();
    if (t.isNotEmpty) m[t] = 'disconnect';
  }
  return m.isEmpty ? '' : jsonEncode(m);
}
