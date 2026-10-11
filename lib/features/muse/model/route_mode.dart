// Muse VPN - global routing mode (Shadowrocket "配置 / 代理 / 直连").
// Part of Muse VPN, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// The app has no native global/direct switch, so the mode is applied on top of the user's
/// route rules (see [applyTo]) right before they are handed to the core:
/// - [rule]: the route rules as configured (bypass LAN / region rules, user rules) - default.
/// - [global]: every rule that sends traffic direct is dropped, except "bypass LAN", so all
///   internet traffic goes through the selected node. Block rules are kept.
/// - [direct]: a catch-all direct rule is put first, so nothing goes through the node.
enum MuseRouteMode {
  rule('rule'),
  global('global'),
  direct('direct');

  const MuseRouteMode(this.key);

  final String key;

  static MuseRouteMode fromKey(String key) =>
      MuseRouteMode.values.firstWhere((e) => e.key == key, orElse: () => MuseRouteMode.rule);

  String get title => switch (this) {
    rule => '配置',
    global => '代理',
    direct => '直连',
  };

  String get explain => switch (this) {
    rule => '按规则分流：国内/局域网直连，其余走节点（推荐）',
    global => '全局代理：除局域网外所有流量都走节点',
    direct => '全部直连：不走节点，相当于临时关掉代理',
  };

  static const _bypassLanName = 'builtin:bypassLan';
  static const _allDirectName = 'muse:all-direct';

  List<Rule> applyTo(List<Rule> rules) => switch (this) {
    rule => rules,
    global => [
      for (final r in rules)
        if (r.name == _bypassLanName || (r.outbound != Outbound.direct && r.outbound != Outbound.direct_with_fragment))
          r,
    ],
    direct => [
      Rule(
        listOrder: 0,
        enabled: true,
        name: _allDirectName,
        outbound: Outbound.direct,
        ipCidrs: ['0.0.0.0/0', '::/0'],
        domainRegexes: ['.*'],
      ),
      // copies, so the user's own rule objects keep their order numbers
      for (var i = 0; i < rules.length; i++) Rule.fromBuffer(rules[i].writeToBuffer())..listOrder = i + 1,
    ],
  };
}
