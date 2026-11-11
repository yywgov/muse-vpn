// 穿云 1.20.3 设置 › 隐私：隐私模式、敏感页禁止截屏（安卓）、导入后清空剪贴板，从外观页搬来（键、行为、说明都不变）。
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

class MusePrivacyPage extends ConsumerWidget {
  const MusePrivacyPage({super.key, this.android});

  /// Platform override for tests; null = the running platform.
  final bool? android;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MuseScaffold(
      title: '隐私',
      body: MuseGroupedBody(
        padding: museSettingsPagePadding(context),
        children: [
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('appearance_privacy'),
                leading: const Icon(Icons.blur_on_outlined),
                title: '隐私模式',
                info: '首页的流量、IP 等数字打码',
                value: ref.watch(MusePrefs.privacyMask),
                onChanged: (v) => ref.read(MusePrefs.privacyMask.notifier).update(v),
              ),
              // 1.16.0 B8: 敏感页禁截屏 (Android only: the window flag)
              if (android ?? PlatformUtils.isAndroid)
                MuseSwitchTile(
                  key: const ValueKey('appearance_secure_sensitive'),
                  leading: const Icon(Icons.screenshot_monitor_outlined),
                  title: '敏感页禁止截屏',
                  info: '节点详情、订阅详情、二维码、导出配置打开时禁止截屏和录屏，在最近任务里也只显示空白',
                  value: ref.watch(MusePrefs.secureSensitive),
                  onChanged: (v) => ref.read(MusePrefs.secureSensitive.notifier).update(v),
                ),
              // 1.10.0: from the removed 帮助与隐私 page (same preference)
              MuseSwitchTile(
                key: const ValueKey('clear_clipboard_switch'),
                leading: const Icon(Icons.content_paste_off_outlined),
                title: '导入后清空剪贴板',
                info: '从剪贴板导入订阅链接后，立即清空剪贴板（链接里带有密钥）',
                value: ref.watch(MusePrefs.clearClipboardAfterImport),
                onChanged: (v) => ref.read(MusePrefs.clearClipboardAfterImport.notifier).update(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
