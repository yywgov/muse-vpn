// 穿云 - 设置 › 连接信息：本次流量、当前节点、出口 IP、活动连接。
// Part of 穿云 (Chuanyun), a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseDataPage extends HookConsumerWidget {
  const MuseDataPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(serviceRunningProvider);
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();
    final activeProxy = running ? ref.watch(activeProxyNotifierProvider).valueOrNull : null;

    Widget value(String text) => Text(text, style: Theme.of(context).textTheme.bodyMedium);

    return Scaffold(
      backgroundColor: MuseColors.background(context),
      appBar: AppBar(
        backgroundColor: MuseColors.background(context),
        scrolledUnderElevation: 0,
        title: const Text('连接信息'),
      ),
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '本次连接流量',
            footer: running ? null : '未连接，连接后开始统计。',
            children: [
              MuseTile(title: '已上传', trailing: value(stats.uplinkTotal.toInt().size())),
              MuseTile(title: '已下载', trailing: value(stats.downlinkTotal.toInt().size())),
              MuseTile(title: '合计', trailing: value((stats.uplinkTotal.toInt() + stats.downlinkTotal.toInt()).size())),
            ],
          ),
          MuseSection(
            header: '连接',
            children: [
              MuseTile(
                title: '当前节点',
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    activeProxy == null
                        ? '--'
                        : museCurrentOutboundLabel(
                            activeProxy.tagDisplay.isNotEmpty ? activeProxy.tagDisplay : activeProxy.tag,
                          ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
              MuseTile(
                title: '出口 IP',
                trailing: value(
                  activeProxy != null && activeProxy.ipinfo.ip.isNotEmpty
                      ? '${activeProxy.ipinfo.ip}${activeProxy.ipinfo.countryCode.isNotEmpty ? '  ${activeProxy.ipinfo.countryCode}' : ''}'
                      : '--',
                ),
              ),
              MuseTile(title: '活动连接', trailing: value(running ? '${stats.connectionsOut}' : '--')),
              MuseTile(title: '内核内存', trailing: value(running ? stats.memory.toInt().size() : '--')),
            ],
          ),
        ],
      ),
    );
  }
}
