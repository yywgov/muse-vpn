// 穿云 1.20.3 设置 › 隐私：隐私模式、敏感页禁止截屏（安卓）、导入后清空剪贴板，从外观页搬来（键、行为、说明都不变）。
// 1.20.3：改名「隐私与通知」；外观页剩下的 Android「通知与图标」（通知栏断开按钮、隐藏通知、在最近任务中隐藏）也搬来；
// ⓘ 改成副标题。键和行为都不变。
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

class MusePrivacyPage extends ConsumerWidget {
  const MusePrivacyPage({super.key, this.android});

  /// Platform override for tests; null = the running platform.
  final bool? android;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAndroid = android ?? PlatformUtils.isAndroid;
    return MuseScaffold(
      title: musePrivacyTitle,
      body: MuseGroupedBody(
        padding: museSettingsPagePadding(context),
        children: [
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('appearance_privacy'),
                leading: const Icon(Icons.blur_on_outlined),
                title: '隐私模式',
                subtitle: '首页的流量、IP 等数字打码',
                value: ref.watch(MusePrefs.privacyMask),
                onChanged: (v) => ref.read(MusePrefs.privacyMask.notifier).update(v),
              ),
              // 1.16.0 B8: 敏感页禁截屏 (Android only: the window flag)
              if (isAndroid)
                MuseSwitchTile(
                  key: const ValueKey('appearance_secure_sensitive'),
                  leading: const Icon(Icons.screenshot_monitor_outlined),
                  title: '敏感页禁止截屏',
                  subtitle: '节点详情、订阅详情、二维码、导出配置打开时禁止截屏和录屏',
                  value: ref.watch(MusePrefs.secureSensitive),
                  onChanged: (v) => ref.read(MusePrefs.secureSensitive.notifier).update(v),
                ),
              // 1.10.0: from the removed 帮助与隐私 page (same preference)
              MuseSwitchTile(
                key: const ValueKey('clear_clipboard_switch'),
                leading: const Icon(Icons.content_paste_off_outlined),
                title: '导入后清空剪贴板',
                subtitle: '订阅链接里带有密钥，导入后立即清空',
                value: ref.watch(MusePrefs.clearClipboardAfterImport),
                onChanged: (v) => ref.read(MusePrefs.clearClipboardAfterImport.notifier).update(v),
              ),
            ],
          ),
          // 1.20.3：从外观页搬来（Android）
          if (isAndroid) const MuseAndroidAppearanceSection(),
        ],
      ),
    );
  }
}

/// 1.20.3：设置一级与页标题。
const musePrivacyTitle = '隐私与通知';
