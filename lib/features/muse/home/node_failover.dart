// 穿云 - 节点失效自动切换: when the hand-picked node of the main group stops answering the url test,
// switch the group to its 自动最快 (urltest) member. Reuses the existing auto group, nothing new to test.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final museNodeFailoverProvider = Provider<void>((ref) {
  if (!ref.watch(Preferences.nodeFailover) || !ref.watch(serviceRunningProvider)) return;
  var switching = false;
  ref.listen<AsyncValue<OutboundGroup?>>(proxiesOverviewNotifierProvider, (previous, next) async {
    final group = next.valueOrNull;
    if (group == null || switching || !group.selectable) return;
    final selected = group.items.where((e) => e.tag == group.selected).firstOrNull;
    // only a concrete node the user picked; a group (自动最快 etc.) handles failures itself
    if (selected == null || selected.isGroup) return;
    final delay = selected.urlTestDelay;
    final failed = delay > 0 && !ConnectionConst.isValidDelay(delay);
    if (!failed) return;
    // react to a fresh test result only: picking a node that timed out earlier is the user's choice
    final before = previous?.valueOrNull?.items.where((e) => e.tag == selected.tag).firstOrNull;
    if (before == null || before.urlTestTime == selected.urlTestTime) return;
    final auto = group.items
        .where((e) => e.isGroup && (e.type.toLowerCase() == 'urltest' || e.type.toLowerCase() == 'url-test'))
        .firstOrNull;
    if (auto == null) return;
    switching = true;
    try {
      await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, auto.tag);
      ref
          .read(inAppNotificationControllerProvider)
          .showInfoToast('「${selected.tagDisplay.isNotEmpty ? selected.tagDisplay : selected.tag}」超时，已切换到自动最快');
    } catch (_) {
      // the notifier logs it; try again on the next result
    } finally {
      switching = false;
    }
  }, fireImmediately: false);
});
