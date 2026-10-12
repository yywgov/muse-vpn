// 穿云 - 设置 > 关于.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/data/diagnostics.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final theme = Theme.of(context);

    return MuseScaffold(
      title: '关于',
      body: MuseGroupedBody(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Assets.images.logo.svg(width: 72, height: 72),
                ),
                const Gap(12),
                Text(Constants.appName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Gap(4),
                Text(
                  '版本 ${appInfo.presentVersion}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: MuseColors.secondaryText(context)),
                ),
              ],
            ),
          ),
          MuseSection(
            footer: '穿云基于开源项目 Hiddify 修改，以 GPLv3 许可发布，仅供学习交流，不得用于商业用途。',
            children: [
              MuseTile(
                leading: const Icon(Icons.system_update_rounded),
                title: '检查更新',
                subtitle: '在 GitHub 发布页查看最新版本',
                chevron: true,
                onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.githubReleasesUrl)),
              ),
              MuseTile(
                leading: const Icon(Icons.code_rounded),
                title: '开源许可 · 源代码',
                chevron: true,
                onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.githubUrl)),
              ),
              MuseTile(
                leading: const Icon(Icons.copy_rounded),
                title: '复制版本信息',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: appInfo.format()));
                  ref.read(inAppNotificationControllerProvider).showSuccessToast('已复制');
                },
              ),
            ],
          ),
          // 穿云: deliberately low-key — only needed when reporting a connection problem
          MuseSection(
            footer: '连接异常时可导出，内含断开原因与最近日志，仅在你主动分享时才会发出。',
            children: [
              MuseTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: '导出诊断',
                onTap: () async {
                  final ok = await MuseDiagnostics.export(ref);
                  if (!ok && context.mounted) {
                    ref.read(inAppNotificationControllerProvider).showErrorToast('导出失败');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
