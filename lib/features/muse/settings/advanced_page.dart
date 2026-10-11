// 穿云 - 设置 > 高级: rarely needed knobs (core, ports, TLS 技巧, settings backup).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AdvancedPage extends HookConsumerWidget {
  const AdvancedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dialogs = ref.read(dialogNotifierProvider.notifier);
    final options = ref.read(configOptionNotifierProvider.notifier);
    final secondary = MuseColors.secondaryText(context);

    String minutes(Duration d) => d.inMinutes < 1 ? '${d.inSeconds} 秒' : '${d.inMinutes} 分钟';

    Future<void> confirmImport(Future<void> Function() run) async {
      final ok = await dialogs.showConfirmation(title: '导入设置', message: '导入会覆盖当前的设置，确定继续吗？', positiveBtnTxt: '导入');
      if (ok) await run();
    }

    return MuseScaffold(
      title: '高级',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '连接',
            children: [
              MuseTile(
                title: '入站与 VPN 模式',
                subtitle: 'VPN / 仅代理、本地端口、局域网共享',
                chevron: true,
                onTap: () => context.goNamed('inboundOptions'),
              ),
              MuseTile(
                title: 'TLS 分片 / 技巧',
                subtitle: '默认关闭，只在个别网络屏蔽 SNI 时才需要',
                chevron: true,
                onTap: () => context.goNamed('tlsTricks'),
              ),
              MuseTile(
                title: '测速地址',
                subtitle: ref.watch(ConfigOptions.connectionTestUrl),
                subtitleMaxLines: 1,
                onTap: () async {
                  final value = await dialogs.showSettingInput<String>(
                    title: '测速地址',
                    initialValue: ref.read(ConfigOptions.connectionTestUrl),
                    possibleValues: ref.read(ConfigOptions.connectionTestUrl.notifier).possibleValues,
                    onReset: ref.read(ConfigOptions.connectionTestUrl.notifier).reset,
                    validator: isUrl,
                  );
                  if (value != null) await ref.read(ConfigOptions.connectionTestUrl.notifier).update(value);
                },
              ),
              MuseTile(
                title: '自动测速间隔',
                subtitle: '自动最快和节点失效切换按这个间隔重新测速',
                trailing: Text(minutes(ref.watch(ConfigOptions.urlTestInterval)), style: TextStyle(color: secondary)),
                onTap: () async {
                  final value = await dialogs.showSettingSlider(
                    title: '自动测速间隔（分钟）',
                    initialValue: ref.read(ConfigOptions.urlTestInterval).inMinutes.coerceIn(1, 60).toDouble(),
                    onReset: ref.read(ConfigOptions.urlTestInterval.notifier).reset,
                    min: 1,
                    max: 60,
                    divisions: 59,
                    labelGen: (value) => '${value.toInt()} 分钟',
                  );
                  if (value != null) {
                    await ref.read(ConfigOptions.urlTestInterval.notifier).update(Duration(minutes: value.toInt()));
                  }
                },
              ),
              MuseSwitchTile(
                title: '自动检测出口 IP',
                subtitle: '连接后查询当前节点的出口 IP 和国家',
                value: ref.watch(Preferences.autoCheckIp),
                onChanged: ref.read(Preferences.autoCheckIp.notifier).update,
              ),
            ],
          ),
          MuseSection(
            header: '内核',
            children: [
              MuseSwitchTile(
                title: '内存限制',
                subtitle: '遇到内存不足或频繁崩溃时再打开',
                value: !ref.watch(Preferences.disableMemoryLimit),
                onChanged: (value) => ref.read(Preferences.disableMemoryLimit.notifier).update(!value),
              ),
              MuseSwitchTile(
                title: '尽量使用 Xray 内核解析',
                subtitle: '解析订阅时优先用 Xray，重新导入订阅后生效',
                value: ref.watch(ConfigOptions.useXrayCoreWhenPossible),
                onChanged: ref.read(ConfigOptions.useXrayCoreWhenPossible.notifier).update,
              ),
              MuseTile(
                title: 'Clash API 端口',
                trailing: Text('${ref.watch(ConfigOptions.clashApiPort)}', style: TextStyle(color: secondary)),
                onTap: () async {
                  final value = await dialogs.showSettingInput<int>(
                    title: 'Clash API 端口',
                    initialValue: ref.read(ConfigOptions.clashApiPort),
                    mapTo: int.tryParse,
                    validator: isPort,
                    digitsOnly: true,
                    onReset: ref.read(ConfigOptions.clashApiPort.notifier).reset,
                  );
                  if (value != null) await ref.read(ConfigOptions.clashApiPort.notifier).update(value);
                },
              ),
            ],
          ),
          MuseSection(
            header: '备份',
            footer: '「导出」不含局域网共享密码等私密内容。',
            children: [
              MuseTile(
                title: '从剪贴板导入设置',
                onTap: () => confirmImport(options.importFromClipboard),
              ),
              MuseTile(title: '从文件导入设置', onTap: () => confirmImport(options.importFromJsonFile)),
              MuseTile(title: '导出设置到剪贴板', onTap: () => options.exportJsonClipboard()),
              MuseTile(title: '导出设置到文件', onTap: () => options.exportJsonFile()),
              MuseTile(
                title: '恢复默认设置',
                trailing: Icon(Icons.restart_alt_rounded, color: Theme.of(context).colorScheme.error),
                onTap: () => options.resetOption(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
