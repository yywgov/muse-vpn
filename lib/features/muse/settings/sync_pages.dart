// 穿云 - 设置 › 同步与备份（局域网、WebDAV、备份）. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 同步与备份

class MuseSyncPage extends HookConsumerWidget {
  const MuseSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastAt = ref.watch(MusePrefs.syncLastAt);
    final busy = useState(false);
    final webdavUser = ref.watch(MusePrefs.webdavUser);

    Future<void> run(Future<String> Function() job) async {
      if (busy.value) return;
      busy.value = true;
      try {
        final msg = await job();
        if (msg.isNotEmpty) _toast(ref, msg);
      } on MuseSyncException catch (e) {
        _toast(ref, e.message, error: true);
      } on MuseLanException catch (e) {
        _toast(ref, e.message, error: true);
      } catch (e) {
        _toast(ref, '失败：$e', error: true);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    /// The joining side: confirm, then sync with the device in [raw].
    Future<void> join(String? raw) async {
      if (raw == null || raw.trim().isEmpty || !context.mounted) return;
      final p = museParseLanPairing(raw);
      if (p == null) {
        _toast(ref, '不是穿云的配对码', error: true);
        return;
      }
      if (p.expired(DateTime.now())) {
        _toast(ref, '配对码已过期，请在对方设备上重新打开', error: true);
        return;
      }
      final ok = await museConfirm(
        context,
        title: '局域网同步',
        message: '与「${p.device.isEmpty ? p.host : p.device}」合并设置和订阅？\n两边各自的修改都会保留（同一项以较新的为准），订阅只增不删。',
        okText: '同步',
      );
      if (!ok) return;
      await run(() async => (await museLanSyncWith(ref.read(museSyncServiceProvider), p)).summary);
    }

    /// 1.6.0 C10: read the file, preview (恢复范围 / 恢复策略), then restore.
    Future<void> restore(String text, {String password = '', String? source}) async {
      final service = ref.read(museSyncServiceProvider);
      final MuseSnapshot snap;
      try {
        snap = await service.readBackup(text, password: password);
      } on MuseSyncException catch (e) {
        _toast(ref, e.message, error: true);
        return;
      }
      if (!context.mounted) return;
      final plan = await showMuseRestorePreview(
        context,
        (scope, strategy) => service.planRestore(snap, scope: scope, strategy: strategy),
        source: source,
      );
      if (plan == null) return;
      await run(() async => (await service.applyRestore(plan)).summary);
    }

        return MuseScaffold(
      title: '同步与备份',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '局域网同步',
            footer: '两台设备连同一 Wi‑Fi / 局域网，无需账号；配对码 3 分钟内有效、只能用一次，数据全程加密',
            children: [
              MuseTile(
                key: const ValueKey('lan_host'),
                leading: const Icon(Icons.qr_code_2_outlined),
                title: '显示配对码',
                subtitle: '在另一台设备上扫码或输入',
                chevron: true,
                onTap: busy.value ? null : () => showMuseLanHostSheet(context),
              ),
              if (PlatformUtils.isAndroid || PlatformUtils.isIOS)
                MuseTile(
                  key: const ValueKey('lan_scan'),
                  leading: busy.value
                      ? const SizedBox(
                          width: MuseIconSize.small,
                          height: MuseIconSize.small,
                          child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                        )
                      : const Icon(Icons.qr_code_scanner_outlined),
                  title: '扫码配对',
                  chevron: true,
                  onTap: busy.value ? null : () async => join(await ref.read(dialogNotifierProvider.notifier).showQrScanner()),
                ),
              MuseTile(
                key: const ValueKey('lan_type'),
                leading: const Icon(Icons.keyboard_outlined),
                title: '输入配对码',
                chevron: true,
                onTap: busy.value ? null : () async => join(await museAskText(context, '配对码', hint: '192.168.1.5:43125 ABCD-EFGH-…')),
              ),
              if (lastAt != 0)
                MuseTile(
                  key: const ValueKey('sync_last'),
                  leading: const Icon(Icons.history_outlined),
                  title: '上次同步',
                  trailing: Text(museUpdatedAgo(DateTime.fromMillisecondsSinceEpoch(lastAt), now: DateTime.now()).replaceAll('更新', '')),
                ),
            ],
          ),
          MuseSection(
            header: '本地备份',
            children: [
              // 1.9.0 #7: one 导出备份; 脱敏 is a checkbox in its dialog
              MuseTile(
                key: const ValueKey('backup_export'),
                leading: const Icon(Icons.save_alt_outlined),
                title: '导出备份',
                subtitle: '可选加密，或脱敏（不含订阅链接）后分享',
                onTap: () async {
                  final choice = await showMuseExportBackupDialog(context);
                  if (choice == null || !context.mounted) return;
                  await run(() async {
                    final text = await ref.read(museSyncServiceProvider).exportBackup(password: choice.password, redact: choice.redact);
                    if (!context.mounted) return '';
                    final ok = await museSaveTextFile(context, museBackupFileName(redact: choice.redact), text);
                    return ok ? '已导出' : '已取消';
                  });
                },
              ),
              MuseTile(
                key: const ValueKey('backup_import'),
                leading: const Icon(Icons.restore_outlined),
                title: '从备份恢复',
                subtitle: '先预览，可选 仅订阅 / 仅设置、合并 / 覆盖',
                onTap: () async {
                  final text = await museOpenTextFile();
                  if (text == null || !context.mounted) return;
                  var pw = '';
                  if (museIsEncrypted(text)) {
                    pw = await museAskText(context, '备份密码', obscure: true) ?? '';
                    if (pw.isEmpty) return;
                  }
                  await restore(text, password: pw);
                },
              ),
              // 1.9.0 #200
              MuseSwitchTile(
                key: const ValueKey('weekly_snapshot'),
                leading: const Icon(Icons.event_repeat_outlined),
                title: '每周本地快照',
                info: '每周自动保存一份设置和订阅到本机（含订阅链接，不上传），保留最近 5 份，可在「自动备份」里恢复',
                value: ref.watch(MusePrefs.weeklySnapshot),
                onChanged: (v) => ref.read(MusePrefs.weeklySnapshot.notifier).update(v),
              ),
              // 1.5.0 #197 / #206: taken by itself before a restore or an app update
              MuseTile(
                key: const ValueKey('backup_auto'),
                leading: const Icon(Icons.history_toggle_off_outlined),
                title: '自动备份',
                info: '恢复备份或更新 App 前自动保存当前配置，保留最近 5 份',
                chevron: true,
                onTap: () async {
                  final files = await museListAutoBackups();
                  if (!context.mounted) return;
                  if (files.isEmpty) {
                    _toast(ref, '还没有自动备份');
                    return;
                  }
                  final picked = await musePick<File>(context, '恢复到', [
                    for (final f in files)
                      if (museParseAutoBackupName(f.uri.pathSegments.last) case final meta?)
                        (f, '${museAutoBackupReasonTitle(meta.reason)} · ${museShortDateTime(meta.at)}'),
                  ], files.first);
                  if (picked == null) return;
                  final meta = museParseAutoBackupName(picked.uri.pathSegments.last);
                  await restore(
                    await picked.readAsString(),
                    source: meta == null ? null : '自动备份 · ${museAutoBackupReasonTitle(meta.reason)} · ${museShortDateTime(meta.at)}',
                  );
                },
              ),
            ],
          ),
          MuseSection(
            header: '更多',
            children: [
              MuseTile(
                key: const ValueKey('sync_webdav'),
                leading: const Icon(Icons.cloud_sync_outlined),
                title: 'WebDAV 同步',
                trailing: Text(webdavUser.isEmpty ? '未设置' : '已设置'),
                chevron: true,
                onTap: () => musePushPage(context, const MuseWebdavPage()),
              ),
            ],
          ),
        ],
      ),
    );
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

/// 局域网同步, the side that shows the code: listens only while this sheet is open.
Future<void> showMuseLanHostSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: MuseColors.card(context),
  builder: (_) => const MuseLanHostSheet(),
);

class MuseLanHostSheet extends ConsumerStatefulWidget {
  const MuseLanHostSheet({super.key, this.address, this.ttl = museLanPairingTtl});

  /// fixed address (tests); null = the LAN address
  final String? address;
  final Duration ttl;

  @override
  ConsumerState<MuseLanHostSheet> createState() => _MuseLanHostSheetState();
}

class _MuseLanHostSheetState extends ConsumerState<MuseLanHostSheet> {
  late final MuseLanHost _host;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _host = MuseLanHost(
      ref.read(museSyncServiceProvider),
      confirm: (device) async {
        if (!mounted) return false;
        return museConfirm(
          context,
          title: '局域网同步',
          message: '「$device」请求同步设置和订阅，同意吗？',
          okText: '同意',
        );
      },
      onChange: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_host.start(address: widget.address, ttl: widget.ttl));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _host.state == MuseLanHostState.waiting) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_host.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final p = _host.pairing;
    final left = p == null ? Duration.zero : Duration(milliseconds: p.expiresAt - DateTime.now().millisecondsSinceEpoch);
    final secs = left.isNegative ? 0 : left.inSeconds;
    final Widget body = switch (_host.state) {
      // 1.5.0: the QR code's place, pulsing, instead of a spinner
      MuseLanHostState.starting => const Padding(
        padding: EdgeInsets.all(MuseSpace.s32),
        child: Center(child: MuseSkeleton(child: MuseSkeletonBox(width: MuseSize.qrCode, height: MuseSize.qrCode, radius: MuseRadius.cardAll))),
      ),
      MuseLanHostState.waiting when p != null => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MuseQrView(p.toUri(), key: const ValueKey('lan_qr')),
          const SizedBox(height: MuseSpace.s16),
          SelectableText(
            p.manualCode,
            key: const ValueKey('lan_code'),
            textAlign: TextAlign.center,
            style: MuseType.body(context).copyWith(fontFeatures: MuseType.tabular, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: MuseSpace.s8),
          Text(
            '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')} 后失效 · 另一台设备：设置 › 同步与备份 › 扫码或输入配对码',
            textAlign: TextAlign.center,
            style: MuseType.caption(context),
          ),
          if (PlatformUtils.isWindows) ...[
            const SizedBox(height: MuseSpace.s4),
            Text('Windows 首次使用会询问防火墙，请允许「专用网络」', textAlign: TextAlign.center, style: MuseType.caption(context)),
          ],
        ],
      ),
      MuseLanHostState.syncing => Padding(
        padding: const EdgeInsets.all(MuseSpace.s24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: MuseIconSize.small, height: MuseIconSize.small, child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke)),
            const SizedBox(width: MuseSpace.s12),
            Text('正在同步…', style: MuseType.body(context)),
          ],
        ),
      ),
      _ => Padding(
        padding: const EdgeInsets.all(MuseSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _host.state == MuseLanHostState.done ? Icons.check_circle_outlined : Icons.error_outlined,
              color: _host.state == MuseLanHostState.done ? MusePalette.green : MusePalette.orange,
              size: MuseSize.emptyIcon,
            ),
            const SizedBox(height: MuseSpace.s12),
            Text(_host.message, key: const ValueKey('lan_host_message'), textAlign: TextAlign.center, style: MuseType.body(context)),
          ],
        ),
      ),
    };
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          key: const ValueKey('lan_host_sheet'),
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('局域网同步', style: MuseType.title(context)),
              const SizedBox(height: MuseSpace.s16),
              Center(child: body),
              const SizedBox(height: MuseSpace.s16),
              Text(
                '同步：订阅、节点重命名 / 备注 / 隐藏、收藏、分流和设置',
                textAlign: TextAlign.center,
                style: MuseType.caption(context).copyWith(color: mt.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1.4.1: WebDAV (any server) — the secondary sync, under 同步与备份 › 更多.
class MuseWebdavPage extends HookConsumerWidget {
  const MuseWebdavPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(MusePrefs.webdavUrl);
    final user = ref.watch(MusePrefs.webdavUser);
    final pass = ref.watch(MusePrefs.webdavPassword);
    final passphrase = ref.watch(MusePrefs.syncPassphrase);
    final lastAt = ref.watch(MusePrefs.syncLastAt);
    final busy = useState(false);

    Future<void> syncNow() async {
      if (busy.value) return;
      busy.value = true;
      try {
        _toast(ref, (await ref.read(museSyncServiceProvider).syncNow()).summary);
      } on MuseSyncException catch (e) {
        _toast(ref, e.message, error: true);
      } catch (e) {
        _toast(ref, '失败：$e', error: true);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return MuseScaffold(
      title: 'WebDAV 同步',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            footer: '支持任意 WebDAV 服务；文件加密后上传，两台设备的同步密码需相同',
            children: [
              MuseTile(
                key: const ValueKey('sync_url'),
                leading: const Icon(Icons.dns_outlined),
                title: '服务器',
                trailing: Text(url.isEmpty ? '未填写' : (Uri.tryParse(url)?.host ?? url), overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '服务器地址', initial: url, hint: 'https://dav.example.com/dav/');
                  if (v != null) await ref.read(MusePrefs.webdavUrl.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_user'),
                leading: const Icon(Icons.person_outlined),
                title: '账号',
                trailing: Text(user.isEmpty ? '未填写' : user, overflow: TextOverflow.ellipsis),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '账号', initial: user);
                  if (v != null) await ref.read(MusePrefs.webdavUser.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_password'),
                leading: const Icon(Icons.key_outlined),
                title: '密码',
                trailing: Text(pass.isEmpty ? '未填写' : '已填写'),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '密码（部分服务需使用「应用密码」）', obscure: true);
                  if (v != null && v.isNotEmpty) await ref.read(MusePrefs.webdavPassword.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_passphrase'),
                leading: const Icon(Icons.lock_outlined),
                title: '同步密码',
                trailing: Text(passphrase.isEmpty ? '同登录密码' : '已设置'),
                chevron: true,
                onTap: () async {
                  final v = await museAskText(context, '同步密码（留空 = 用登录密码）', obscure: true);
                  if (v != null) await ref.read(MusePrefs.syncPassphrase.notifier).update(v);
                },
              ),
              MuseTile(
                key: const ValueKey('sync_now'),
                leading: busy.value
                    ? const SizedBox(
                        width: MuseIconSize.small,
                        height: MuseIconSize.small,
                        child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                      )
                    : const Icon(Icons.sync_outlined),
                title: '立即同步',
                subtitle: lastAt == 0 ? null : '上次：${museUpdatedAgo(DateTime.fromMillisecondsSinceEpoch(lastAt), now: DateTime.now()).replaceAll('更新', '')}',
                onTap: busy.value ? null : syncNow,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
