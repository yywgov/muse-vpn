import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/utils/link_parsers.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bottom_sheets_notifier.g.dart';

@riverpod
class BottomSheetsNotifier extends _$BottomSheetsNotifier {
  @override
  void build() {}

  Future<T?> _show<T>({required Widget child, required bool isScrollControlled}) async {
    final context = rootNavKey.currentContext;
    if (context == null) return null;
    // ref.read(popupCountNotifierProvider.notifier).increase();
    // 穿云 1.2.1: ModalBottomSheetRoute ignores the theme's scrim (defaults to black54, which
    // hides the dark status bar icons of the light theme) - pass the theme's own colour.
    final theme = Theme.of(context);
    final barrier =
        theme.bottomSheetTheme.modalBarrierColor ?? (theme.brightness == Brightness.light ? museLightScrim : Colors.black54);
    return await Navigator.of(context)
        .push<T>(
          ModalBottomSheetRoute(
            modalBarrierColor: barrier,
            constraints: BottomSheetConst.boxConstraints,
            isScrollControlled: isScrollControlled,
            builder: (context) => ClipRRect(
              borderRadius: BottomSheetConst.borderRadius,
              child: Material(
                child: Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: child,
                ),
              ),
            ),
          ),
        )
        .then((value) {
          // ref.read(popupCountNotifierProvider.notifier).decrease();
          return value;
        });
  }

  /// The host the deep link would actually fetch from, for the confirmation
  /// message. [url] is the deep link itself (`hiddify://import/?url=...`), so
  /// its own host is always `import` — unwrap it to the subscription link first.
  String _deepLinkHost(String url) {
    final target = LinkParser.parse(url)?.url ?? url;
    final host = Uri.tryParse(target)?.host ?? '';
    return host.isNotEmpty ? host : target;
  }

  Future<void> showAddProfile({String? url, bool triggeredByDeepLink = false}) async {
    if (url != null && triggeredByDeepLink) {
      // Preventing Zero-click SSRF
      final t = ref.watch(translationsProvider).requireValue;
      final isConfirmed = await ref
          .read(dialogNotifierProvider.notifier)
          .showConfirmation(
            title: t.dialogs.confirmation.addProfileByDeepLinkWarning.title,
            message: t.dialogs.confirmation.addProfileByDeepLinkWarning.message(host: _deepLinkHost(url)),
          );
      if (isConfirmed) {
        await _show(isScrollControlled: true, child: AddProfileModal(url: url));
      }
    } else {
      await _show(isScrollControlled: true, child: AddProfileModal(url: url));
    }
  }
}
