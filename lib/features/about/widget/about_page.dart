// 穿云 - 设置 > 关于.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
//
// 1.1: 检查更新 downloads and installs the new version in the app; 复制版本信息 and the
// Hiddify/GPL note are gone from here (the credit lives on the 开源许可 page).

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/diagnostics.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final theme = Theme.of(context);
    final update = ref.watch(museUpdaterProvider);
    final toast = ref.read(inAppNotificationControllerProvider);

    Future<void> checkUpdate() async {
      final updater = ref.read(museUpdaterProvider.notifier);
      final MuseRelease? release;
      try {
        release = await updater.check();
      } catch (_) {
        toast.showErrorToast('检查更新失败，请稍后再试');
        return;
      }
      if (release == null) {
        toast.showSuccessToast('已是最新版本');
        return;
      }
      final pageOnly = PlatformUtils.isWindows && (!museIsWindowsInstaller(release) || release.sha256 == null);
      final ok = await ref
          .read(dialogNotifierProvider.notifier)
          .showConfirmation(
            title: '发现新版本 ${release.version}',
            message: pageOnly
                ? '将在浏览器中打开下载页面。'
                : PlatformUtils.isWindows
                ? '下载后自动安装并重新打开穿云，设置和订阅都会保留。'
                : '下载后打开系统安装界面，安装后设置和订阅都会保留。',
            positiveBtnTxt: pageOnly ? '打开下载页面' : '下载并安装',
          );
      if (!ok) return;
      try {
        final opened = await updater.downloadAndInstall(release);
        if (!opened && !PlatformUtils.isWindows) toast.showInfoToast('请允许穿云「安装未知应用」，然后再点一次检查更新');
      } on MuseSignatureChanged catch (e) {
        // 1.2.4: earlier builds were signed with a different key each time; from now on the key
        // stays the same. This one switch needs the old version removed first.
        final go = await ref
            .read(dialogNotifierProvider.notifier)
            .showConfirmation(
              title: '需要先卸载旧版（仅此一次）',
              message: '之前的版本签名不固定，系统不允许直接覆盖安装。请先在「订阅/配置」里复制好订阅链接，'
                  '然后卸载穿云，再安装刚下载的新版。从这个版本起签名固定，以后点更新就能直接覆盖安装。',
              positiveBtnTxt: '打开安装包',
            );
        if (go) await ChuanyunPlatform.installApk(e.path);
      } catch (_) {
        toast.showErrorToast('下载失败，请稍后再试');
      }
    }

    final String? updateStatus = switch (update) {
      MuseUpdateChecking() => '正在检查…',
      MuseUpdateDownloading(:final progress) =>
        progress == null ? '正在下载…' : '正在下载 ${(progress * 100).toStringAsFixed(0)}%',
      MuseUpdateIdle() => null,
    };

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
            children: [
              MuseTile(
                leading: const Icon(Icons.system_update_rounded),
                title: '检查更新',
                subtitle: updateStatus,
                trailing: update is MuseUpdateIdle
                    ? null
                    : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                chevron: update is MuseUpdateIdle,
                onTap: update is MuseUpdateIdle ? checkUpdate : null,
              ),
              MuseTile(
                leading: const Icon(Icons.code_rounded),
                title: '开源许可 · 源代码',
                chevron: true,
                onTap: () => context.goNamed('openSource'),
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
