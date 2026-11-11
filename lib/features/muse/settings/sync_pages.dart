// 穿云 - 导出 / 导入配置. 1.9.0 #8 was the 设置 › 备份与同步 page; 1.11.0 removed that page with
// WebDAV 同步, 局域网同步, 自动备份 and 每周本地快照: what is left is 设置 › 关于 › 导出配置 / 导入配置,
// which write and read the same backup file as before (old backups, encrypted or not, still import;
// the restore preview with 仅订阅 / 仅设置、合并 / 覆盖 is unchanged, subscriptions are only added).
// 1.20.3：设置一级「备份与恢复」（MuseBackupPage）放这两项，关于页不再有；订阅弹层 ⋯ 里的快捷入口保留。
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 导出 / 导入配置

/// 1.11.0: the two links on 关于; 1.20.3: the rows of 设置 › 备份与恢复.
const museExportConfigTitle = '导出配置';
const museImportConfigTitle = '导入配置';

/// 1.20.3：设置 › 备份与恢复。
class MuseBackupPage extends ConsumerWidget {
  const MuseBackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MuseScaffold(
    key: const ValueKey('backup_page'),
    title: '备份与恢复',
    body: MuseGroupedBody(
      children: [
        MuseSection(
          children: [
            MuseTile(
              key: const ValueKey('backup_export'),
              leading: const Icon(Icons.ios_share_outlined),
              title: museExportConfigTitle,
              subtitle: '订阅和各项设置写进一个文件，可选脱敏或加密',
              subtitleMaxLines: 2,
              onTap: () => museExportConfig(context, ref),
            ),
            MuseTile(
              key: const ValueKey('backup_import'),
              leading: const Icon(Icons.file_open_outlined),
              title: museImportConfigTitle,
              subtitle: '先预览，再选恢复范围（仅订阅 / 仅设置）和合并或覆盖',
              subtitleMaxLines: 2,
              onTap: () => museImportConfig(context, ref),
            ),
          ],
        ),
      ],
    ),
  );
}

/// 1.11.0: 导出配置 — the dialog (脱敏 / password), then a save dialog for the file.
/// 1.16.0 B8: no screenshots while 导出配置 (a password, subscription links) is on screen.
Future<void> museExportConfig(BuildContext context, WidgetRef ref) => museSecureFor(context, () => _museExportConfig(context, ref));

Future<void> _museExportConfig(BuildContext context, WidgetRef ref) async {
  final choice = await showMuseExportBackupDialog(context);
  if (choice == null || !context.mounted) return;
  try {
    final text = await ref.read(museSyncServiceProvider).exportBackup(password: choice.password, redact: choice.redact);
    if (!context.mounted) return;
    final ok = await museSaveTextFile(context, museBackupFileName(redact: choice.redact), text);
    _toast(ref, ok ? '已导出' : '已取消');
  } catch (e) {
    _toast(ref, '导出失败：$e', error: true);
  }
}

/// 1.11.0: 导入配置 — pick a file, ask for its password when encrypted, preview, then restore.
Future<void> museImportConfig(BuildContext context, WidgetRef ref, {Future<String?> Function()? pickFile}) async {
  final text = await (pickFile ?? museOpenTextFile)();
  if (text == null || !context.mounted) return;
  var password = '';
  if (museIsEncrypted(text)) {
    password = await museAskText(context, '备份密码', obscure: true) ?? '';
    if (password.isEmpty) return;
  }
  await museRestoreConfigText(context, ref, text, password: password);
}

/// Reads [text] (a backup file), shows the preview (恢复范围 / 恢复策略) and applies it.
Future<void> museRestoreConfigText(BuildContext context, WidgetRef ref, String text, {String password = ''}) async {
  final service = ref.read(museSyncServiceProvider);
  final MuseSnapshot snap;
  try {
    snap = await service.readBackup(text, password: password);
  } on MuseSyncException catch (e) {
    _toast(ref, e.message, error: true);
    return;
  }
  if (!context.mounted) return;
  final plan = await showMuseRestorePreview(context, (scope, strategy) => service.planRestore(snap, scope: scope, strategy: strategy));
  if (plan == null) return;
  try {
    _toast(ref, (await service.applyRestore(plan)).summary);
  } on MuseSyncException catch (e) {
    _toast(ref, e.message, error: true);
  } catch (e) {
    _toast(ref, '失败：$e', error: true);
  }
}

/// 1.9.0 #7: what 导出备份 writes. [redact] drops subscription links (and is never encrypted, it is
/// meant to be shared); otherwise [password] empty = plain JSON.
typedef MuseExportBackupChoice = ({bool redact, String password});

String museBackupFileName({required bool redact}) => redact ? 'chuanyun-backup-redacted.json' : 'chuanyun-backup.json';

/// 1.9.0 #7: the 导出备份 dialog (脱敏 checkbox + optional password); null when cancelled.
Future<MuseExportBackupChoice?> showMuseExportBackupDialog(BuildContext context) =>
    showDialog<MuseExportBackupChoice>(context: context, builder: (_) => const MuseExportBackupDialog());

class MuseExportBackupDialog extends HookWidget {
  const MuseExportBackupDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final redact = useState(false);
    final password = useTextEditingController();
    return AlertDialog(
      title: const Text('导出备份'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            key: const ValueKey('backup_export_redact'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: redact.value,
            title: const Text('脱敏'),
            subtitle: const Text('不含订阅链接，可放心发给别人帮忙排查'),
            onChanged: (v) => redact.value = v ?? false,
          ),
          const SizedBox(height: MuseSpace.s8),
          TextField(
            key: const ValueKey('backup_export_password'),
            controller: password,
            enabled: !redact.value,
            obscureText: true,
            decoration: InputDecoration(labelText: '备份密码', hintText: redact.value ? '脱敏备份不加密' : '留空 = 不加密'),
          ),
        ],
      ),
      actions: [
        TextButton(key: const ValueKey('backup_export_cancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          key: const ValueKey('backup_export_ok'),
          onPressed: () => Navigator.of(context).pop<MuseExportBackupChoice>((redact: redact.value, password: redact.value ? '' : password.text)),
          child: const Text('导出'),
        ),
      ],
    );
  }
}

/// A yes / no question; false when dismissed.
Future<bool> museConfirm(BuildContext context, {required String title, required String message, String okText = '确定'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(key: const ValueKey('confirm_cancel'), onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          FilledButton(key: const ValueKey('confirm_ok'), onPressed: () => Navigator.of(c).pop(true), child: Text(okText)),
        ],
      ),
    ) ??
    false;

