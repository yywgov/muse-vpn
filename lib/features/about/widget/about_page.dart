// 穿云 - 设置 > 关于.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
//
// 1.1: 检查更新 downloads and installs the new version in the app; 复制版本信息 and the
// GPL note are gone from here (the credit lives on the 开源许可 page).
// 1.3.0: 导出日志 moved into 诊断 (设置 › 诊断 / 首页 出口 IP tile).
// 1.6.0 C10: 版本与构建号, 内核版本 (bundled release + the running engine while connected), 致谢
// (the GPL credits: the only place the upstream projects are named); tapping the version 7 times
// turns 开发者选项 on (#127).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/changelog_dialog.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart' show museEngineVersionProvider;
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart' show MuseStatusDot;
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final update = ref.watch(museUpdaterProvider);
    final toast = ref.read(inAppNotificationControllerProvider);
    final taps = useMemoized(MuseDevTaps.new);
    final engine = ref.watch(museEngineVersionProvider).valueOrNull;

    Future<void> tapVersion() async {
      final left = taps.tap(DateTime.now());
      final on = ref.read(MusePrefs.devMode);
      if (left == 0) {
        if (on) {
          toast.showInfoToast('开发者选项已开启');
        } else {
          await ref.read(MusePrefs.devMode.notifier).update(true);
          toast.showSuccessToast('已开启开发者选项（设置 › 开发者选项）');
        }
      } else if (left <= 3 && !on) {
        toast.showInfoToast('再点 $left 次开启开发者选项');
      }
    }

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
              message: '之前的版本签名不固定，系统不允许直接覆盖安装。请先在「订阅」里复制好订阅链接，'
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
            padding: const EdgeInsets.symmetric(vertical: MuseSpace.s24),
            child: Column(
              children: [
                ClipRSuperellipse(
                  borderRadius: MuseRadius.cardAll,
                  child: Assets.images.logo.svg(width: MuseSize.emptyArt, height: MuseSize.emptyArt),
                ),
                const Gap(MuseSpace.s12),
                Text(Constants.appName, style: MuseType.title(context)),
                const Gap(MuseSpace.s4),
                GestureDetector(
                  key: const ValueKey('about_version'),
                  behavior: HitTestBehavior.opaque,
                  onTap: tapVersion,
                  child: Padding(
                    padding: const EdgeInsets.all(MuseSpace.s4),
                    child: Text('版本 ${appInfo.presentVersion}', style: MuseType.caption(context)),
                  ),
                ),
              ],
            ),
          ),
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('about_app_version'),
                leading: const Icon(Icons.info_outlined),
                title: '版本',
                subtitle: '${appInfo.presentVersion}（构建 ${appInfo.buildNumber}）',
                onTap: tapVersion,
              ),
              MuseTile(
                key: const ValueKey('about_core_version'),
                leading: const Icon(Icons.memory_outlined),
                title: '内核版本',
                subtitle: museCoreVersionLabel(engine: engine),
                subtitleMaxLines: 2,
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseTile(
                leading: const Icon(Icons.system_update_outlined),
                title: '检查更新',
                subtitle: updateStatus,
                trailing: update is MuseUpdateIdle
                    ? null
                    : const SizedBox(width: MuseIconSize.small, height: MuseIconSize.small, child: CircularProgressIndicator(strokeWidth: 2)),
                chevron: update is MuseUpdateIdle,
                onTap: update is MuseUpdateIdle ? checkUpdate : null,
              ),
              // 1.5.0: 更新内容 lives here (a small update only shows a dot, no dialog)
              MuseTile(
                key: const ValueKey('about_changelog'),
                leading: const Icon(Icons.article_outlined),
                title: '更新内容',
                trailing: ref.watch(museChangelogDotProvider) ? const MuseStatusDot(color: MusePalette.red) : null,
                chevron: true,
                onTap: () => showMuseChangelogDialog(context, ref, version: appInfo.version),
              ),
              MuseTile(
                leading: const Icon(Icons.code_outlined),
                title: '开源许可 · 源代码',
                chevron: true,
                onTap: () => context.goNamed('openSource'),
              ),
            ],
          ),
          // the GPL credits — the only place in the app the upstream projects are named
          const MuseSection(
            header: '致谢',
            footer: '穿云以 GPL-3.0 协议开源',
            children: [
              MuseTile(
                key: ValueKey('about_credit_ui'),
                leading: Icon(Icons.design_services_outlined),
                title: '界面设计参考 FlClash',
                subtitle: 'chen08209 · GPL-3.0',
              ),
              MuseTile(
                key: ValueKey('about_credit_base'),
                leading: Icon(Icons.account_tree_outlined),
                title: '基于 Hiddify 开发',
                subtitle: 'GPL-3.0',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
