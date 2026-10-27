// 穿云 1.6.0 C10 - 设置 › 资源: the rule-sets the app ships (name, kind, size, when the copy on this
// device was written, 修复 = copy the missing / damaged ones again) and the remote rule-sets the
// user added (managed in 分流 › 远程规则集, one tap away). 数据库 and 脚本 are placeholders for
// the dual-core version. Reading the files happens off the first frame, so opening 设置 is not
// slowed down.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/bundled_rule_sets.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/node_order.dart' show museBytes;
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart' show museShortDateTime;
import 'package:hiddify/features/muse/settings/more_settings.dart' show MuseRemoteRuleSetsPage, musePushPage;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseResourcesPage extends HookConsumerWidget {
  const MuseResourcesPage({super.key, this.baseDir});

  /// for tests; otherwise the app's base directory
  final String? baseDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = useState<List<MuseRuleSetFile>?>(null);
    final busy = useState(false);
    final remote = museParseRemoteRuleSets(ref.watch(MusePrefs.remoteRuleSets));

    Future<String?> dir() async {
      if (baseDir != null) return baseDir;
      try {
        return (await ref.read(appDirectoriesProvider.future)).baseDir.absolute.path;
      } catch (_) {
        return null;
      }
    }

    Future<void> load() async {
      final d = await dir();
      if (!context.mounted) return;
      files.value = d == null ? [for (final n in museBundledRuleSets) MuseRuleSetFile(n)] : museReadRuleSetFiles(d, museBundledRuleSets);
    }

    useEffect(() {
      Future.microtask(load);
      return null;
    }, const []);

    Future<void> repair() async {
      if (busy.value) return;
      busy.value = true;
      try {
        final d = await dir();
        final copied = d == null ? 0 : await museInstallBundledRuleSets(d);
        await load();
        try {
          ref.read(inAppNotificationControllerProvider).showSuccessToast(copied == 0 ? '内置规则集完好' : '已补齐 $copied 个规则集');
        } catch (_) {}
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    final list = files.value;
    final present = list?.where((f) => f.present).toList() ?? const <MuseRuleSetFile>[];
    final mt = MuseTheme.of(context);

    return MuseScaffold(
      title: '资源',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '内置规则集',
            footer: '随穿云提供，连接时直接使用，不用等下载；连接后每 $museRuleSetUpdateDays 天在后台自动更新为最新版',
            children: [
              MuseTile(
                key: const ValueKey('res_builtin_summary'),
                leading: const Icon(Icons.inventory_2_outlined),
                title: '规则集',
                subtitle: list == null ? '读取中…' : '本机 ${present.length} / ${list.length} 个 · 共 ${museBytes(museRuleSetTotal(present))}',
              ),
              if (list != null)
                for (final f in list)
                  MuseTile(
                    key: ValueKey('res_builtin_${f.name}'),
                    title: museRuleSetTitle(f.name),
                    subtitle: f.present
                        ? '${museRuleSetKind(f.name)} · ${museBytes(f.size!)} · ${museShortDateTime(f.modified!)} 写入'
                        : '${museRuleSetKind(f.name)} · 本机缺少，连接时下载',
                    trailing: f.present ? null : Icon(Icons.error_outline_outlined, size: MuseIconSize.small, color: mt.text3),
                  ),
              MuseTile(
                key: const ValueKey('res_repair'),
                leading: busy.value
                    ? const SizedBox(
                        width: MuseIconSize.small,
                        height: MuseIconSize.small,
                        child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                      )
                    : const Icon(Icons.build_circle_outlined),
                title: '检查并修复',
                subtitle: '重新复制本机缺少或损坏的内置规则集',
                onTap: busy.value ? null : repair,
              ),
            ],
          ),
          MuseSection(
            header: '远程规则集',
            footer: '你添加的规则集链接：首次连接时下载，之后每 $museRuleSetUpdateDays 天在后台更新',
            children: [
              for (var i = 0; i < remote.length; i++)
                MuseTile(
                  key: ValueKey('res_remote_$i'),
                  leading: const Icon(Icons.cloud_outlined),
                  title: Uri.tryParse(remote[i].url)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? remote[i].url,
                  subtitle: '${museOutboundTitle(remote[i].outbound)} · ${museRemoteRuleSetSource(remote[i].url)}',
                ),
              MuseTile(
                key: const ValueKey('res_remote_manage'),
                leading: const Icon(Icons.edit_note_outlined),
                title: remote.isEmpty ? '添加远程规则集' : '管理远程规则集',
                subtitle: '设置 › 分流 › 远程规则集',
                chevron: true,
                onTap: () => musePushPage(context, const MuseRemoteRuleSetsPage()),
              ),
            ],
          ),
          // placeholders, grey: these come with the dual-core version
          MuseSection(
            header: '数据库与脚本 · 双内核版本提供',
            children: [
              MuseTile(
                key: const ValueKey('res_geo_placeholder'),
                leading: Icon(Icons.public_outlined, color: mt.text3),
                title: 'Geo 数据库',
                subtitle: '查看与编辑 GeoIP / GeoSite 文件',
              ),
              MuseTile(
                key: const ValueKey('res_script_placeholder'),
                leading: Icon(Icons.code_outlined, color: mt.text3),
                title: '脚本',
                subtitle: '订阅覆写脚本',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
