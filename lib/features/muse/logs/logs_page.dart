// 穿云 1.6.0 C3 - 日志: live core logs while 日志记录 is on (off by default: nothing is collected
// then). Level filter, search, pause, copy and a redacted export. At most 1000 lines in memory.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/redact.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show museSaveTextFile;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_card.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const museLogLevelTitles = {'debug': '调试', 'info': '信息', 'warning': '警告', 'error': '错误'};

/// The lines as exported / copied: time, level, redacted text.
String museLogExportText(List<MuseLogLine> lines) => [
  for (final l in lines)
    '${l.time.toIso8601String()} ${museLogLevelTitles[l.level] ?? l.level} ${museRedact(l.text)}',
].join('\n');

class MuseLogsPage extends HookConsumerWidget {
  const MuseLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capture = ref.watch(MusePrefs.logCapture);
    final level = ref.watch(museLogLevelProvider);
    final query = useState('');
    final paused = useState<List<MuseLogLine>?>(null);
    final live = ref.watch(museLogsProvider).valueOrNull ?? const <MuseLogLine>[];
    final source = paused.value ?? live;
    final lines = [for (final l in source) if (museLogPasses(l, level, query.value)) l];
    final scheme = Theme.of(context).colorScheme;
    final n = ref.read(inAppNotificationControllerProvider);

    Color levelColor(String l) => switch (l) {
      'error' => scheme.error,
      'warning' => scheme.warning,
      'debug' => scheme.onSurfaceVariant,
      _ => scheme.primary,
    };

    return MuseScaffold(
      title: '日志',
      actions: [
        IconButton(
          key: const ValueKey('logs_pause'),
          tooltip: paused.value == null ? '暂停' : '继续',
          icon: Icon(paused.value == null ? Icons.pause_outlined : Icons.play_arrow_outlined),
          onPressed: capture ? () => paused.value = paused.value == null ? List.of(live) : null : null,
        ),
        IconButton(
          tooltip: '复制',
          icon: const Icon(Icons.copy_outlined),
          onPressed: lines.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: museLogExportText(lines)));
                  n.showSuccessToast('已复制 ${lines.length} 行（已脱敏）');
                },
        ),
        IconButton(
          tooltip: '导出',
          icon: const Icon(Icons.save_alt_outlined),
          onPressed: lines.isEmpty ? null : () => museSaveTextFile(context, 'chuanyun-logs.txt', museLogExportText(lines)),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(MuseSpace.page(context), 0, MuseSpace.page(context), MuseSpace.s8),
            child: Column(
              children: [
                MuseSectionGroup(
                  children: [
                    MuseSwitchRow(
                      key: const ValueKey('logs_capture'),
                      title: '日志记录',
                      subtitle: '只在打开时采集，最多保留最近 1000 行，不写入磁盘',
                      value: capture,
                      onChanged: (v) {
                        ref.read(MusePrefs.logCapture.notifier).update(v);
                        if (!v) ref.read(museLogBufferProvider).clear();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: MuseSpace.s8),
                SegmentedButton<String>(
                  key: const ValueKey('logs_level'),
                  segments: [for (final l in museLogLevels) ButtonSegment(value: l, label: Text(museLogLevelTitles[l]!))],
                  selected: {level},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => ref.read(museLogLevelProvider.notifier).state = s.first,
                ),
                const SizedBox(height: MuseSpace.s8),
                TextField(
                  key: const ValueKey('logs_search'),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_outlined), hintText: '搜索日志', isDense: true),
                  onChanged: (v) => query.value = v,
                ),
              ],
            ),
          ),
          Expanded(
            child: !capture
                ? Center(child: Text('打开「日志记录」后显示内核实时日志', style: MuseTextLevel.subheadline.style(context, color: scheme.onSurfaceVariant)))
                : lines.isEmpty
                ? Center(child: Text(ref.watch(museLocalApiProvider) == null ? '连接后显示实时日志' : '暂无日志', style: MuseTextLevel.subheadline.style(context, color: scheme.onSurfaceVariant)))
                : ListView.builder(
                    key: const ValueKey('logs_list'),
                    reverse: true,
                    padding: EdgeInsets.fromLTRB(MuseSpace.page(context), 0, MuseSpace.page(context), MuseSpace.s16),
                    itemCount: lines.length,
                    itemBuilder: (_, i) {
                      final l = lines[lines.length - 1 - i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${museLogLevelTitles[l.level] ?? l.level} ', style: TextStyle(color: levelColor(l.level), fontWeight: FontWeight.w600)),
                              TextSpan(text: l.text),
                            ],
                          ),
                          style: MuseTextLevel.footnote.style(context),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
