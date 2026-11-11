// 穿云 1.20.3 - 分应用代理让哪些应用根本不进穿云（Android）。被排除的应用写进「指定节点」或「我的规则」里的
// 包名规则永远不生效，界面据此给出提示。只读分应用代理已有的列表（drift 表的 watch），不轮询。
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/app_based_routing/data/selected_data_provider.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/muse/logic/per_app_tools.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 分应用代理的现状：[mode] null = 没开；[active] 列表里选中的包名。
typedef MusePerAppState = ({AppProxyMode? mode, Set<String> active});

/// Android 才有分应用代理；其他平台、没开、读不到时 mode 为 null。测试可覆盖。
final musePerAppStateProvider = StreamProvider<MusePerAppState>((ref) {
  final mode = ref.watch(Preferences.perAppProxyModeInUse);
  if (!PlatformUtils.isAndroid || mode == null) return Stream.value((mode: null, active: const <String>{}));
  return ref
      .watch(appProxyDataSourceProvider)
      .watchAll(mode: mode)
      .map((rows) => (mode: mode, active: {for (final r in rows) if (museAppActive(r.flags)) r.pkgName}));
});

/// [pkg] 是否被分应用代理挡在穿云外面（不走代理 = 不进穿云）。
bool museAppBypassed(String pkg, MusePerAppState s) => switch (s.mode) {
  null => false,
  AppProxyMode.exclude => s.active.contains(pkg),
  AppProxyMode.include => !s.active.contains(pkg),
};

/// [packages] 里被挡住的那些。
List<String> museBypassedPackages(Iterable<String> packages, MusePerAppState s) => [for (final p in packages) if (museAppBypassed(p, s)) p];

/// 规则下面那行提示；没有被挡住的应用时 null。
String? museBypassedNote(List<String> bypassed) =>
    bypassed.isEmpty ? null : '${bypassed.join('、')} 已在分应用代理中设为不走代理，这条规则对它不生效';
