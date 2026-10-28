// 穿云 1.7.0 M3 - 设置 › 内核: which core runs the connection (标准内核 by default) and its version.
// Switching needs the connection off; Windows then offers to restart the app (the core library is
// loaded once per run), Android uses the new core from the next connect.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/windows_admin.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/resources.dart' show museCoreRelease;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Version shown for [kind].
String museCoreKindVersion(MuseCoreKind kind) => switch (kind) {
  MuseCoreKind.standard => museCoreRelease,
  MuseCoreKind.compat => museCompatEngineVersion,
};

class MuseCoreKindSection extends ConsumerWidget {
  const MuseCoreKindSection({super.key, this.desktop});

  /// null = the real platform (tests pass it)
  final bool? desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = desktop ?? PlatformUtils.isDesktop;
    final saved = MuseCoreKind.fromKey(ref.watch(MusePrefs.coreKind));
    final running = isDesktop ? MuseCoreSelection.startup : saved;
    final pending = museCoreRestartPending(saved: saved, running: running, desktop: isDesktop);
    return MuseSection(
      header: '内核',
      children: [
        MuseTile(
          key: const ValueKey('core_kind'),
          leading: const Icon(Icons.memory_outlined),
          title: '内核',
          subtitle: pending ? '已选${saved.title}，重启应用后生效' : null,
          trailing: Text(saved.title),
          chevron: true,
          onTap: () => _pick(context, ref, saved, isDesktop),
        ),
        MuseTile(
          key: const ValueKey('core_kind_version'),
          leading: const Icon(Icons.info_outlined),
          title: '内核版本',
          // a subtitle, not trailing: the version is long and must wrap at 320 px with large text
          subtitle: museCoreKindVersion(running),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, MuseCoreKind saved, bool isDesktop) async {
    final picked = await showDialog<MuseCoreKind>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('内核'),
        children: [
          for (final k in MuseCoreKind.values)
            ListTile(
              key: ValueKey('core_kind_${k.key}'),
              title: Text(k.title),
              subtitle: Text('${k.blurb} · ${museCoreKindVersion(k)}'),
              trailing: k == saved
                  ? Icon(Icons.check_outlined, color: museBrandOf(context), size: MuseIconSize.small)
                  : null,
              onTap: () => Navigator.of(c).pop(k),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    final status = ref.read(connectionNotifierProvider).valueOrNull;
    final step = museCoreSwitchStep(
      current: saved,
      picked: picked,
      disconnected: status == null || status is Disconnected,
      desktop: isDesktop,
    );
    final toasts = ref.read(inAppNotificationControllerProvider);
    switch (step) {
      case MuseCoreSwitchStep.none:
        return;
      case MuseCoreSwitchStep.disconnectFirst:
        toasts.showInfoToast('请先断开连接，再切换内核');
        return;
      case MuseCoreSwitchStep.nextConnect:
        await ref.read(MusePrefs.coreKind.notifier).update(picked.key);
        toasts.showInfoToast('下次连接时使用${picked.title}');
      case MuseCoreSwitchStep.restartApp:
        await ref.read(MusePrefs.coreKind.notifier).update(picked.key);
        // back to the core this run loaded: nothing to restart
        if (picked == MuseCoreSelection.startup) return;
        final now = await ref
            .read(dialogNotifierProvider.notifier)
            .showConfirmation(title: '重启应用后生效', message: '切换到${picked.title}需要重新打开穿云。', positiveBtnTxt: '立即重启');
        if (!now) return;
        if (await WindowsAdmin.relaunch()) await ref.read(windowNotifierProvider.notifier).exit();
    }
  }
}
