// 穿云 1.4.0 - settings pages added in 1.4: 外观, 节点, 分流 (presets / hosts / rule tester),
// 网络 (DNS), 同步与备份 and 统计. All built from the grouped-list widgets and design tokens.
// Network-affecting options start off; nothing here changes the default connection path.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/logic/quick_rules.dart';
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/log/model/log_level.dart' as log;
import 'package:hiddify/features/muse/data/crash_recorder.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/latency_cache.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/node_prefs.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart' show MuseSnapshot, museIsEncrypted;
import 'package:hiddify/features/muse/nodes/node_list.dart' show museAskText, museNodeName;
import 'package:hiddify/features/muse/settings/android_settings.dart';
import 'package:hiddify/features/muse/settings/restore_preview.dart';
import 'package:hiddify/features/muse/settings/theme_preview_page.dart';
import 'package:hiddify/features/muse/settings/windows_settings.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_segmented.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

part 'appearance_page.dart';
part 'node_settings_page.dart';
part 'developer_page.dart';
part 'routing_pages.dart';
part 'network_page.dart';
part 'sync_pages.dart';
part 'stats_page.dart';

/// Opens a settings sub-page.
Future<void> musePushPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

void _toast(WidgetRef ref, String text, {bool error = false}) {
  try {
    final n = ref.read(inAppNotificationControllerProvider);
    error ? n.showErrorToast(text) : n.showSuccessToast(text);
  } catch (_) {}
}

/// 1.5.0 #59: this app's rule file, or else Clash / Surge rule lines converted.
Future<void> _importRulesText(WidgetRef ref, String text) async {
  List<Rule>? rules;
  var skipped = 0;
  try {
    rules = museImportRules(text);
  } catch (_) {
    final conv = museConvertClashRules(text);
    if (conv.converted > 0) {
      rules = conv.rules;
      skipped = conv.skipped;
    }
  }
  if (rules == null || rules.isEmpty) {
    _toast(ref, '没有可导入的规则', error: true);
    return;
  }
  await ref.read(rulesNotifierProvider.notifier).museImport(rules);
  _toast(ref, '已导入 ${rules.length} 条规则${skipped > 0 ? '，$skipped 行无法转换已跳过' : ''}');
}

/// A one-of-N choice as a dialog; null when dismissed.
Future<T?> musePick<T>(BuildContext context, String title, List<(T, String)> options, T current) => showDialog<T>(
  context: context,
  builder: (c) => SimpleDialog(
    title: Text(title),
    children: [
      for (final (value, label) in options)
        ListTile(
          key: ValueKey('pick_$label'),
          title: Text(label),
          trailing: value == current ? Icon(Icons.check_outlined, color: museBrandOf(context), size: MuseIconSize.small) : null,
          onTap: () => Navigator.of(c).pop(value),
        ),
    ],
  ),
);

// ======================================================================= files

/// Saves [text] as [name] (Android: the system save dialog; Windows: a save-as dialog).
Future<bool> museSaveTextFile(BuildContext context, String name, String text) async {
  try {
    final bytes = utf8.encode(text);
    final path = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
    if (path == null) return false;
    if (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) await File(path).writeAsBytes(bytes);
    return true;
  } catch (_) {
    return false;
  }
}

/// Picks a text file; null when cancelled or unreadable.
Future<String?> museOpenTextFile() async {
  try {
    final r = await FilePicker.platform.pickFiles(withData: true);
    final f = r?.files.firstOrNull;
    if (f == null) return null;
    final data = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    return data == null ? null : utf8.decode(data, allowMalformed: true);
  } catch (_) {
    return null;
  }
}
