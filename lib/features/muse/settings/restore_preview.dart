// 穿云 1.6.0 C10 - 从备份恢复 › 预览: choose 恢复范围 (全部 / 仅订阅 / 仅设置) and 恢复策略
// (合并 / 覆盖), see what would change, then restore. 覆盖 asks once more. Subscriptions are only
// ever added; the current state is saved as an automatic backup before anything is written
// (MuseSyncService.applyRestore).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/logic/restore_plan.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_segmented.dart';

typedef MuseRestorePlanner = Future<MuseRestorePlan> Function(MuseRestoreScope scope, MuseRestoreStrategy strategy);

/// The preview dialog; the plan to carry out, or null when cancelled.
Future<MuseRestorePlan?> showMuseRestorePreview(BuildContext context, MuseRestorePlanner planner, {String? source}) async {
  final plan = await showDialog<MuseRestorePlan>(
    context: context,
    builder: (_) => MuseRestorePreview(planner: planner, source: source),
  );
  if (plan == null || plan.strategy != MuseRestoreStrategy.overwrite || !context.mounted) return plan;
  final sure = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('覆盖恢复'),
      content: Text(
        [
          if (plan.settingsReset > 0) '备份里没有的 ${plan.settingsReset} 项设置将恢复默认值。',
          '订阅不会被删除。恢复前会自动备份当前配置，可在「自动备份」里撤销。',
        ].join('\n'),
      ),
      actions: [
        TextButton(key: const ValueKey('restore_overwrite_cancel'), onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
        FilledButton(key: const ValueKey('restore_overwrite_ok'), onPressed: () => Navigator.of(c).pop(true), child: const Text('覆盖')),
      ],
    ),
  );
  return sure == true ? plan : null;
}

class MuseRestorePreview extends StatefulWidget {
  const MuseRestorePreview({super.key, required this.planner, this.source});

  final MuseRestorePlanner planner;

  /// where the backup came from (自动备份 · 10-27 09:00), shown under the title
  final String? source;

  @override
  State<MuseRestorePreview> createState() => _MuseRestorePreviewState();
}

class _MuseRestorePreviewState extends State<MuseRestorePreview> {
  var _scope = MuseRestoreScope.all;
  var _strategy = MuseRestoreStrategy.merge;
  MuseRestorePlan? _plan;
  var _loading = true;
  var _gen = 0;

  @override
  void initState() {
    super.initState();
    _replan();
  }

  Future<void> _replan() async {
    final gen = ++_gen;
    setState(() => _loading = true);
    MuseRestorePlan? plan;
    try {
      plan = await widget.planner(_scope, _strategy);
    } catch (_) {
      plan = null;
    }
    if (!mounted || gen != _gen) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final plan = _plan;
    final caption = MuseType.caption(context).copyWith(color: mt.text2);
    const shown = 5;
    return AlertDialog(
      title: const Text('从备份恢复'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: MuseSize.dialogText),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.source != null) ...[
                Text(widget.source!, style: caption),
                const SizedBox(height: MuseSpace.s12),
              ],
              Text('恢复范围', style: MuseType.body(context)),
              const SizedBox(height: MuseSpace.s8),
              MuseSegmented<MuseRestoreScope>(
                key: const ValueKey('restore_scope'),
                values: MuseRestoreScope.values,
                selected: _scope,
                label: (s) => s.title,
                onChanged: (s) {
                  _scope = s;
                  _replan();
                },
              ),
              const SizedBox(height: MuseSpace.s12),
              Text('恢复策略', style: MuseType.body(context)),
              const SizedBox(height: MuseSpace.s8),
              MuseSegmented<MuseRestoreStrategy>(
                key: const ValueKey('restore_strategy'),
                values: MuseRestoreStrategy.values,
                selected: _strategy,
                label: (s) => s.title,
                onChanged: (s) {
                  _strategy = s;
                  _replan();
                },
              ),
              const SizedBox(height: MuseSpace.s4),
              Text(
                _strategy == MuseRestoreStrategy.merge ? '只写入备份里的设置，其他保持不变' : '设置与备份完全一致：备份里没有的设置恢复默认值',
                style: caption,
              ),
              const SizedBox(height: MuseSpace.s16),
              if (_loading)
                const Center(
                  child: SizedBox(
                    width: MuseIconSize.small,
                    height: MuseIconSize.small,
                    child: CircularProgressIndicator(strokeWidth: MuseSize.spinnerStroke),
                  ),
                )
              else if (plan == null)
                Text('读取当前配置失败', key: const ValueKey('restore_summary'), style: MuseType.body(context))
              else ...[
                Text(plan.summary, key: const ValueKey('restore_summary'), style: MuseType.body(context)),
                for (final s in plan.subsToAdd.take(shown))
                  Padding(
                    padding: const EdgeInsets.only(top: MuseSpace.s4),
                    child: Text('＋ ${museRestoreSubTitle(s)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: caption),
                  ),
                if (plan.subsToAdd.length > shown)
                  Padding(
                    padding: const EdgeInsets.only(top: MuseSpace.s4),
                    child: Text('…等 ${plan.subsToAdd.length} 个', style: caption),
                  ),
                if (plan.subsAlreadyHere > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: MuseSpace.s4),
                    child: Text('已有的 ${plan.subsAlreadyHere} 个订阅保持不变', style: caption),
                  ),
              ],
              const SizedBox(height: MuseSpace.s12),
              Text('订阅只增不删；恢复前会自动备份当前配置', style: caption),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(key: const ValueKey('restore_cancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          key: const ValueKey('restore_ok'),
          onPressed: _loading || plan == null || plan.isEmpty ? null : () => Navigator.of(context).pop(plan),
          child: const Text('恢复'),
        ),
      ],
    );
  }
}
