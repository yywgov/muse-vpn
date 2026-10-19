// 穿云 - global routing mode: 规则 / 全局.
// 1.2.2: 直连 is gone (it was 断开 with extra steps: traffic still went through the core) and the
// labels no longer clash with the 配置 tab (配置/代理 -> 规则/全局). A saved 直连 starts as 规则.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// The app has no native global/direct switch, so the mode is applied on top of the user's
/// route rules (see [applyTo]) right before they are handed to the core:
/// - [rule]: the route rules as configured (bypass LAN / region rules, user rules) - default.
/// - [global]: every rule that sends traffic direct is dropped, except "bypass LAN", so all
///   internet traffic goes through the selected node. Block rules are kept.
enum MuseRouteMode {
  rule('rule'),
  global('global');

  const MuseRouteMode(this.key);

  final String key;

  static MuseRouteMode fromKey(String key) =>
      MuseRouteMode.values.firstWhere((e) => e.key == key, orElse: () => MuseRouteMode.rule);

  String get title => switch (this) {
    rule => '规则',
    global => '全局',
  };

  String get explain => switch (this) {
    rule => '按规则分流：国内/局域网直连，其余走节点（推荐）',
    global => '全局代理：除局域网外所有流量都走节点',
  };

  static const _bypassLanName = 'builtin:bypassLan';

  List<Rule> applyTo(List<Rule> rules) => switch (this) {
    rule => rules,
    global => [
      for (final r in rules)
        if (r.name == _bypassLanName || (r.outbound != Outbound.direct && r.outbound != Outbound.direct_with_fragment))
          r,
    ],
  };
}
