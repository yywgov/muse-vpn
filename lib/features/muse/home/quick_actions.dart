// 穿云 1.12.0 - what the launcher shortcuts do once 穿云 is open: 切换规则/全局 (chuanyun://mode),
// 扫码添加 (chuanyun://scan) and 测速 (chuanyun://speedtest). Each one goes through the same code as
// the matching button in the app; nothing runs in the background.
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/muse/desktop/desktop_actions.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart' show MuseAddAction;
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Test seams.
typedef MuseQuickRunner = Future<void> Function(Ref ref, MuseQuickAction action);
MuseQuickRunner? museQuickActionOverride;

Future<void> museRunQuickAction(Ref ref, MuseQuickAction action) async {
  final o = museQuickActionOverride;
  if (o != null) return o(ref, action);
  try {
    switch (action) {
      case MuseQuickAction.mode:
        await museRunDesktopAction(ref, MuseDesktopAction.toggleMode);
      case MuseQuickAction.scan:
        await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(action: MuseAddAction.qr);
      case MuseQuickAction.speedtest:
        // the node list may still be loading right after start-up
        for (var i = 0; i < 20 && ref.read(proxiesOverviewNotifierProvider).valueOrNull == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final group = ref.read(proxiesOverviewNotifierProvider).valueOrNull;
        if (group != null) await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group.tag);
    }
  } catch (_) {}
}
