// 穿云 1.1 - 剪贴板里有订阅链接时提示导入（1.3.0：添加面板第一行）。
// 1.12.0: 回到前台只问系统「剪贴板里有没有文字」（不读内容，Android 不弹「已粘贴」提示）；
// 打开「添加」面板时才读取并识别。同一链接不重复提示，已是订阅的链接不提示。
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
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

/// 1.12.0: whether the clipboard holds text, as seen when the app last came to the front.
/// Only [Clipboard.hasStrings] is asked (it does not read the content, so Android shows no
/// 「已从剪贴板粘贴」 notice); the text itself is read when the user opens 添加.
final museClipboardHasTextProvider = StateProvider<bool>((ref) => false);

/// 1.12.0 (was 1.3.0): on open / back in front only asks whether there is text at all. The
/// clipboard is read only when the 添加 sheet opens ([museReadClipboardOffer]).
void useMuseClipboardWatcher(WidgetRef ref) {
  final context = useContext();
  Future<void> check() async {
    // a short wait: on Android the clipboard can only be asked once the window has focus
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!context.mounted) return;
    try {
      final has = await Clipboard.hasStrings();
      if (!context.mounted) return;
      ref.read(museClipboardHasTextProvider.notifier).state = has;
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

/// The link to offer for clipboard [text] (pure, for tests): null when it is not a subscription
/// link, was offered before, or is already one of the subscriptions.
String? museClipboardOfferFor(String? text, {required String? lastOffered, required Iterable<String> subscriptionUrls}) {
  final link = museSubscriptionLinkFromClipboard(text);
  if (link == null || link == lastOffered) return null;
  final url = museSubscriptionUrlOf(link);
  if (subscriptionUrls.contains(url)) return null;
  return link;
}

/// 1.12.0: the 添加 sheet opened — the user asked to add something, so the clipboard is read
/// now (only when it holds text) and a subscription link becomes the sheet's first row.
Future<void> museReadClipboardOffer(WidgetRef ref, {Future<String?> Function()? read}) async {
  try {
    final String? text;
    if (read != null) {
      text = await read();
    } else {
      if (!await Clipboard.hasStrings()) return;
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    }
    final profiles = ref.read(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
    final link = museClipboardOfferFor(
      text,
      lastOffered: ref.read(Preferences.clipboardLastOffered),
      subscriptionUrls: [for (final p in profiles) if (p is RemoteProfileEntity) p.url],
    );
    ref.read(museClipboardOfferProvider.notifier).state = link;
  } catch (_) {
    // clipboard unavailable: nothing to offer
  }
}

/// First row of the 添加 sheet while a clipboard link is on offer: 「导入剪贴板里的订阅 · host」.
class MuseClipboardOfferTile extends HookConsumerWidget {
  const MuseClipboardOfferTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1.12.0: read the clipboard once, when the sheet opens (the user's own action)
    useEffect(() {
      Future.microtask(() => museReadClipboardOffer(ref));
      return null;
    }, const []);
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
          leading: Icon(Icons.content_paste_outlined, color: museBrandOf(context), size: MuseIconSize.regular),
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
            // 1.9.0 #191: the link carries a secret; empty the clipboard when asked to
            if (ref.read(MusePrefs.clearClipboardAfterImport)) {
              try {
                await Clipboard.setData(const ClipboardData(text: ''));
              } catch (_) {}
            }
          },
        ),
      ),
    );
  }
}
