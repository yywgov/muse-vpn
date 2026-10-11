import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Characters used for the generated LAN sharing password.
///
/// Visually ambiguous characters (`0`/`O`, `1`/`l`/`I`) are left out so the
/// password stays readable when it is typed from a QR code by hand.
const _passwordAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

const _passwordLength = 16;

String _generatePassword() {
  final random = Random.secure();
  return List.generate(_passwordLength, (_) => _passwordAlphabet[random.nextInt(_passwordAlphabet.length)]).join();
}

class LanSharingPreferenceWidget extends HookConsumerWidget {
  const LanSharingPreferenceWidget({super.key, this.showLeading = true, this.title, this.subtitle});

  /// Whether to show the leading icon of the [ListTile].
  ///
  /// Hidden when the widget is embedded in the quick settings modal.
  final bool showLeading;

  /// Muse VPN: optional plain-language title / one-line explanation (quick settings sheet).
  /// When [subtitle] is set, the device's LAN address and port are shown while sharing is on.
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final enabled = ref.watch(ConfigOptions.allowConnectionFromLan);

    /// Creates the password the first time sharing is turned on and keeps it
    /// for every later session, so the user never has to pick or manage one.
    Future<void> ensurePassword() async {
      if (ref.read(ConfigOptions.lanSharingPassword).isEmpty) {
        await ref.read(ConfigOptions.lanSharingPassword.notifier).update(_generatePassword());
      }
    }

    // Covers sharing that was already enabled before the password became
    // mandatory.
    useEffect(() {
      if (enabled) ensurePassword();
      return null;
    }, [enabled]);

    Future<String?> getSharingLink() async {
      final ipResult = await ref.read(hiddifyCoreServiceProvider).getLANIP().run();
      final ip = ipResult.fold((_) => null, (r) => r.ip);
      if (ip == null) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.settings.inbound.lanIPError);
        return null;
      }
      final port = ref.read(ConfigOptions.mixedPort);
      final password = ref.read(ConfigOptions.lanSharingPassword);
      return 'socks://hiddify:$password@$ip:$port';
    }

    // Muse VPN: show "ip:port" while sharing is on, so other devices know where to connect.
    final lanAddress = useState<String?>(null);
    final mixedPort = ref.watch(ConfigOptions.mixedPort);
    useEffect(() {
      if (!enabled || subtitle == null) {
        lanAddress.value = null;
        return null;
      }
      var active = true;
      ref.read(hiddifyCoreServiceProvider).getLANIP().run().then((result) {
        if (!active) return;
        lanAddress.value = result.fold((_) => null, (r) => r.ip.isEmpty ? null : '${r.ip}:$mixedPort');
      });
      return () => active = false;
    }, [enabled, mixedPort, subtitle]);

    // The action buttons live below the tile instead of in its trailing slot to
    // avoid overflowing the tile on narrow screens (e.g. iOS).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          secondary: showLeading ? const Icon(Icons.share_rounded) : null,
          title: Text(title ?? t.pages.settings.inbound.lanSharing),
          subtitle: subtitle == null
              ? null
              : Text(
                  enabled && lanAddress.value != null
                      ? '$subtitle\n本机地址：${lanAddress.value}（SOCKS，需要密码，可复制链接或扫码）'
                      : subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                ),
          value: enabled,
          onChanged: (value) async {
            if (value) await ensurePassword();
            await ref.read(ConfigOptions.allowConnectionFromLan.notifier).update(value);
          },
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      final link = await getSharingLink();
                      if (link != null) {
                        await Clipboard.setData(ClipboardData(text: link));
                        ref
                            .read(inAppNotificationControllerProvider)
                            .showSuccessToast(t.common.msg.export.clipboard.success);
                      }
                    },
                    icon: Icon(Icons.link_rounded, color: theme.colorScheme.primary),
                    label: Text(
                      t.pages.settings.inbound.copyLink,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final link = await getSharingLink();
                      if (link != null) {
                        final qrLink = '#profile-title: LAN only\n$link#LAN only';
                        await ref.read(dialogNotifierProvider.notifier).showQrCode(qrLink, message: link);
                      }
                    },
                    icon: Icon(Icons.qr_code_rounded, color: theme.colorScheme.primary),
                    label: Text(
                      t.pages.settings.inbound.qrCode,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
