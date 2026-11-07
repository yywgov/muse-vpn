// 穿云 1.14.0 R14 - 订阅自定义请求头: some panels want a token or a device id with the
// subscription download. Kept per subscription (by profile id, setting `muse_sub_headers`), sent
// only when that subscription is downloaded, never synced or backed up (the ids are this device's
// own, and the values are secrets), and masked wherever they could be shown or logged.
// Pure and never throws.
// Part of 穿云 (GPLv3).

import 'dart:convert';

/// Header names the app sets itself (or that would break the download).
const _reserved = {'host', 'content-length', 'connection', 'transfer-encoding', 'accept-encoding'};

final _token = RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+$");

/// Why [name] can't be a header name (null = fine).
String? museHeaderNameError(String name) {
  final n = name.trim();
  if (n.isEmpty) return '名称不能为空';
  if (!_token.hasMatch(n)) return '名称「$n」含有不允许的字符';
  if (_reserved.contains(n.toLowerCase())) return '「$n」由穿云自动设置，不能自定义';
  return null;
}

/// Why [value] can't be a header value (null = fine).
String? museHeaderValueError(String value) {
  if (value.contains('\n') || value.contains('\r')) return '值不能换行';
  if (value.codeUnits.any((c) => c < 0x20 && c != 0x09 || c == 0x7f)) return '值含有控制字符';
  return null;
}

/// The editor's text: one 「名称: 值」 per line; empty lines and 「#」 comments are skipped.
/// Returns the headers (in order, last one wins) or the first problem with its line number.
({Map<String, String> headers, String? error}) museParseHeaderLines(String text) {
  final out = <String, String>{};
  final lines = const LineSplitter().convert(text);
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    final at = l.indexOf(':') >= 0 ? l.indexOf(':') : l.indexOf('：');
    if (at <= 0) return (headers: const {}, error: '第 ${i + 1} 行应为「名称: 值」');
    final name = l.substring(0, at).trim();
    final value = l.substring(at + 1).trim();
    final e = museHeaderNameError(name) ?? museHeaderValueError(value);
    if (e != null) return (headers: const {}, error: '第 ${i + 1} 行：$e');
    out.removeWhere((k, _) => k.toLowerCase() == name.toLowerCase());
    out[name] = value;
  }
  return (headers: out, error: null);
}

String museHeaderLines(Map<String, String> headers) => [for (final e in headers.entries) '${e.key}: ${e.value}'].join('\n');

/// All subscriptions' headers by profile id. A broken value reads as none.
Map<String, Map<String, String>> museParseSubHeaders(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return {};
    final out = <String, Map<String, String>>{};
    for (final e in j.entries) {
      if (e.value is! Map) continue;
      final h = <String, String>{
        for (final h in (e.value as Map).entries)
          if (museHeaderNameError('${h.key}') == null && museHeaderValueError('${h.value}') == null) '${h.key}'.trim(): '${h.value}',
      };
      if (h.isNotEmpty) out['${e.key}'] = h;
    }
    return out;
  } catch (_) {
    return {};
  }
}

/// [all] with [id]'s headers replaced ([headers] empty = removed).
String museEncodeSubHeaders(Map<String, Map<String, String>> all, String id, Map<String, String> headers) {
  final next = {...all};
  if (headers.isEmpty) {
    next.remove(id);
  } else {
    next[id] = headers;
  }
  return jsonEncode(next);
}

/// The headers sent with [id]'s download.
Map<String, String> museSubHeadersFor(String raw, String? id) => id == null ? const {} : museParseSubHeaders(raw)[id] ?? const {};

/// 「abcdef123」 → 「ab****」: enough to recognise, never the secret.
String museMaskHeaderValue(String v) {
  final t = v.trim();
  if (t.isEmpty) return '';
  return '${t.length > 6 ? t.substring(0, 2) : ''}****';
}

/// What the subscription menu shows (names with masked values).
String museMaskedHeaderSummary(Map<String, String> headers) =>
    [for (final e in headers.entries) '${e.key}: ${museMaskHeaderValue(e.value)}'].join('\n');
