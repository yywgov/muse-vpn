// 穿云 1.6.0 C6 - 订阅 › 查看运行配置: the saved config, read only, monospace, secrets redacted.
// Part of 穿云 (GPLv3).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/logic/profile_tools.dart';
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final museRuntimeConfigProvider = FutureProvider.autoDispose.family<String, String>((ref, id) async {
  final repo = await ref.watch(profileRepositoryProvider.future);
  final raw = await repo.getRawConfig(id).getOrElse((_) => '').run();
  if (raw.isEmpty) return '';
  // a big config is formatted and redacted off the UI thread
  return raw.length > 64 * 1024 ? compute(museRuntimeConfigView, raw) : museRuntimeConfigView(raw);
});

Future<void> showMuseRuntimeConfig(BuildContext context, {required String id, required String name}) =>
    showMuseSnapSheet<void>(
      context,
      title: '运行配置 · $name',
      startExpanded: true,
      builder: (context, controller) => _RuntimeConfig(id: id, controller: controller),
    );

class _RuntimeConfig extends ConsumerWidget {
  const _RuntimeConfig({required this.id, required this.controller});

  final String id;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(museRuntimeConfigProvider(id));
    return text.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('读取失败')),
      data: (t) {
        if (t.isEmpty) return const Center(child: Text('还没有配置（先更新一次订阅）'));
        final lines = t.split('\n');
        return Column(
          key: const ValueKey('runtime_config'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
              child: Row(
                children: [
                  Expanded(child: Text('密码、密钥和服务器地址已隐藏', style: MuseType.caption(context))),
                  TextButton(
                    key: const ValueKey('runtime_config_copy'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: t));
                      try {
                        ref.read(inAppNotificationControllerProvider).showSuccessToast('已复制（已脱敏）');
                      } catch (_) {}
                    },
                    child: const Text('复制'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.all(MuseSpace.s16),
                itemCount: lines.length,
                itemBuilder: (context, i) => Text(
                  lines[i],
                  style: MuseType.caption(context).copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Consolas', 'Menlo']),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
