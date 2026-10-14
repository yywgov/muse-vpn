// 穿云 Windows - control port for the CI smoke tests (tool/smoke/recovery_smoke.ps1).
//
// Off unless the process was started with CHUANYUN_SMOKE_CONTROL=<port> (only the CI runner sets
// it). Listens on 127.0.0.1 only and every request must carry ?token=<CHUANYUN_SMOKE_TOKEN>.
//   /state                      UI status, core state, startedByUser, system proxy ours
//   /import?path=<json file>    adds the file as a profile and makes it active (if none yet)
//   /connect  /disconnect       the same as the 连接 button
//   /break-status               the status stream breaks while the core keeps running
//   /core-stop                  the core stops without the app asking for it
//   /resume                     the window-restore / wake path
//   /crash                      exit(2), like a Go fatal error in the core
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/desktop/connection_keeper.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

abstract final class MuseSmokeControl {
  static final _logger = infraLogger('SmokeControl');

  static Future<void> startIfRequested(ProviderContainer container) async {
    final port = int.tryParse(Platform.environment['CHUANYUN_SMOKE_CONTROL'] ?? '');
    final token = Platform.environment['CHUANYUN_SMOKE_TOKEN'] ?? '';
    if (port == null || token.length < 8) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _logger.warning('smoke control listening on 127.0.0.1:$port');
    server.listen((req) async {
      final res = req.response;
      try {
        if (req.uri.queryParameters['token'] != token) {
          res.statusCode = HttpStatus.forbidden;
          return;
        }
        final body = await _handle(container, req.uri);
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(body));
      } catch (e) {
        res.statusCode = HttpStatus.internalServerError;
        res.write(jsonEncode({'error': '$e'}));
      } finally {
        await res.close();
      }
    });
  }

  static Future<Map<String, Object?>> _handle(ProviderContainer c, Uri uri) async {
    final service = c.read(hiddifyCoreServiceProvider);
    final notifier = c.read(connectionNotifierProvider.notifier);
    switch (uri.path) {
      case '/state':
        final ui = c.read(connectionNotifierProvider).valueOrNull;
        final core = await service.queryCoreState();
        return {
          'ui': museConnectionName(ui),
          'uiConnected': ui is Connected,
          'core': museCoreName(core),
          'startedByUser': c.read(Preferences.startedByUser),
          'proxyOurs': await WindowsProxyGuard.pointsAtUsNow(),
          'recoveries': c.read(museConnectionKeeperProvider)?.failedAttempts,
        };
      case '/import':
        final path = uri.queryParameters['path'] ?? '';
        final repo = await c.read(profileRepositoryProvider.future);
        final content = await File(path).readAsString();
        final added = await repo.addLocal(content).run();
        final err = added.getLeft().toNullable();
        if (err != null) return {'ok': false, 'error': '$err'};
        // the first profile becomes active; make sure
        final all = await repo.watchAll().first;
        final list = all.getOrElse((_) => []);
        if (list.isNotEmpty && !list.any((p) => p.active)) await repo.setAsActive(list.first.id).run();
        return {'ok': true, 'profiles': list.length};
      case '/connect':
        if (c.read(connectionNotifierProvider).valueOrNull is! Connected) await notifier.toggleConnection();
        return {'ok': true};
      case '/disconnect':
        if (c.read(connectionNotifierProvider).valueOrNull is Connected) await notifier.toggleConnection();
        return {'ok': true};
      case '/break-status':
        await service.debugBreakStatusStream();
        return {'ok': true};
      case '/core-stop':
        await service.debugStopCoreBehindTheApp();
        return {'ok': true};
      case '/resume':
        await service.resume();
        c.read(museConnectionKeeperProvider)?.poke('resume');
        return {'ok': true};
      case '/crash':
        _logger.warning('smoke: simulated crash exit(2)');
        Timer(const Duration(milliseconds: 200), () => exit(2));
        return {'ok': true};
      default:
        return {'error': 'unknown ${uri.path}'};
    }
  }
}
