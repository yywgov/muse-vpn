// 穿云 - 设置 > 高级: the rarely needed knobs that stay (TLS 分片 / 技巧, 我的宽带).
// 1.0 removed the developer options (run mode, ports, core, test URL, backup).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AdvancedPage extends HookConsumerWidget {
  const AdvancedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final up = ConfigOptions.museBandwidth(ref.watch(ConfigOptions.hysteria2UpMbps));
    final down = ConfigOptions.museBandwidth(ref.watch(ConfigOptions.hysteria2DownMbps));
    return MuseScaffold(
      title: '高级',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                title: 'TLS 分片 / 技巧',
                chevron: true,
                onTap: () => context.goNamed('tlsTricks'),
              ),
              MuseTile(
                key: const ValueKey('bandwidth_tile'),
                title: '我的宽带',
                trailing: Text(museBandwidthLabel(up, down)),
                chevron: true,
                onTap: () => _editBandwidth(context, ref, up, down),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editBandwidth(BuildContext context, WidgetRef ref, int up, int down) async {
    final upCtrl = TextEditingController(text: up > 0 ? '$up' : '');
    final downCtrl = TextEditingController(text: down > 0 ? '$down' : '');
    Widget field(TextEditingController c, String label, IconData icon) => TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      decoration: InputDecoration(prefixIcon: Icon(icon), labelText: label, hintText: '自动', suffixText: 'Mbps'),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('我的宽带'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(upCtrl, '上行', Icons.arrow_upward_rounded),
            const SizedBox(height: 12),
            field(downCtrl, '下行', Icons.arrow_downward_rounded),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(ConfigOptions.hysteria2UpMbps.notifier).update(museParseBandwidth(upCtrl.text));
    await ref.read(ConfigOptions.hysteria2DownMbps.notifier).update(museParseBandwidth(downCtrl.text));
  }
}

/// Blank or invalid input = automatic (0).
int museParseBandwidth(String text) => ConfigOptions.museBandwidth(int.tryParse(text.trim()) ?? 0);

String museBandwidthLabel(int up, int down) {
  if (up <= 0 && down <= 0) return '自动';
  String v(int x) => x > 0 ? '$x' : '自动';
  return '↑${v(up)} ↓${v(down)}';
}
