// 穿云 - 规则集：一键导入常用 sing-box 规则集（SagerNet sing-geosite / sing-geoip，经 jsDelivr 加速）。
// Part of 穿云 (Chuanyun), a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _site = 'https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set';
const _ip = 'https://cdn.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set';

class _Preset {
  const _Preset(this.name, this.desc, this.icon, this.outbound, this.ruleSets);

  final String name;
  final String desc;
  final IconData icon;
  final Outbound outbound;
  final List<String> ruleSets;

  /// Saved rule name; lets the page tell which presets are already in the list.
  String get key => '规则集:$name';
}

final _presets = <_Preset>[
  _Preset('国外常用网站走代理', 'geolocation-!cn：谷歌、推特、GitHub 等境外站点', Icons.public_rounded, Outbound.proxy, [
    '$_site/geosite-geolocation-%21cn.srs',
  ]),
  _Preset('AI 服务走代理', 'OpenAI / ChatGPT', Icons.auto_awesome_rounded, Outbound.proxy, ['$_site/geosite-openai.srs']),
  _Preset('谷歌 / YouTube 走代理', 'Google、YouTube', Icons.play_circle_outline_rounded, Outbound.proxy, [
    '$_site/geosite-google.srs',
    '$_site/geosite-youtube.srs',
  ]),
  _Preset('Telegram / 推特 / 脸书走代理', 'Telegram、X(Twitter)、Facebook', Icons.forum_outlined, Outbound.proxy, [
    '$_site/geosite-telegram.srs',
    '$_site/geosite-twitter.srs',
    '$_site/geosite-facebook.srs',
  ]),
  _Preset('Netflix 走代理', '流媒体', Icons.movie_outlined, Outbound.proxy, ['$_site/geosite-netflix.srs']),
  _Preset('国内网站直连', 'geosite:cn + geoip:cn', Icons.home_outlined, Outbound.direct, [
    '$_site/geosite-cn.srs',
    '$_ip/geoip-cn.srs',
  ]),
  _Preset('苹果 / 微软国内服务直连', 'Apple、Microsoft 中国区 CDN', Icons.apple_rounded, Outbound.direct, [
    '$_site/geosite-apple@cn.srs',
    '$_site/geosite-microsoft@cn.srs',
  ]),
  _Preset('国内游戏直连', '国内游戏下载与联机', Icons.sports_esports_outlined, Outbound.direct, [
    '$_site/geosite-category-games@cn.srs',
  ]),
  _Preset('拦截广告', 'category-ads-all', Icons.block_rounded, Outbound.block, ['$_site/geosite-category-ads-all.srs']),
];

String _outboundLabel(Outbound o) => switch (o) {
  Outbound.proxy => '代理',
  Outbound.block => '拦截',
  _ => '直连',
};

class RuleSetsPage extends HookConsumerWidget {
  const RuleSetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesNotifierProvider);
    final added = {for (final r in rules) r.name: r};

    Future<void> toggle(_Preset p) async {
      final notifier = ref.read(rulesNotifierProvider.notifier);
      final existing = added[p.key];
      if (existing != null) {
        await notifier.deleteRule(existing.listOrder);
        ref.read(inAppNotificationControllerProvider).showInfoToast('已移除：${p.name}');
      } else {
        await notifier.addRule(Rule(name: p.key, outbound: p.outbound, ruleSets: p.ruleSets));
        ref.read(inAppNotificationControllerProvider).showSuccessToast('已添加：${p.name}，重新连接后生效');
      }
    }

    return MuseScaffold(
      title: '规则集',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '一键导入',
            footer: '规则集来自 SagerNet sing-geosite / sing-geoip（jsDelivr 加速），内核首次使用时自动下载并定期更新。'
                '只在「配置」路由模式下生效；新添加的规则排在最前面，可在「路由规则」里调整顺序。',
            children: [
              for (final p in _presets)
                MuseSwitchTile(
                  leading: Icon(p.icon),
                  title: '${p.name}（${_outboundLabel(p.outbound)}）',
                  subtitle: p.desc,
                  value: added.containsKey(p.key),
                  onChanged: (_) => toggle(p),
                ),
            ],
          ),
          MuseSection(
            children: [
              MuseTile(
                leading: const Icon(Icons.route_rounded),
                title: '管理路由规则',
                subtitle: '查看、排序或自定义规则',
                chevron: true,
                onTap: () => context.goNamed('routingOptions'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
