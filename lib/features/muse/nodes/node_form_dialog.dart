// 穿云 1.14.0 R21 - 手动添加节点 (节点 ⋯) and 编辑节点 (node detail). Both are saved in the active
// subscription's 覆写, so an update of the subscription keeps them; the saved subscription itself
// is never changed. While connected the 覆写 listener applies the change (no reconnect by hand).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/config/sub_override_page.dart' show museSaveOverride;
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/node_form.dart';
import 'package:hiddify/features/muse/logic/sub_override.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'package:hiddify/features/muse/logic/sub_override.dart' show museChainCandidates;

MuseSubOverride _overrideOf(WidgetRef ref, String id) => museParseOverrides(ref.read(MusePrefs.subOverrides))[id] ?? const MuseSubOverride();

/// Whether [tag] of [profileId] has a local patch.
bool museOverrideHasEdit(WidgetRef ref, String profileId, String tag) => _overrideOf(ref, profileId).edits.containsKey(tag);

/// 手动添加节点 to [profileId]; true when one was added.
Future<bool> showMuseAddNodeDialog(BuildContext context, WidgetRef ref, String profileId) async {
  final link = await showDialog<String>(context: context, builder: (_) => const MuseNodeFormDialog());
  if (link == null) return false;
  final o = _overrideOf(ref, profileId);
  await museSaveOverride(ref, profileId, o.copyWith(enabled: true, nodes: [...o.nodes, link]));
  return true;
}

/// 节点 ⋯ › 手动添加节点, with the toast.
Future<void> museAddNodeFromMenu(BuildContext context, WidgetRef ref, {required String? profileId, required bool running}) async {
  if (profileId == null || !await showMuseAddNodeDialog(context, ref, profileId)) return;
  try {
    ref.read(inAppNotificationControllerProvider).showSuccessToast(running ? '已添加节点，正在应用' : '已添加节点，连接后出现在列表里');
  } catch (_) {}
}

/// 编辑节点 [tag] of [profileId]; [original] is the node as the subscription has it.
/// Returns '' when the patch was removed, the saved message otherwise, null when cancelled.
Future<String?> showMuseEditNodeDialog(BuildContext context, WidgetRef ref, String profileId, String tag, Map<String, dynamic> original) async {
  final o = _overrideOf(ref, profileId);
  final current = o.edits[tag] ?? const MuseNodeEdit();
  final result = await showDialog<MuseNodeEdit>(
    context: context,
    builder: (_) => MuseNodeEditDialog(original: original, current: current),
  );
  if (result == null) return null;
  await museSaveOverride(ref, profileId, o.withEdit(tag, result).copyWith(enabled: true));
  return result.isEmpty ? '' : '已保存本地修改，订阅更新后仍会保留';
}

/// 1.15.0 R22: 当前的前置节点（没有为 null）。
String? museOverrideChainOf(WidgetRef ref, String profileId, String tag) => _overrideOf(ref, profileId).chains[tag];

/// 1.15.0 R22: 链式代理——为 [tag] 选前置节点（[candidates] 来自正在用的配置）。返回提示文字，取消为 null。
Future<String?> showMuseChainDialog(BuildContext context, WidgetRef ref, String profileId, String tag, List<String> candidates) async {
  final current = museOverrideChainOf(ref, profileId, tag);
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      key: const ValueKey('node_chain_dialog'),
      title: const Text('通过另一个节点连接'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, 0, MuseSpace.s24, MuseSpace.s8),
          child: Text(museChainWarning, key: const ValueKey('node_chain_warning'), style: Theme.of(ctx).textTheme.bodySmall),
        ),
        SimpleDialogOption(
          key: const ValueKey('node_chain_none'),
          onPressed: () => Navigator.pop(ctx, ''),
          child: Text(current == null ? '不使用前置节点（当前）' : '不使用前置节点'),
        ),
        for (final c in candidates)
          SimpleDialogOption(
            key: ValueKey('node_chain_pick_$c'),
            onPressed: () => Navigator.pop(ctx, c),
            child: Text(c == current ? '$c（当前）' : c, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
    ),
  );
  if (picked == null || picked == (current ?? '')) return null;
  final o = _overrideOf(ref, profileId);
  await museSaveOverride(ref, profileId, o.withChain(tag, picked).copyWith(enabled: true));
  return picked.isEmpty ? '已取消前置节点' : '已设置：先连「$picked」，再经它连「$tag」';
}

/// 开启前的提示（会变慢）。
const museChainWarning = '流量会先到前置节点，再由它连到这个节点：落地 IP 不变，但速度会变慢、延迟会增加，部分节点不支持 UDP。仅标准内核生效。';

Widget _field(TextEditingController c, String label, {String? key, bool number = false, bool secret = false, String? hint}) => Padding(
  padding: const EdgeInsets.only(bottom: MuseSpace.s8),
  child: TextField(
    key: key == null ? null : ValueKey(key),
    controller: c,
    keyboardType: number ? TextInputType.number : null,
    autocorrect: false,
    enableSuggestions: !secret,
    decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
  ),
);

class MuseNodeFormDialog extends StatefulWidget {
  const MuseNodeFormDialog({super.key});

  @override
  State<MuseNodeFormDialog> createState() => _MuseNodeFormDialogState();
}

class _MuseNodeFormDialogState extends State<MuseNodeFormDialog> {
  var _protocol = MuseFormProtocol.vless;
  var _method = museSsMethods.first;
  var _tls = true;
  var _insecure = false;
  var _ws = false;
  String? _error;
  final _name = TextEditingController();
  final _server = TextEditingController();
  final _port = TextEditingController(text: '443');
  final _uuid = TextEditingController();
  final _password = TextEditingController();
  final _sni = TextEditingController();
  final _path = TextEditingController();
  final _wsHost = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _server, _port, _uuid, _password, _sni, _path, _wsHost]) {
      c.dispose();
    }
    super.dispose();
  }

  MuseNodeForm get _form => MuseNodeForm(
    protocol: _protocol,
    name: _name.text,
    server: _server.text,
    port: _port.text,
    uuid: _uuid.text,
    password: _password.text,
    method: _method,
    tls: _tls,
    sni: _sni.text,
    insecure: _insecure,
    ws: _ws,
    path: _path.text,
    wsHost: _wsHost.text,
  );

  void _save() {
    final f = _form;
    if (f.error != null) return setState(() => _error = f.error);
    Navigator.of(context).pop(f.toLink());
  }

  @override
  Widget build(BuildContext context) {
    final p = _protocol;
    final tlsOn = p == MuseFormProtocol.hysteria2 || (p.tlsOptional && _tls);
    return AlertDialog(
      key: const ValueKey('node_add_dialog'),
      title: const Text('手动添加节点'),
      content: SizedBox(
        width: MuseSize.dialogText,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<MuseFormProtocol>(
                key: const ValueKey('node_add_protocol'),
                initialValue: p,
                decoration: const InputDecoration(labelText: '协议', isDense: true),
                items: [for (final e in MuseFormProtocol.values) DropdownMenuItem(value: e, child: Text(e.label))],
                onChanged: (v) => setState(() => _protocol = v ?? _protocol),
              ),
              const SizedBox(height: MuseSpace.s8),
              _field(_name, '名称', key: 'node_add_name'),
              _field(_server, '地址', key: 'node_add_server', hint: '域名或 IP'),
              _field(_port, '端口', key: 'node_add_port', number: true),
              if (p.usesUuid) _field(_uuid, 'UUID', key: 'node_add_uuid', secret: true),
              if (p.usesPassword) _field(_password, '密码', key: 'node_add_password', secret: true),
              if (p == MuseFormProtocol.shadowsocks)
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: '加密方式', isDense: true),
                  items: [for (final m in museSsMethods) DropdownMenuItem(value: m, child: Text(m))],
                  onChanged: (v) => setState(() => _method = v ?? _method),
                ),
              if (p.tlsOptional)
                SwitchListTile(
                  key: const ValueKey('node_add_tls'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('TLS 加密'),
                  value: _tls,
                  onChanged: (v) => setState(() => _tls = v),
                ),
              if (p.hasTls && tlsOn) ...[
                _field(_sni, 'SNI（可留空）', key: 'node_add_sni'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('跳过证书验证'),
                  subtitle: const Text('仅在自签证书时打开，会降低安全性'),
                  value: _insecure,
                  onChanged: (v) => setState(() => _insecure = v),
                ),
              ],
              if (p.hasTransport) ...[
                SwitchListTile(
                  key: const ValueKey('node_add_ws'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('WebSocket 传输'),
                  value: _ws,
                  onChanged: (v) => setState(() => _ws = v),
                ),
                if (_ws) ...[
                  _field(_path, '路径', key: 'node_add_path', hint: '/'),
                  _field(_wsHost, '伪装域名（可留空）'),
                ],
              ],
              if (_error != null)
                Text(_error!, key: const ValueKey('node_add_error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: MuseSpace.s8),
              Text('保存在当前订阅的覆写里，订阅更新后仍会保留。', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(key: const ValueKey('node_add_save'), onPressed: _save, child: const Text('添加')),
      ],
    );
  }
}

class MuseNodeEditDialog extends StatefulWidget {
  const MuseNodeEditDialog({super.key, required this.original, required this.current});

  final Map<String, dynamic> original;
  final MuseNodeEdit current;

  @override
  State<MuseNodeEditDialog> createState() => _MuseNodeEditDialogState();
}

class _MuseNodeEditDialogState extends State<MuseNodeEditDialog> {
  late final Map<String, dynamic> _shown = widget.current.applyTo(widget.original);
  late final _server = TextEditingController(text: '${_shown['server'] ?? ''}');
  late final _port = TextEditingController(text: '${_shown['server_port'] ?? ''}');
  late final _sni = TextEditingController(text: _shown['tls'] is Map ? '${(_shown['tls'] as Map)['server_name'] ?? ''}' : '');
  late final _uuid = TextEditingController(text: '${_shown['uuid'] ?? ''}');
  late final _password = TextEditingController(text: '${_shown['password'] ?? ''}');
  String? _error;

  bool get _hasTls => widget.original['tls'] is Map;

  @override
  void dispose() {
    for (final c in [_server, _port, _sni, _uuid, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final e = museServerError(_server.text) ?? musePortError(_port.text);
    if (e != null) return setState(() => _error = e);
    Navigator.of(context).pop(
      MuseNodeEdit.diff(
        widget.original,
        server: _server.text,
        port: _port.text,
        sni: _hasTls ? _sni.text : null,
        uuid: widget.original.containsKey('uuid') ? _uuid.text : null,
        password: widget.original.containsKey('password') ? _password.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('node_edit_dialog'),
    title: const Text('编辑节点'),
    content: SizedBox(
      width: MuseSize.dialogText,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_server, '地址', key: 'node_edit_server'),
            _field(_port, '端口', key: 'node_edit_port', number: true),
            if (_hasTls) _field(_sni, 'SNI', key: 'node_edit_sni'),
            if (widget.original.containsKey('uuid')) _field(_uuid, 'UUID', key: 'node_edit_uuid', secret: true),
            if (widget.original.containsKey('password')) _field(_password, '密码', key: 'node_edit_password', secret: true),
            if (_error != null)
              Text(_error!, key: const ValueKey('node_edit_error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: MuseSpace.s8),
            Text('修改只保存在本机，作为本地覆写叠加在订阅上，订阅更新后仍会保留。', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
    actions: [
      if (!widget.current.isEmpty)
        TextButton(key: const ValueKey('node_edit_reset'), onPressed: () => Navigator.of(context).pop(const MuseNodeEdit()), child: const Text('恢复订阅原值')),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      FilledButton(key: const ValueKey('node_edit_save'), onPressed: _save, child: const Text('保存')),
    ],
  );
}
