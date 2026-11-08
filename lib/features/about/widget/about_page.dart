// 穿云 - 设置 > 关于.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
//
// 1.1: 检查更新 downloads and installs the new version in the app.
// 1.10.0: the whole page is the centred icon, the name and one small line
// 「1.10.0（193）· 内核 muse.20」. Tapping that line checks for updates (a new version's notes are
// in the dialog; 「已是最新版本」 otherwise) and the line itself shows 正在检查 / 下载进度. One small
// link at the bottom opens 开源许可与致谢 (license, source, the GPL credits). Tapping the icon 7
// times turns 开发者选项 on (#127).
// 1.10.1: the tappable line now says 「点击检测更新」 (primary colour) while idle, 正在检查 / 下载进度
// while busy; the version line 「1.10.1（194）· 内核 muse.20」 sits right below it as plain grey
// caption text and is not tappable.
// 1.11.0: 设置 › 备份与同步 is gone; 导出配置 / 导入配置 are two small links at the bottom, next to
// 开源许可与致谢 (same backup file as before; old backups still import).

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
import 'package:hiddify/features/muse/logic/help_content.dart' show museFileSizeText;
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show museExportConfig, museImportConfig, museExportConfigTitle, museImportConfigTitle;
import 'package:hiddify/features/muse/update/muse_updater.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 1.10.1: what the update line on 关于 says while idle.
const museAboutCheckUpdateLabel = '点击检测更新';

/// 1.10.0: what the update line on 关于 says while an update is checked / downloaded (1.10.1: null =
/// idle, the line then says [museAboutCheckUpdateLabel]).
String? museAboutUpdateStatus(MuseUpdateState state) => switch (state) {
  MuseUpdateChecking() => '正在检查更新…',
  MuseUpdateVerifying() => '正在校验安装包…',
  MuseUpdateDownloading(:final progress) => progress == null ? '正在下载…' : '正在下载 ${(progress * 100).toStringAsFixed(0)}%',
  MuseUpdateIdle() => null,
};

/// 1.10.0: the body of the 「发现新版本」 dialog: size, the new version's notes, what happens next.
String museUpdateDialogMessage({required int size, required List<String> notes, required bool pageOnly, required bool windows}) {
  final b = StringBuffer();
  final sizeText = museFileSizeText(size);
  if (sizeText.isNotEmpty) b.write('大小 $sizeText。');
  b.write(
    pageOnly
        ? '将在浏览器中打开下载页面。'
        : windows
        ? '下载后自动安装并重新打开穿云，设置和订阅都会保留。'
        : '下载后打开系统安装界面，安装后设置和订阅都会保留。',
  );
  if (notes.isNotEmpty) {
    b.write('\n\n更新内容：');
    for (final n in notes) {
      b.write('\n· $n');
    }
  }
  return b.toString();
}

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final update = ref.watch(museUpdaterProvider);
    final toast = ref.read(inAppNotificationControllerProvider);
    final taps = useMemoized(MuseDevTaps.new);
    final mt = MuseTheme.of(context);

    Future<void> tapIcon() async {
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
      } catch (e) {
        toast.showErrorToast(e is MuseUpdateFailure ? museUpdateFailureText(e) : '检查更新失败，请稍后再试');
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
            message: museUpdateDialogMessage(
              size: release.apkSize,
              notes: updater.lastNotes,
              pageOnly: pageOnly,
              windows: PlatformUtils.isWindows,
            ),
            positiveBtnTxt: pageOnly ? '打开下载页面' : '下载并安装',
          );
      if (!ok) return;
      // 1.17.0 B12: a failed download offers 「重试」 (keeps what was downloaded, 断点续传) or, after a
      // failed checksum, 「重新下载」 (starts over); at most 5 rounds without leaving the dialog
      for (var round = 0; ; round++) {
      try {
        final opened = await updater.downloadAndInstall(release);
        if (!opened && !PlatformUtils.isWindows) toast.showInfoToast('请允许穿云「安装未知应用」，然后再点一次「点击检测更新」');
        return;
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
        return;
      } catch (e) {
        final startsOver = e is MuseUpdateFailure && e.startsOver;
        if (startsOver) await updater.discardDownload(release);
        if (round >= 4 || !context.mounted) {
          toast.showErrorToast('更新没有完成，请稍后再试');
          return;
        }
        final again = await ref
            .read(dialogNotifierProvider.notifier)
            .showConfirmation(
              title: '更新没有完成',
              message: museUpdateFailureText(e),
              positiveBtnTxt: startsOver ? '重新下载' : '重试',
            );
        if (!again) return;
      }
      }
    }

    final status = museAboutUpdateStatus(update);
    final idle = update is MuseUpdateIdle;
    return MuseScaffold(
      title: '关于',
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(MuseSpace.s24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        key: const ValueKey('about_icon'),
                        behavior: HitTestBehavior.opaque,
                        onTap: tapIcon,
                        child: ClipRSuperellipse(
                          borderRadius: MuseRadius.cardAll,
                          child: Assets.images.logo.svg(width: MuseSize.emptyArt, height: MuseSize.emptyArt),
                        ),
                      ),
                      const Gap(MuseSpace.s12),
                      Text(Constants.appName, style: MuseType.title(context)),
                      const Gap(MuseSpace.s4),
                      Semantics(
                        button: idle,
                        label: idle ? '检查更新' : null,
                        child: InkWell(
                          key: const ValueKey('about_check_update'),
                          borderRadius: MuseRadius.smallAll,
                          onTap: idle ? checkUpdate : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8, vertical: MuseSpace.s4),
                            child: Text(
                              status ?? museAboutCheckUpdateLabel,
                              key: const ValueKey('about_check_update_text'),
                              textAlign: TextAlign.center,
                              style: MuseType.body(context).copyWith(
                                color: idle ? museBrandOf(context) : mt.text2,
                                fontFeatures: MuseType.tabular,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        museAboutVersionLine(version: appInfo.version, build: appInfo.buildNumber),
                        key: const ValueKey('about_version_text'),
                        textAlign: TextAlign.center,
                        style: MuseType.caption(context).copyWith(color: mt.text2, fontFeatures: MuseType.tabular),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: MuseSpace.s16),
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final (key, label, onTap) in [
                    (const ValueKey('about_export_config'), museExportConfigTitle, () => museExportConfig(context, ref)),
                    (const ValueKey('about_import_config'), museImportConfigTitle, () => museImportConfig(context, ref)),
                    (const ValueKey('about_open_source'), '开源许可与致谢', () => context.goNamed('openSource')),
                  ])
                    TextButton(
                      key: key,
                      style: TextButton.styleFrom(foregroundColor: mt.text2, visualDensity: VisualDensity.compact),
                      onPressed: onTap,
                      child: Text(label, style: MuseType.caption(context).copyWith(color: mt.text2)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
