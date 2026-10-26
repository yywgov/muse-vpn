// 穿云 1.1 - 剪贴板里有订阅链接时提示导入（1.3.0：「添加」上的小圆点 + 添加面板第一行）。
// Only checked when the app opens or comes back to the front, never offered twice for the same
// link, and never for a link that is already one of the user's subscriptions.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/utils/link_parsers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _importSchemes = {'chuanyun', 'hiddify', 'clash', 'clashmeta', 'sing-box', 'v2ray', 'v2rayn', 'v2rayng'};

final _subscriptionHint = RegExp(
  r'(sub|token|clash|subscribe|config|v2ray|singbox|sing-box|flag=|/link/|/s/|/api/)',
  caseSensitive: false,
);

/// The subscription link in [text], or null when it does not look like one (pure, for tests).
/// Import links (chuanyun://, hiddify://, clash://install-config?url=…) always count; a plain
/// http(s) link only when its path or query looks like a subscription, so ordinary web pages
/// copied from a browser are not offered.
String? museSubscriptionLinkFromClipboard(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > 2048 || trimmed.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;
  final scheme = uri.scheme.toLowerCase();
  if (_importSchemes.contains(scheme)) {
    final link = LinkParser.deep(trimmed);
    if (link == null) return null;
    final inner = Uri.tryParse(link.url);
    if (inner == null || !(inner.isScheme('http') || inner.isScheme('https')) || inner.host.isEmpty) return null;
    return trimmed;
  }
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  final rest = '${uri.path}?${uri.query}';
  if (!_subscriptionHint.hasMatch(rest)) return null;
  return trimmed;
}

/// The subscription url a clipboard link imports (the inner url for import schemes).
String museSubscriptionUrlOf(String link) => LinkParser.parse(link)?.url ?? link;

/// 1.3.0: checks the clipboard when the app opens or comes back to the front; a new subscription
/// link puts a dot on 添加 and becomes the first row of the 添加 sheet (no 首页 banner any more).
void useMuseClipboardWatcher(WidgetRef ref) {
  final context = useContext();
  Future<void> check() async {
    // a short wait: on Android the clipboard can only be read once the window has focus
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!context.mounted) return;
    try {
      // hasStrings does not read the content, so no "pasted from clipboard" toast for nothing
      if (!await Clipboard.hasStrings()) return;
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final link = museSubscriptionLinkFromClipboard(data?.text);
      if (link == null || !context.mounted) return;
      if (ref.read(Preferences.clipboardLastOffered) == link) return;
      final url = museSubscriptionUrlOf(link);
      final profiles = ref.read(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
      if (profiles.any((p) => p is RemoteProfileEntity && p.url == url)) return;
      ref.read(museClipboardOfferProvider.notifier).state = link;
    } catch (_) {
      // clipboard unavailable: nothing to offer
    }
  }

  useEffect(() {
    check();
    return null;
  }, const []);
  useOnAppLifecycleStateChange((_, state) {
    if (state == AppLifecycleState.resumed) check();
  });
}

/// First row of the 添加 sheet while a clipboard link is on offer: 「导入剪贴板里的订阅 · host」.
class MuseClipboardOfferTile extends ConsumerWidget {
  const MuseClipboardOfferTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(museClipboardOfferProvider);
    if (link == null) return const SizedBox.shrink();
    final mt = MuseTheme.of(context);
    final host = Uri.tryParse(museSubscriptionUrlOf(link))?.host ?? '';
    Future<void> done() async {
      ref.read(museClipboardOfferProvider.notifier).state = null;
      await ref.read(Preferences.clipboardLastOffered.notifier).update(link);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s8),
      child: Material(
        color: mt.selected,
        shape: MuseShape.radius(MuseRadius.cardAll),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: const ValueKey('clipboard_offer'),
          leading: Icon(Icons.content_paste_outlined, color: MusePalette.brand, size: MuseIconSize.regular),
          title: Text('导入剪贴板里的订阅', style: MuseType.body(context).copyWith(fontWeight: FontWeight.w600)),
          subtitle: host.isEmpty ? null : Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseType.caption(context)),
          trailing: IconButton(
            tooltip: '忽略',
            icon: Icon(Icons.close_outlined, size: MuseIconSize.small, color: mt.text3),
            onPressed: done,
          ),
          onTap: () async {
            await done();
            await ref.read(addProfileNotifierProvider.notifier).addClipboard(link);
          },
        ),
      ),
    );
  }
}
