import 'dart:convert';

import 'package:hiddify/utils/validators.dart';

typedef ProfileLink = ({String url, String name});

/// Subscription links: plain http(s) URLs and app deep links (chuanyun://, panel schemes).
/// Tested in test/utils/link_parsers_test.dart.
abstract class LinkParser {
  static String generateSubShareLink(String url, [String? name]) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final modifiedUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path,
      query: uri.query,
      fragment: name ?? uri.fragment,
    );
    // return 'hiddify://import/$modifiedUri';
    return '$modifiedUri';
  }

  // protocols schemas
  static const protocols = ['chuanyun', 'hiddify', 'v2ray', 'v2rayn', 'v2rayng', 'clash', 'clashmeta', 'sing-box'];

  static ProfileLink? parse(String link) {
    return simple(link) ?? deep(link);
  }

  static ProfileLink? simple(String link) {
    if (!isUrl(link)) return null;
    final uri = Uri.parse(link.trim());
    return (url: uri.toString(), name: uri.queryParameters['name'] ?? '');
  }

  static ProfileLink? deep(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final queryParams = uri.queryParameters;
    switch (uri.scheme) {
      case 'chuanyun' || 'hiddify':
        if (queryParams.containsKey('url')) {
          // Doc form: chuanyun://install-config (or hiddify://)?url=<uri>#<name> — the name lives
          // in the fragment. Prefer an explicit `name=` param, else the fragment.
          final name = (queryParams['name']?.isNotEmpty ?? false) ? queryParams['name']! : _fragment(uri);
          return (url: queryParams['url']!, name: name);
        } else {
          return (url: uri.path.substring(1) + (uri.hasQuery ? "?${uri.query}" : ""), name: _fragment(uri));
        }
      case 'v2ray' || 'v2rayn' || 'v2rayng' || 'clash' || 'clashmeta' || 'sing-box':
        return queryParams.containsKey('url') ? (url: queryParams['url']!, name: queryParams['name'] ?? '') : null;
      default:
        return null;
    }
  }

  /// The fragment as text (`#%E5%AE%B6` → 家); a malformed escape keeps the raw fragment.
  static String _fragment(Uri uri) {
    try {
      return Uri.decodeComponent(uri.fragment);
    } catch (_) {
      return uri.fragment;
    }
  }
}

String safeDecodeBase64(String str) {
  try {
    return utf8.decode(base64Decode(str));
  } catch (e) {
    return str;
  }
}
