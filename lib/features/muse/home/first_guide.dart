// 穿云 1.16.0 B10 - 新用户一步引导：全新安装第一次打开时弹一次「添加订阅 → 连接」，可跳过；
// 只出现一次（muse_onboarding_done），老用户升级（以前打开过穿云或已有订阅）直接记为已看过、不弹。
// 添加订阅后再问一次「现在连接？」。不读剪贴板、不联网、无计时器。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart' show MuseAddAction;
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What to do with the guide on this start.
enum MuseFirstGuide { show, markDone, none }

/// [done]: the guide was shown (or skipped) before. [hasProfile]: subscriptions exist.
/// [changelogShown]: the version whose 更新说明 an earlier start recorded (empty on a new install).
MuseFirstGuide museFirstGuideFor({required bool done, required bool? hasProfile, required String changelogShown}) {
  if (done || hasProfile == null) return MuseFirstGuide.none;
  // an existing user (opened an older version, or already has subscriptions) never sees it
  if (hasProfile || changelogShown.isNotEmpty) return MuseFirstGuide.markDone;
  return MuseFirstGuide.show;
}

/// Set while a subscription added from the guide should be followed by 「现在连接？」 (memory only).
final museGuideAwaitConnectProvider = StateProvider<bool>((_) => false);

/// The guide's ways to add (key, icon, label, action); 扫码 only where there is a camera scanner.
List<(String, IconData, String, MuseAddAction)> museGuideActions({required bool qr}) => [
  ('guide_paste', Icons.content_paste_outlined, '粘贴订阅链接', MuseAddAction.paste),
  if (qr) ('guide_qr', Icons.qr_code_scanner_outlined, '扫码添加', MuseAddAction.qr),
];

/// Runs once on the first start: decides, records, and shows the guide when it is a new install.
/// [changelogShown] is read before this start records its version.
Future<void> museMaybeShowFirstGuide(
  BuildContext context,
  WidgetRef ref, {
  required bool? hasProfile,
  required String changelogShown,
  required bool qr,
}) async {
  final decision = museFirstGuideFor(
    done: ref.read(MusePrefs.onboardingDone),
    hasProfile: hasProfile,
    changelogShown: changelogShown,
  );
  if (decision == MuseFirstGuide.none) return;
  await ref.read(MusePrefs.onboardingDone.notifier).update(true); // only ever once
  if (decision != MuseFirstGuide.show || !context.mounted) return;
  final picked = await showModalBottomSheet<MuseAddAction>(
    context: context,
    showDragHandle: true,
    builder: (c) => MuseFirstGuideSheet(qr: qr),
  );
  if (picked == null) return; // 跳过
  ref.read(museGuideAwaitConnectProvider.notifier).state = true;
  await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(action: picked);
}

/// After a subscription was added from the guide: 「现在连接？」 once.
Future<void> museGuideAskConnect(BuildContext context, WidgetRef ref) async {
  ref.read(museGuideAwaitConnectProvider.notifier).state = false;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('guide_connect_dialog'),
      title: const Text('订阅已添加'),
      content: const Text('现在连接就能开始使用。以后在首页点按大按钮即可连接或断开。'),
      actions: [
        TextButton(key: const ValueKey('guide_connect_later'), onPressed: () => Navigator.of(c).pop(false), child: const Text('稍后')),
        FilledButton(key: const ValueKey('guide_connect_now'), onPressed: () => Navigator.of(c).pop(true), child: const Text('连接')),
      ],
    ),
  );
  if (go == true) await ref.read(connectionNotifierProvider.notifier).toggleConnection();
}

class MuseFirstGuideSheet extends StatelessWidget {
  const MuseFirstGuideSheet({super.key, required this.qr});

  final bool qr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // scrolls on a small screen with large text (320 px at 2×)
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('first_guide_sheet'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('欢迎使用穿云', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              '一步开始：添加你的订阅，然后点「连接」',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            for (final (key, icon, label, action) in museGuideActions(qr: qr)) ...[
              SizedBox(
                height: 48,
                child: action == MuseAddAction.paste
                    ? FilledButton.icon(
                        key: ValueKey(key),
                        onPressed: () => Navigator.of(context).pop(action),
                        icon: Icon(icon),
                        label: Text(label),
                      )
                    : OutlinedButton.icon(
                        key: ValueKey(key),
                        onPressed: () => Navigator.of(context).pop(action),
                        icon: Icon(icon),
                        label: Text(label),
                      ),
              ),
              const SizedBox(height: 8),
            ],
            TextButton(
              key: const ValueKey('guide_skip'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('跳过'),
            ),
          ],
        ),
      ),
    );
  }
}
