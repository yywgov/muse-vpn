// 穿云 1.1 - 剪贴板里有订阅链接时，首页顶部弹出「导入」。
// Only checked when the app opens or comes back to the front, never offered twice for the same
// link, and never for a link that is already one of the user's subscriptions.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
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

/// Top card on 首页: 「检测到订阅链接」 [忽略] [导入].
class MuseClipboardImportBanner extends HookConsumerWidget {
  const MuseClipboardImportBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = useState<String?>(null);
    // keeps the add notifier (and its success/error toasts) alive while an import runs
    ref.listen(addProfileNotifierProvider, (_, _) {});

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
        final known = profiles.any((p) => p is RemoteProfileEntity && p.url == url);
        if (known) return;
        offer.value = link;
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

    final link = offer.value;
    if (link == null) return const SizedBox.shrink();

    Future<void> close() async {
      offer.value = null;
      await ref.read(Preferences.clipboardLastOffered.notifier).update(link);
    }

    final theme = Theme.of(context);
    final host = Uri.tryParse(museSubscriptionUrlOf(link))?.host ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: BoxDecoration(color: MuseColors.card(context), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            const Icon(Icons.content_paste_rounded, color: MuseColors.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('检测到订阅链接', style: theme.textTheme.titleSmall),
                  if (host.isNotEmpty)
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: MuseColors.secondaryText(context)),
                    ),
                ],
              ),
            ),
            TextButton(onPressed: close, child: const Text('忽略')),
            FilledButton(
              onPressed: () async {
                await close();
                await ref.read(addProfileNotifierProvider.notifier).addClipboard(link);
              },
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );
  }
}
