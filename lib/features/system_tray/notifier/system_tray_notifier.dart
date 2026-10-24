import 'dart:io';

import 'package:hiddify/features/muse/logic/home_tiles.dart' as tiles;
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/logger_setup.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/muse/home/node_memory.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Notifier, NotifierProvider;
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'system_tray_notifier.g.dart';

@Riverpod(keepAlive: true)
class SystemTrayNotifier extends _$SystemTrayNotifier with TrayListener, AppLogger {
  bool listenerAdded = false;
  String? _lastMenuLine;
  String? _lastIcon;
  String? _lastMenuKey;
  @override
  Future<void> build() async {
    assert(PlatformUtils.isDesktop);
    if (!listenerAdded) {
      trayManager.addListener(this);
      listenerAdded = true;
    }
    await _initializeTray();
  }

  Future<void> _initializeTray() async {
    final t = await ref.watch(translationsProvider.future);
    // 穿云 1.2.8: the icon follows the real connection status; the delay only goes into the tooltip.
    // Both are watched without waiting, so a missing delay (no 测速 yet) never holds the tray back
    // and every status / delay change rebuilds it.
    final connection = await ref.watch(connectionNotifierProvider.future).catchError((e) {
      loggy.warning("error getting connection status", e);
      return const ConnectionStatus.disconnected();
    });
    final urlTestDelay = ref.watch(activeProxyNotifierProvider).valueOrNull?.urlTestDelay ?? 0;
    final speed = ref.watch(museTraySpeedProvider);

    // 1.5.0 #144: orange while connected but the internet can't be reached through the node
    final reach = ref.watch(museReachProvider);
    final icon = museTrayWarning(connection, reach)
        ? (PlatformUtils.isWindows ? museTrayWarningIco : museTrayWarningPng)
        : _trayIconPath(museTrayIconStatus(connection));
    if (icon != _lastIcon) {
      _lastIcon = icon;
      await trayManager.setIcon(icon, isTemplate: PlatformUtils.isMacOS);
    }
    if (Platform.isMacOS) {
      windowManager.setBadgeLabel(connection is Connected && ConnectionConst.isValidDelay(urlTestDelay) ? "${urlTestDelay}ms" : "-ms");
    }
    if (!PlatformUtils.isLinux) {
      await trayManager.setToolTip(museTrayTooltip(connection, urlTestDelay, connection.present(t), speed: speed));
    }
    // 穿云 1.2.3: 节点 submenu (switch node, see delays, 测速) while connected
    final running = ref.watch(serviceRunningProvider);
    final group = running ? ref.watch(proxiesOverviewNotifierProvider).valueOrNull : null;
    _groupTag = group?.tag;
    final nodes = group == null
        ? const <MuseTrayNode>[]
        : museTrayNodes(
            [
              for (final e in group.items)
                if (!e.isGroup) (tag: e.tag, name: e.tagDisplay.isNotEmpty ? e.tagDisplay : e.tag, delay: e.urlTestDelay),
            ],
            selected: group.selected,
          );
    final spec = museTrayMenuSpec(connection, ref.watch(ConfigOptions.museRouteMode), nodes: nodes, speed: speed);
    final menuKey = _specKey(spec);
    if (menuKey != _lastMenuKey) {
      _lastMenuKey = menuKey;
      await trayManager.setContextMenu(_trayMenu(spec));
    }
  }

  String? _groupTag;

  // 穿云: 显示 / 连接|断开 / 退出 — nothing else
  String _specKey(List<MuseTrayItem> spec) =>
      spec.map((e) => '${e.key}=${e.label}${e.checked}${e.disabled}[${_specKey(e.children)}]').join(';');

  Menu _trayMenu(List<MuseTrayItem> spec) {
    // 穿云 1.2: one line in app.log, checked by the Windows smoke test
    // (app.log keeps errors only, so the line goes in as a marker, once per distinct menu;
    // the 网速 line changes every few seconds and is left out of it)
    final line =
        "tray menu: ${spec.where((e) => e.key != 'speed').map((e) => e.key == '-' ? '|' : '${e.label}${e.checked ? '*' : ''}').join(' ')}";
    loggy.info(line);
    if (line != _lastMenuLine) {
      _lastMenuLine = line;
      logMarkLine(line);
    }
    return _menuOf(spec);
  }

  Menu _menuOf(List<MuseTrayItem> spec) => Menu(
    items: [
      for (final e in spec)
        if (e.key == '-')
          MenuItem.separator()
        else if (e.children.isNotEmpty)
          MenuItem.submenu(key: e.key, label: e.label, disabled: e.disabled, submenu: _menuOf(e.children))
        else if (e.checkable)
          MenuItem.checkbox(key: e.key, label: e.label, checked: e.checked, disabled: e.disabled)
        else
          MenuItem(key: e.key, label: e.label, disabled: e.disabled),
    ],
  );

  String _trayIconPath(ConnectionStatus status) {
    final isDarkMode = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    const images = Assets.images;
    final isWindows = PlatformUtils.isWindows;
    switch (status) {
      case Connected():
        return isWindows ? images.trayIconConnectedIco : images.trayIconConnectedPng.path;
      case Connecting():
      case Disconnecting():
        return isWindows ? images.trayIconDisconnectedIco : images.trayIconDisconnectedPng.path;
      case Disconnected():
        return isWindows
            ? isDarkMode
                  ? images.trayIconIco
                  : images.trayIconDarkIco
            : isDarkMode
            ? images.trayIconDarkPng.path
            : images.trayIconPng.path;
    }
  }

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    // if (menuItem.key == 'dashboard') {
    //   await ref.read(windowNotifierProvider.notifier).open();
    // }
    if (menuItem.key == 'dashboard') {
      await ref.read(windowNotifierProvider.notifier).show();
    } else if (menuItem.key == 'connection') {
      await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    } else if (menuItem.key?.startsWith('mode:') ?? false) {
      await ref.read(ConfigOptions.museRouteMode.notifier).update(MuseRouteMode.fromKey(menuItem.key!.substring(5)));
    } else if (menuItem.key?.startsWith('node:') ?? false) {
      final group = _groupTag;
      if (group == null) return;
      try {
        await museSelectNodeFrom(ref, group, menuItem.key!.substring(5));
      } catch (e) {
        loggy.warning('tray: switching node failed', e);
      }
    } else if (menuItem.key == 'urltest') {
      final group = _groupTag;
      if (group == null) return;
      try {
        await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group);
      } catch (e) {
        loggy.warning('tray: url test failed', e);
      }
    } else if (menuItem.key == 'quit') {
      await ref.read(windowNotifierProvider.notifier).exit();
    }
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    // if (Platform.isMacOS) {
    //   await trayManager.popUpContextMenu();
    // } else {
    //   await ref.read(windowNotifierProvider.notifier).hideOrShow();
    // }
    // 穿云: a left click on the tray icon always brings the window up (Windows convention)
    await ref.read(windowNotifierProvider.notifier).show();
  }

  @override
  Future<void> onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }
}

// @Riverpod(keepAlive: true)
// class SystemTrayNotifier extends _$SystemTrayNotifier with AppLogger {
//   @override
//   Future<void> build() async {
//     if (!PlatformUtils.isDesktop) return;

//     final activeProxy = await ref.watch(activeProxyNotifierProvider.future);
//     final delay = activeProxy.urlTestDelay;
//     final newConnectionStatus = delay > 0 && delay < 65000;
//     ConnectionStatus connection;
//     try {
//       connection = await ref.watch(connectionNotifierProvider.future);
//     } catch (e) {
//       loggy.warning("error getting connection status", e);
//       connection = const ConnectionStatus.disconnected();
//     }

//     final t = await ref.watch(translationsProvider.future);

//     var tooltip = Constants.appName;
//     final serviceMode = ref.watch(ConfigOptions.serviceMode);
//     if (connection is Disconnected) {
//       setIcon(connection);
//     } else if (newConnectionStatus) {
//       setIcon(const Connected());
//       tooltip = "$tooltip - ${connection.present(t)}";
//       if (newConnectionStatus) {
//         tooltip = "$tooltip : ${delay}ms";
//       } else {
//         tooltip = "$tooltip : -";
//       }
//       // else if (delay>1000)
//       //   SystemTrayNotifier.setIcon(timeout ? Disconnecting() : Connecting());
//     } else {
//       setIcon(const Disconnecting());
//       tooltip = "$tooltip - ${connection.present(t)}";
//     }
//     if (Platform.isMacOS) {
//       windowManager.setBadgeLabel("${delay}ms");
//     }
//     if (!Platform.isLinux) await trayManager.setToolTip(tooltip);

//     // final destinations = <(String label, String location)>[
//     //   (t.home.pageTitle, const HomeRoute().location),
//     //   (t.proxies.pageTitle, const ProfilesOverviewRoute().location),
//     //   (t.logs.title, const LogsOverviewRoute().location),
//     //   // (t.settings.pageTitle, const SettingsRoute().location),
//     //   (t.about.pageTitle, const AboutRoute().location),
//     // ];

//     // loggy.debug('updating system tray');

//     final menu = Menu(
//       items: [
//         MenuItem(
//           label: t.tray.dashboard,
//           onClick: (_) async {
//             await ref.read(windowNotifierProvider.notifier).open();
//           },
//         ),
//         MenuItem.separator(),
//         MenuItem.checkbox(
//           label: switch (connection) {
//             Disconnected() => t.tray.status.connect,
//             Connecting() => t.tray.status.connecting,
//             Connected() => t.tray.status.disconnect,
//             Disconnecting() => t.tray.status.disconnecting,
//           },
//           // checked: connection.isConnected,
//           checked: false,
//           disabled: connection.isSwitching,
//           onClick: (_) async {
//            await ref.read(connectionNotifierProvider.notifier).toggleConnection();
//          },
//        ),
//         MenuItem.separator(),
//         MenuItem(
//           label: t.config.serviceMode,
//           icon: Assets.images.trayIconIco,
//           disabled: true,
//         ),

//         ...ServiceMode.values.map(
//           (e) => MenuItem.checkbox(
//             checked: e == serviceMode,
//             key: e.name,
//             label: e.present(t),
//             onClick: (menuItem) async {
//               final newMode = ServiceMode.values.byName(menuItem.key!);
//               loggy.debug("switching service mode: [$newMode]");
//               await ref.read(ConfigOptions.serviceMode.notifier).update(newMode);
//             },
//           ),
//         ),

//         // MenuItem.submenu(
//         //   label: t.tray.open,
//         //   submenu: Menu(
//         //     items: [
//         //       ...destinations.map(
//         //         (e) => MenuItem(
//         //           label: e.$1,
//         //           onClick: (_) async {
//         //             await ref.read(windowNotifierProvider.notifier).open();
//         //             ref.read(routerProvider).go(e.$2);
//         //           },
//         //         ),
//         //       ),
//         //     ],
//         //   ),
//         // ),
//         MenuItem.separator(),
//         MenuItem(
//           label: t.tray.quit,
//           onClick: (_) async {
//             return ref.read(windowNotifierProvider.notifier).quit();
//           },
//         ),
//       ],
//     );

//     await trayManager.setContextMenu(menu);
//   }

//   static void setIcon(ConnectionStatus status) {
//     if (!PlatformUtils.isDesktop) return;
//     trayManager
//         .setIcon(
//           _trayIconPath(status),
//           isTemplate: Platform.isMacOS,
//         )
//         .asStream();
//   }

//   static String _trayIconPath(ConnectionStatus status) {
//     if (Platform.isWindows) {
//       final Brightness brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
//       final isDarkMode = brightness == Brightness.dark;
//       switch (status) {
//         case Connected():
//           return Assets.images.trayIconConnectedIco;
//         case Connecting():
//           return Assets.images.trayIconDisconnectedIco;
//         case Disconnecting():
//           return Assets.images.trayIconDisconnectedIco;
//         case Disconnected():
//           if (isDarkMode) {
//             return Assets.images.trayIconIco;
//           } else {
//             return Assets.images.trayIconDarkIco;
//           }
//       }
//     }
//     // const isDarkMode = false;
//     switch (status) {
//       case Connected():
//         return Assets.images.trayIconConnectedPng.path;
//       case Connecting():
//         return Assets.images.trayIconDisconnectedPng.path;
//       case Disconnecting():
//         return Assets.images.trayIconDisconnectedPng.path;
//       case Disconnected():
//         // if (isDarkMode) {
//         //   return Assets.images.trayIconDarkPng.path;
//         // } else {
//         //   return Assets.images.trayIconPng.path;
//         // }
//         return Assets.images.trayIconPng.path;
//     }
//     // return Assets.images.trayIconPng.path;
//   }
// }

/// One entry of the tray menu ('-' = separator).
class MuseTrayItem {
  const MuseTrayItem(
    this.key,
    this.label, {
    this.checkable = false,
    this.checked = false,
    this.disabled = false,
    this.children = const [],
  });

  /// a submenu when not empty
  final List<MuseTrayItem> children;

  final String key;
  final String label;
  final bool checkable;
  final bool checked;
  final bool disabled;
}

/// One node in the tray's 节点 submenu.
class MuseTrayNode {
  const MuseTrayNode(this.tag, this.label, {this.selected = false});

  final String tag;
  final String label;
  final bool selected;
}

/// The tray lists at most this many nodes (fastest first); the window has the full list.
const museTrayMaxNodes = 25;

/// Nodes for the tray: fastest first (untested and timed-out last), the selected one always
/// included, each labelled `name   123 ms` / `超时`.
List<MuseTrayNode> museTrayNodes(List<({String tag, String name, int delay})> items, {required String selected}) {
  final sorted = museSortNodes<({String tag, String name, int delay})>(
    items,
    isGroup: (_) => false,
    delay: (e) => e.delay,
    isValidDelay: ConnectionConst.isValidDelay,
  );
  final picked = sorted.take(museTrayMaxNodes).toList();
  if (!picked.any((e) => e.tag == selected)) {
    final sel = sorted.where((e) => e.tag == selected).firstOrNull;
    if (sel != null) picked.insert(0, sel);
  }
  String delayText(int d) => d == 0 ? '' : (ConnectionConst.isValidDelay(d) ? '   $d ms' : '   超时');
  return [for (final e in picked) MuseTrayNode(e.tag, '${e.name}${delayText(e.delay)}', selected: e.tag == selected)];
}

/// 穿云 tray right-click menu: 连接/断开 · 规则/全局 · 节点 ▸ (1.2.3, while connected) · 显示窗口 · 退出.
List<MuseTrayItem> museTrayMenuSpec(
  ConnectionStatus connection,
  MuseRouteMode mode, {
  List<MuseTrayNode> nodes = const [],
  String? speed,
}) => [
  // 穿云 1.2.8: current speed (read-only line) while connected
  if (connection is Connected && speed != null && speed.isNotEmpty) MuseTrayItem('speed', speed, disabled: true),
  MuseTrayItem(
    'connection',
    switch (connection) {
      Disconnected() => '连接',
      Connecting() => '连接中…',
      Connected() => '断开',
      Disconnecting() => '断开中…',
    },
    disabled: connection.isSwitching,
  ),
  const MuseTrayItem('-', ''),
  for (final m in MuseRouteMode.values) MuseTrayItem('mode:${m.key}', m.title, checkable: true, checked: m == mode),
  const MuseTrayItem('-', ''),
  if (connection is Connected && nodes.isNotEmpty)
    MuseTrayItem(
      'nodes',
      '节点',
      children: [
        for (final n in nodes) MuseTrayItem('node:${n.tag}', n.label, checkable: true, checked: n.selected),
        const MuseTrayItem('-', ''),
        const MuseTrayItem('urltest', '测速'),
      ],
    ),
  const MuseTrayItem('dashboard', '显示窗口'),
  const MuseTrayItem('quit', '退出'),
];

/// 1.5.0 #144: the tray has three looks: grey (off / switching), blue (connected), orange
/// (connected, but the post-connect check found no internet through the node).
const museTrayWarningIco = 'assets/images/tray_icon_warning.ico';
const museTrayWarningPng = 'assets/images/tray_icon_warning.png';

bool museTrayWarning(ConnectionStatus connection, MuseReach reach) => connection is Connected && reach == MuseReach.failed;

/// 穿云 1.2.8: the tray icon is blue as soon as the tunnel is really up (no delay needed).
ConnectionStatus museTrayIconStatus(ConnectionStatus connection) => connection;

/// Tray tooltip: `穿云 - 已连接 · 123ms · ↓1.2 MB/s ↑30 KB/s`; delay / speed only when known.
String museTrayTooltip(ConnectionStatus connection, int urlTestDelay, String statusText, {String? speed}) {
  final parts = ["${Constants.appName} - $statusText"];
  if (connection is Connected) {
    if (ConnectionConst.isValidDelay(urlTestDelay)) parts.add('${urlTestDelay}ms');
    if (speed != null && speed.isNotEmpty) parts.add(speed);
  }
  return parts.join(' · ');
}

/// `↓1.2 MB/s ↑30 KB/s` for the tray (1.4.0: KB/s at least).
String museSpeedText(int uplink, int downlink) => '↓${tiles.museSpeedText(downlink)} ↑${tiles.museSpeedText(uplink)}';

/// 穿云 1.2.8: the current speed for the tray, at most one change every 3 s (so the tray isn't
/// rebuilt every second); null while disconnected.
final museTraySpeedProvider = NotifierProvider<MuseTraySpeed, String?>(MuseTraySpeed.new);

class MuseTraySpeed extends Notifier<String?> {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String? build() {
    if (!ref.watch(serviceRunningProvider)) return null;
    ref.listen(statsNotifierProvider, (_, next) {
      final v = next.valueOrNull;
      if (v == null) return;
      final now = DateTime.now();
      if (now.difference(_last) < const Duration(seconds: 3)) return;
      _last = now;
      final text = museSpeedText(v.uplink.toInt(), v.downlink.toInt());
      if (text != state) state = text;
    });
    return null;
  }
}
