// 穿云 1.5.0 #43 - 只显示 / 排除 for one subscription (on top of 设置 › 节点's global filters).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The filter of [profileId] (empty when none).
MuseSubFilter museSubFilterOf(String raw, String? profileId) =>
    profileId == null ? const MuseSubFilter() : museParseSubFilters(raw)[profileId] ?? const MuseSubFilter();

Future<void> museEditSubFilter(BuildContext context, WidgetRef ref, String profileId) async {
  final all = museParseSubFilters(ref.read(MusePrefs.subFilters));
  final current = all[profileId] ?? const MuseSubFilter();
  final result = await museShowSubFilterDialog(context, current);
  if (result == null) return;
  await ref.read(MusePrefs.subFilters.notifier).update(museSubFiltersToRaw({...all, profileId: result}));
  try {
    ref.read(inAppNotificationControllerProvider).showSuccessToast('已保存');
  } catch (_) {}
}

Future<MuseSubFilter?> museShowSubFilterDialog(BuildContext context, MuseSubFilter current) =>
    showDialog<MuseSubFilter>(context: context, builder: (c) => _SubFilterDialog(current: current));

class _SubFilterDialog extends StatefulWidget {
  const _SubFilterDialog({required this.current});

  final MuseSubFilter current;

  @override
  State<_SubFilterDialog> createState() => _SubFilterDialogState();
}

class _SubFilterDialogState extends State<_SubFilterDialog> {
  late final _include = TextEditingController(text: widget.current.include);
  late final _exclude = TextEditingController(text: widget.current.exclude);
  String? _includeError;
  String? _excludeError;

  @override
  void dispose() {
    _include.dispose();
    _exclude.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      _includeError = museNodeFilterError(_include.text);
      _excludeError = museNodeFilterError(_exclude.text);
    });
    if (_includeError != null || _excludeError != null) return;
    Navigator.of(context).pop(MuseSubFilter(include: _include.text.trim(), exclude: _exclude.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('节点筛选'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('sub_filter_include'),
            controller: _include,
            decoration: InputDecoration(labelText: '只显示', hintText: '正则，如 香港|日本', errorText: _includeError),
          ),
          const SizedBox(height: MuseSpace.s12),
          TextField(
            key: const ValueKey('sub_filter_exclude'),
            controller: _exclude,
            decoration: InputDecoration(labelText: '排除', hintText: '正则，如 过期|剩余', errorText: _excludeError),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      TextButton(key: const ValueKey('sub_filter_save'), onPressed: _save, child: const Text('保存')),
    ],
  );
}
