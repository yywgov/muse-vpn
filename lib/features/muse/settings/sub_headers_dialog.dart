// 穿云 1.14.0 R14 - 订阅 ⋯ › 请求头: one 「名称: 值」 per line, checked before saving.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/sub_headers.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Edits [profileId]'s headers; true when something was saved.
Future<bool> showMuseSubHeadersDialog(BuildContext context, WidgetRef ref, String profileId) async {
  final all = museParseSubHeaders(ref.read(MusePrefs.subHeaders));
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (c) => MuseSubHeadersDialog(initial: all[profileId] ?? const {}),
  );
  if (result == null) return false;
  await ref.read(MusePrefs.subHeaders.notifier).update(museEncodeSubHeaders(all, profileId, result));
  return true;
}

class MuseSubHeadersDialog extends StatefulWidget {
  const MuseSubHeadersDialog({super.key, required this.initial});

  final Map<String, String> initial;

  @override
  State<MuseSubHeadersDialog> createState() => _MuseSubHeadersDialogState();
}

class _MuseSubHeadersDialogState extends State<MuseSubHeadersDialog> {
  late final TextEditingController _c = TextEditingController(text: museHeaderLines(widget.initial));
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final r = museParseHeaderLines(_c.text);
    if (r.error != null) {
      setState(() => _error = r.error);
      return;
    }
    Navigator.of(context).pop(r.headers);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('sub_headers_dialog'),
    title: const Text('订阅请求头'),
    content: SizedBox(
      width: MuseSize.dialogText,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('更新这个订阅时一起发送，用于需要令牌或设备号的面板。每行一个，格式「名称: 值」。只保存在本机，不会同步或备份，日志中会打码。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: MuseSpace.s12),
          TextField(
            key: const ValueKey('sub_headers_field'),
            controller: _c,
            minLines: 3,
            maxLines: 6,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(hintText: '名称: 值（每行一个）', errorText: _error, errorMaxLines: 3),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      TextButton(key: const ValueKey('sub_headers_clear'), onPressed: () => Navigator.of(context).pop(const <String, String>{}), child: const Text('清空')),
      FilledButton(key: const ValueKey('sub_headers_save'), onPressed: _save, child: const Text('保存')),
    ],
  );
}
