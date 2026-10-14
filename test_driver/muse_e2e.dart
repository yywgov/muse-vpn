// 穿云 1.2.1 - emulator end-to-end target (debug build only, never shipped).
// Runs the real app (prod environment, real core, real VPN service) with a Flutter Driver
// extension whose commands let test_driver/muse_e2e_test.dart switch theme, open pages, add a
// test profile, connect, read the speed stats and time a node test. The host side takes real
// device screenshots (status bar included) with adb.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:hiddify/bootstrap.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

ProviderContainer? _container;

ProviderContainer _c() {
  if (_container != null) return _container!;
  ProviderContainer? found;
  void visit(Element e) {
    if (found != null) return;
    if (e.widget is UncontrolledProviderScope) {
      found = (e.widget as UncontrolledProviderScope).container;
      return;
    }
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  if (found == null) throw StateError('app not up yet');
  return _container = found!; // ignore: unnecessary_null_checks
}

BuildContext? _navigatorContext() {
  BuildContext? ctx;
  void visit(Element e) {
    if (e.widget is Scaffold) ctx = e; // the last (deepest, top-most) scaffold wins
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return ctx;
}

Future<String> _handler(String? message) async {
  final msg = message ?? '';
  final i = msg.indexOf(':');
  final cmd = i < 0 ? msg : msg.substring(0, i);
  final arg = i < 0 ? '' : msg.substring(i + 1);
  try {
    switch (cmd) {
      case 'ready':
        _c();
        return 'ok';
      case 'theme':
        await _c().read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.values.byName(arg));
        return 'ok';
      case 'go':
        _c().read(goRouterNotiferProvider).goNamed(arg);
        return 'ok';
      case 'back':
        final ctx = _navigatorContext();
        if (ctx != null) Navigator.of(ctx).maybePop();
        return 'ok';
      case 'prefs':
        await _c().read(Preferences.keepAliveGuideShown.notifier).update(true);
        return 'ok';
      case 'addProfile':
        await _c().read(addProfileNotifierProvider.notifier).addClipboard(arg);
        final p = await _c().read(activeProfileProvider.future);
        return p == null ? 'no-active-profile' : 'ok:${p.name}';
      case 'connect':
      case 'disconnect':
        final running = _c().read(serviceRunningProvider);
        if ((cmd == 'connect') != running) await _c().read(connectionNotifierProvider.notifier).toggleConnection();
        return 'ok';
      case 'status':
        final s = _c().read(connectionNotifierProvider);
        return jsonEncode({'status': '${s.valueOrNull}', 'running': _c().read(serviceRunningProvider), 'error': '${s.error ?? ''}'});
      case 'stats':
        final st = _c().read(statsNotifierProvider).valueOrNull;
        return jsonEncode({
          'up': st?.uplink.toInt() ?? -1,
          'down': st?.downlink.toInt() ?? -1,
          'upTotal': st?.uplinkTotal.toInt() ?? -1,
          'downTotal': st?.downlinkTotal.toInt() ?? -1,
          'current': st?.currentOutbound ?? '',
        });
      case 'nodes':
        final g = _c().read(proxiesOverviewNotifierProvider).valueOrNull;
        return jsonEncode({
          'tag': g?.tag,
          'selected': g?.selected,
          'items': [
            for (final OutboundInfo e in g?.items ?? <OutboundInfo>[])
              {
                'tag': e.tag,
                'type': e.type,
                'group': e.isGroup,
                'delay': e.urlTestDelay,
                'testedAt': e.hasUrlTestTime() ? e.urlTestTime.toDateTime().millisecondsSinceEpoch : 0,
              },
          ],
        });
      case 'urltest':
        // full manual test of the main group; returns how long until every node reported anew
        final g = _c().read(proxiesOverviewNotifierProvider).valueOrNull;
        if (g == null) return 'no-group';
        final start = DateTime.now();
        await _c().read(proxiesOverviewNotifierProvider.notifier).urlTest(g.tag);
        final deadline = start.add(const Duration(seconds: 90));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          final now = _c().read(proxiesOverviewNotifierProvider).valueOrNull;
          final nodes = (now?.items ?? <OutboundInfo>[]).where((e) => !e.isGroup).toList();
          if (nodes.isNotEmpty &&
              nodes.every((e) => e.hasUrlTestTime() && !e.urlTestTime.toDateTime().isBefore(start.subtract(const Duration(milliseconds: 500))))) {
            return jsonEncode({'ms': DateTime.now().difference(start).inMilliseconds, 'nodes': nodes.length});
          }
        }
        return jsonEncode({'ms': -1});
      case 'sheet':
        unawaited(_c().read(bottomSheetsNotifierProvider.notifier).showAddProfile());
        return 'ok';
      case 'dialog':
        final ctx = _navigatorContext();
        if (ctx == null) return 'no-context';
        unawaited(
          showDialog<void>(
            context: ctx,
            builder: (context) => AlertDialog(
              title: const Text('对话框'),
              content: const Text('状态栏图标检查'),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('好'))],
            ),
          ),
        );
        return 'ok';
    }
    return 'unknown:$cmd';
  } catch (e, st) {
    return 'error:$e\n$st';
  }
}

Future<void> main() async {
  enableFlutterDriverExtension(handler: _handler, enableTextEntryEmulation: false);
  final binding = WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );
  await lazyBootstrap(binding, Environment.prod);
}
