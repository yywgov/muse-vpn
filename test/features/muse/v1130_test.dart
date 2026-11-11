// 穿云 1.13.0 稳定性: 本地崩溃自检、连不上一键诊断、安全模式、被其他 VPN 顶掉、e2e 启动路径.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/data/muse_health.dart';
import 'package:hiddify/features/muse/home/health_banner.dart';
import 'package:hiddify/features/muse/logic/connect_doctor.dart';
import 'package:hiddify/features/muse/logic/diagnosis.dart';
import 'package:hiddify/features/muse/logic/health_tools.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_mobile.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart' show museStopCallTimeout;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

String _fnBody(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: signature);
  var depth = 0;
  var i = src.indexOf('{', start);
  final open = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return src.substring(open, i + 1);
}

const _kt = 'android/app/src/main/kotlin/com/hiddify/hiddify';

class _Health extends MuseHealthNotifier {
  _Health(this.value);

  final MuseHealthState value;

  @override
  Future<MuseHealthState> build() async => value;
}

Future<void> _pumpBanner(WidgetTester t, MuseHealthState h, ConnectionStatus s) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        museHealthProvider.overrideWith(() => _Health(h)),
        museConnectionProvider.overrideWithValue(AsyncData(s)),
      ],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MuseHealthBanner()))),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  group('A1 本地崩溃自检', () {
    test('Kotlin: uncaught exceptions of every process go to a capped local log, then the old handler', () {
      final h = _src('$_kt/bg/ChuanyunHealth.kt');
      expect(h, contains('MAX_BYTES = 128 * 1024L'));
      expect(h, contains('crash.1.log'));
      expect(h, contains('filesDir, "diagnostics"'));
      final install = _fnBody(h, 'fun install(');
      expect(install, contains('setDefaultUncaughtExceptionHandler'));
      expect(install, contains('previous?.uncaughtException(thread, e)'));
      expect(_src('$_kt/Application.kt'), contains('ChuanyunHealth.install('));
      // installed before the 兼容内核 process returns early
      final app = _src('$_kt/Application.kt');
      expect(app.indexOf('ChuanyunHealth.install('), lessThan(app.indexOf('if (com.hiddify.hiddify.bg.ChuanyunProcess.isCompat) return')));
      // no upload anywhere
      expect(h, isNot(contains('URL(')));
      expect(h, isNot(contains('Socket')));
    });

    test('Kotlin: a failed service start (both cores) is written and still releases the core', () {
      final box = _fnBody(_src('$_kt/bg/BoxService.kt'), 'private suspend fun stopAndAlert(');
      expect(box, contains('ChuanyunHealth.startFailed('));
      expect(box, contains('releaseCore()'));
      final compat = _fnBody(_src('$_kt/bg/CompatService.kt'), 'private suspend fun stopAndAlert(');
      expect(compat, contains('ChuanyunHealth.startFailed('));
      expect(compat, contains('releaseCore()'));
    });

    test('Dart: uncaught errors mark 「上次异常」; the state reads both sources, newest wins', () {
      expect(_fnBody(_src('lib/features/muse/data/crash_recorder.dart'), 'static void record('), contains('MuseHealth.markAppCrash('));
      final raw = museEncodeUnseen(DateTime(2026, 11, 8, 5), '界面异常：Bad state\n第二行');
      final app = museParseUnseen(raw)!;
      expect(app.text, '界面异常：Bad state 第二行');
      expect(museParseUnseen(null), isNull);
      expect(museParseUnseen('x'), isNull);
      final s = MuseHealthState.fromMap({'crash': '启动失败：StartService', 'crashAt': DateTime(2026, 11, 8, 6).millisecondsSinceEpoch, 'safeMode': true, 'failures': 2});
      expect(s.withAppCrash(app).crash, '启动失败：StartService'); // the service's is newer
      expect(MuseHealthState.fromMap({'crash': 'x', 'crashAt': 1}).withAppCrash(app).crash, app.text);
      expect(MuseHealthState.fromMap(null).isEmpty, isTrue);
      expect(MuseHealthState.fromMap({'crash': '  '}).crash, isNull);
    });

    test('times and the copied log', () {
      final now = DateTime(2026, 11, 8, 12);
      expect(museWhen(now.subtract(const Duration(seconds: 10)), now), '刚刚');
      expect(museWhen(now.subtract(const Duration(minutes: 5)), now), '5 分钟前');
      expect(museWhen(now.subtract(const Duration(hours: 3)), now), '3 小时前');
      expect(museWhen(now.subtract(const Duration(days: 2)), now), '2 天前');
      final log = museHealthLogText(version: '1.13.0 (202)', system: 'android 15', serviceLog: '', appLog: 'a');
      expect(log, contains('（无）'));
      expect(log, contains('只保存在本机'));
      expect(log, contains('== 界面异常记录 ==\na'));
    });

    testWidgets('首页 shows 上次异常 with 复制日志 / 知道了', (t) async {
      await _pumpBanner(t, MuseHealthState(crash: '启动失败：StartService', crashAt: DateTime.now()), const ConnectionStatus.disconnected());
      expect(find.byKey(const ValueKey('home_last_crash')), findsOneWidget);
      expect(find.text('上次异常'), findsOneWidget);
      expect(find.text('复制日志'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
    });

    testWidgets('nothing to say: no banner', (t) async {
      await _pumpBanner(t, MuseHealthState.none, const ConnectionStatus.connected());
      expect(find.byType(TextButton), findsNothing);
      expect(find.text('上次异常'), findsNothing);
    });
  });

  group('B2 安全模式', () {
    test('two failures in a row; the same failure reported twice within 5 s counts once', () {
      final t0 = DateTime(2026, 11, 8, 5);
      expect(museNextFailures(0, null, t0), 1);
      expect(museNextFailures(1, t0, t0.add(const Duration(seconds: 2))), 1);
      expect(museNextFailures(1, t0, t0.add(const Duration(seconds: 6))), 2);
      expect(museEntersSafeMode(1), isFalse);
      expect(museEntersSafeMode(2), isTrue);
      final h = _src('$_kt/bg/ChuanyunHealth.kt');
      expect(h, contains('SAFE_MODE_AFTER = 2'));
      expect(h, contains('SAME_FAILURE_MS = 5_000L'));
    });

    test('a successful start ends the streak only once the core really runs', () {
      final box = _src('$_kt/bg/BoxService.kt');
      final start = box.indexOf('Mobile.start("","")');
      expect(box.indexOf('ChuanyunHealth.startSucceeded()', start), greaterThan(start));
      // not right after Mobile.setup (a background start that then fails would reset the count)
      final setupOk = box.indexOf('DisconnectLog.record("VPN 服务已启动")');
      expect(box.substring(setupOk, start), isNot(contains('startSucceeded')));
      final notifier = _src('lib/features/connection/notifier/connection_notifier.dart');
      expect(notifier, contains('MuseHealth.startOk()'));
      expect(notifier, contains("MuseHealth.startFailed('\$failure')"));
    });

    test('widget updates stop without touching a Context while a service is constructed', () {
      final w = _src('$_kt/bg/ChuanyunWidget.kt');
      for (final sig in ['fun onStatus(status: Status)', 'fun onNode(node: String, delay: Int)']) {
        final body = _fnBody(w, sig);
        final guard = body.indexOf('ChuanyunHealth.safeModeCached');
        expect(guard, greaterThan(0), reason: sig);
        expect(guard, lessThan(body.indexOf('appContext()')), reason: sig);
      }
      // the flag is a plain field, loaded in Application.onCreate (install), never read from a file here
      final h = _src('$_kt/bg/ChuanyunHealth.kt');
      expect(h, contains('var safeModeCached = false'));
      expect(_fnBody(h, 'fun install('), contains('safeModeCached = f("safe_mode").exists()'));
    });

    test('the config leaves out the user\'s own rules and 订阅覆写 in 安全模式', () {
      final c = _src('lib/features/settings/data/config_option_repository.dart');
      expect(c, contains('final safe = ref.watch(museSafeModeProvider);'));
      expect(c, contains('safe ? const <Rule>[] : ref.watch(rulesNotifierProvider)'));
      expect(c, contains('safe ? const <MuseRemoteRuleSet>[]'));
      expect(c, contains('safe ? const <MuseQuickRule>[]'));
      expect(c, contains('safe ? const <String>[] : museParseBlockedHosts'));
      expect(_src('lib/features/connection/data/connection_repository.dart'), contains('if (ref.read(museSafeModeProvider)) return null;'));
    });

    test('desktop: counted in the preferences, log capped, 退出 clears it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      MuseHealth.attach(prefs);
      await MuseHealth.startFailed('一');
      expect((await MuseHealth.load()).safeMode, isFalse);
      await prefs.setInt(MuseHealth.lastFailKey, DateTime.now().subtract(const Duration(seconds: 10)).millisecondsSinceEpoch);
      await MuseHealth.startFailed('二');
      final s = await MuseHealth.load();
      expect(s.safeMode, isTrue);
      expect(s.failures, 2);
      expect(s.crash, contains('启动失败：二'));
      expect(await MuseHealth.serviceLog(), contains('安全模式'));
      await prefs.setString(MuseHealth.startLogKey, 'x' * (MuseHealth.startLogMax + 100));
      await MuseHealth.startFailed('三');
      expect((await MuseHealth.serviceLog()).length, lessThanOrEqualTo(MuseHealth.startLogMax));
      await MuseHealth.exitSafeMode();
      expect((await MuseHealth.load()).safeMode, isFalse);
      await MuseHealth.dismissCrash();
      expect((await MuseHealth.load()).crash, isNull);
    });

    testWidgets('首页 shows 安全模式 with 退出安全模式', (t) async {
      await _pumpBanner(t, const MuseHealthState(safeMode: true, failures: 2), const ConnectionStatus.disconnected());
      expect(find.byKey(const ValueKey('home_safe_mode')), findsOneWidget);
      expect(find.text('退出安全模式'), findsOneWidget);
    });
  });

  group('B3 被其他 VPN 顶掉', () {
    test('onRevoke notifies and stops; it never starts again by itself', () {
      final box = _fnBody(_src('$_kt/bg/BoxService.kt'), 'fun onRevoke()');
      expect(box, contains('ChuanyunHealth.markRevoked()'));
      expect(box, contains('stopService()'));
      expect(box, isNot(contains('BoxService.start')));
      expect(box, isNot(contains('Mobile.start')));
      expect(box, isNot(contains('startService()')));
      // stopService clears the wish to stay connected (no watchdog / START_STICKY restart)
      expect(_fnBody(_src('$_kt/bg/BoxService.kt'), 'private fun stopService()'), contains('Settings.startedByUser = false'));
      final compat = _fnBody(_src('$_kt/bg/CompatService.kt'), 'fun onRevoke()');
      expect(compat, contains('ChuanyunHealth.markRevoked()'));
      expect(compat, contains('CompatState.markStoppedByUser()'));
      final mark = _fnBody(_src('$_kt/bg/ChuanyunHealth.kt'), 'fun markRevoked()');
      expect(mark, contains('ChuanyunAlerts.ID_REVOKED'));
      expect(mark, contains('不会自动重连'));
    });

    testWidgets('首页 says so, with 知道了 and 重新连接 (only on tap)', (t) async {
      await _pumpBanner(t, MuseHealthState(revokedAt: DateTime.now()), const ConnectionStatus.disconnected());
      expect(find.byKey(const ValueKey('home_vpn_revoked')), findsOneWidget);
      expect(find.textContaining('不会自动重连'), findsOneWidget);
      expect(find.text('重新连接'), findsOneWidget);
    });
  });

  group('B1 连不上一键诊断', () {
    const ok = MuseDoctorInput(connected: false, networkOk: true, dnsOk: true, nodeName: '日本', nodeReachable: true, mixedPort: 12334, otherVpn: false);

    test('all fine', () {
      final items = museDoctorItems(ok);
      expect(items.map((e) => e.title), ['网络', 'DNS', '节点', '端口', '其他 VPN']);
      expect(items.every((e) => e.level == MuseDiagLevel.ok), isTrue);
      expect(museDoctorConclusion(ok), contains('没有发现明显问题'));
      expect(museDoctorFixes(ok, android: true), [MuseDoctorFix.retest]);
    });

    test('a leftover background core (17079) → 释放内核', () {
      const i = MuseDoctorInput(connected: false, networkOk: true, dnsOk: true, corePortBusy: true, mixedPort: 12334, otherVpn: false);
      expect(museDoctorItems(i).firstWhere((e) => e.title == '端口').text, contains('17079'));
      expect(museDoctorConclusion(i), contains('释放内核'));
      expect(museDoctorFixes(i, android: true).first, MuseDoctorFix.releaseCore);
      expect(museDoctorFixes(i, android: false), [MuseDoctorFix.retest]);
    });

    test('another VPN → 打开 VPN 设置; offline beats everything; dead node → 切换节点', () {
      const vpn = MuseDoctorInput(connected: false, networkOk: true, dnsOk: true, otherVpn: true);
      expect(museDoctorConclusion(vpn), contains('其他 VPN'));
      expect(museDoctorFixes(vpn, android: true), contains(MuseDoctorFix.openVpnSettings));
      const off = MuseDoctorInput(connected: false, networkOk: false, dnsOk: false, otherVpn: true, corePortBusy: true);
      expect(museDoctorConclusion(off), contains('没有网络'));
      expect(museDoctorFixes(off, android: true), [MuseDoctorFix.retest]);
      const dead = MuseDoctorInput(connected: false, networkOk: true, dnsOk: true, nodeName: '香港', nodeReachable: false, otherVpn: false);
      expect(museDoctorConclusion(dead), contains('换一个节点'));
      expect(museDoctorFixes(dead, android: true), [MuseDoctorFix.switchNode, MuseDoctorFix.retest]);
      const busy = MuseDoctorInput(connected: false, networkOk: true, dnsOk: true, mixedPort: 7890, mixedPortBusy: true);
      expect(museDoctorConclusion(busy), contains('7890'));
    });

    test('UDP nodes and unknown addresses are skipped, connected skips port / VPN checks', () {
      const udp = MuseDoctorInput(connected: true, networkOk: true, dnsOk: true, nodeName: 'h2', nodeUdp: true);
      final items = museDoctorItems(udp);
      expect(items.where((e) => e.level == MuseDiagLevel.skip).map((e) => e.title), ['节点', '端口', '其他 VPN']);
      expect(museDoctorItems(const MuseDoctorInput(connected: false, networkOk: true, dnsOk: true)).firstWhere((e) => e.title == '节点').level, MuseDiagLevel.skip);
    });

    test('node address from the saved config', () {
      const raw = '{"outbounds":[{"type":"vless","tag":"日本","server":"1.2.3.4","server_port":443},'
          '{"type":"hysteria2","tag":"h2","server":"h.example","server_port":8443},{"type":"selector","tag":"选择"}]}';
      expect(museNodeEndpoint(raw, '日本'), (host: '1.2.3.4', port: 443, udp: false));
      expect(museNodeEndpoint(raw, 'h2')?.udp, isTrue);
      expect(museNodeEndpoint(raw, '选择'), isNull);
      expect(museNodeEndpoint(raw, '无'), isNull);
      expect(museNodeEndpoint('不是 JSON', '日本'), isNull);
    });

    test('runs only on tap; fixes are wired to the platform', () {
      final s = _src('lib/features/muse/settings/connect_doctor_sheet.dart');
      expect(_fnBody(s, 'class _DoctorState'), isNot(contains('initState')));
      expect(s, contains("onPressed: _running ? null : _run"));
      expect(s, contains('ChuanyunPlatform.releaseCore()'));
      expect(s, contains('ChuanyunPlatform.openVpnSettings()'));
      final h = _src('$_kt/ChuanyunHandler.kt');
      expect(h, contains('"other_vpn_active"'));
      expect(h, contains('TRANSPORT_VPN'));
      expect(h, contains('"release_core"'));
      expect(h, contains('ACTION_VPN_SETTINGS'));
      expect(_src('lib/features/muse/settings/diagnose_sheet.dart'), contains('showMuseConnectDoctor(context)'));
      // 1.20.3：诊断页上「连不上」流程直接放在页顶
      expect(_src('lib/features/muse/settings/diagnose_sheet.dart'), contains('MuseConnectDoctorView(embedded: true)'));
    });

    testWidgets('首页 offers 一键诊断 after a failed connect', (t) async {
      await _pumpBanner(t, MuseHealthState.none, const ConnectionStatus.disconnected(ConnectionFailure.unexpected('x')));
      expect(find.byKey(const ValueKey('home_connect_failed')), findsOneWidget);
      // 1.20.3：按钮叫「诊断」，跳到 设置 › 诊断
      expect(find.text('诊断'), findsOneWidget);
    });
  });

  group('版本 1.13.0', () {
    test('pubspec, changelog, CHANGELOG.md', () {
      expect(_src('pubspec.yaml'), matches(RegExp(r'version: 1\.[1-9]\d\.'))); // 1.20.0: 1.1x and later (1.2x no longer contains 「1.1」) // 1.13.0 or later
      expect(museChangelog.keys, contains('1.13.0'));
      final lines = museChangelog['1.13.0']!.join();
      for (final w in ['上次异常', '一键诊断', '安全模式', '其他 VPN']) {
        expect(lines, contains(w));
      }
      expect(_src('CHANGELOG.md'), contains('### 1.13.0'));
    });
  });

  group('A2 e2e 启动路径', () {
    test('debug-only hooks for 开机自启 / 小组件更新; boot logic shared with the receiver', () {
      final boot = _src('$_kt/bg/BootReceiver.kt');
      expect(_fnBody(boot, 'override fun onReceive('), contains('autoStart()'));
      final h = _src('$_kt/ChuanyunHandler.kt');
      for (final m in ['"e2e_boot"', '"e2e_widget_update"']) {
        final at = h.indexOf(m);
        expect(at, greaterThan(0));
        expect(h.substring(at, at + 300), contains('FLAG_DEBUGGABLE'));
      }
    });

    test('the emulator run drives widget, tile, boot and 连→断→再连', () {
      final host = _src('test_driver/muse_e2e_test.dart');
      final body = _fnBody(host, 'Future<Map<String, Object?>> launchPaths()');
      expect(body, contains(r"'$pkg/com.hiddify.hiddify.QuickActionActivity'"));
      expect(body, contains("'click-tile'"));
      expect(body, contains("cmd('e2eBoot')"));
      expect(body, contains("want('home-cycle', false"));
      expect(body, contains("want('home-cycle', true"));
      expect(body, contains('createService'));
      expect(host, contains("results['launch-paths'] = await launchPaths();"));
      final drv = _src('test_driver/muse_e2e.dart');
      expect(drv, contains("invokeMethod<bool>('e2e_boot')"));
      expect(drv, contains("invokeMethod<bool>('e2e_widget_update')"));
    });
  });

  // e2e #16: two in-app disconnects each froze the app for 120 s. Mobile.close ran on the main
  // thread (= Flutter's UI thread) and the core needed 120 s to close.
  group('停止有上限且不占主线程（e2e #16 卡 120 秒）', () {
    final box = _src('$_kt/bg/BoxService.kt');
    final stop = _src('$_kt/bg/CoreStop.kt');

    test('no Mobile.close on the main thread anywhere in the service', () {
      final body = _fnBody(box, 'private fun stopService()');
      expect(body, contains('CoreStop.closeWithin('));
      expect(body, isNot(contains('Mobile.close')));
      // the close comes before the main-thread block that reports 已停止
      final main = body.indexOf('withContext(Dispatchers.Main)');
      expect(body.indexOf('CoreStop.closeWithin('), lessThan(main));
      expect(body.substring(main), contains('status.value = Status.Stopped'));
      for (final f in ['bg/BoxService.kt', 'bg/CompatService.kt', 'MethodHandler.kt', 'ChuanyunHandler.kt']) {
        expect(_src('$_kt/$f'), isNot(contains('Mobile.close(')), reason: f);
      }
      expect(stop, contains('Mobile.close(4L)'));
    });

    test('the core closes on its own thread, waited on for at most 10 s, never twice at once', () {
      expect(stop, contains('const val TIMEOUT_MILLIS = 10_000L'));
      expect(stop, contains('const val PORT = 17079'));
      final run = _fnBody(stop, 'fun runWithin(');
      expect(run, contains('Thread('));
      expect(run, contains('latch.await(timeoutMillis, TimeUnit.MILLISECONDS)'));
      expect(run, contains('running.count > 0L'));
      expect(run, contains('forceReleasePort(PORT)'));
      expect(run, contains('DisconnectLog.record('));
      expect(run, contains('catch (e: Throwable)'));
    });

    test('past the limit 17079 is released: loopback sockets on the port are shut down', () {
      final f = _fnBody(stop, 'fun forceReleasePort(');
      expect(f, contains('/proc/self/fd'));
      expect(f, contains('Os.getsockname('));
      expect(f, contains('local.port == port'));
      expect(f, contains('isLoopbackAddress'));
      expect(f, contains('Os.shutdown(dup.fileDescriptor, OsConstants.SHUT_RDWR)'));
      expect(f, contains('dup?.close()'));
    });

    test('a new setup waits for a late close first (its gRPC server would be taken down)', () {
      final body = _fnBody(box, 'private suspend fun startService()');
      expect(body.indexOf('CoreStop.awaitIdle()'), greaterThan(0));
      expect(body.indexOf('CoreStop.awaitIdle()'), lessThan(body.indexOf('Mobile.setup(')));
      expect(_fnBody(stop, 'fun awaitIdle('), contains('latch.await(maxMillis'));
    });

    test('every caller of releaseCore is off the main thread', () {
      expect(_fnBody(box, 'private suspend fun stopAndAlert('), contains('withContext(Dispatchers.IO) { releaseCore() }'));
      final mh = _src('$_kt/MethodHandler.kt');
      expect(mh, contains('withContext(Dispatchers.IO) { BoxService.releaseCore() }'));
      final ch = _src('$_kt/ChuanyunHandler.kt');
      final at = ch.indexOf('"release_core" ->');
      expect(ch.substring(at, at + 400), contains('Thread('));
      expect(ch.substring(at, at + 400), contains('main.post { result.success(true) }'));
    });

    test('兼容内核 stop is bounded too', () {
      final c = _fnBody(_src('$_kt/bg/CompatService.kt'), 'private fun releaseCore()');
      expect(c, contains('CoreStop.runWithin("兼容内核"'));
      expect(c.indexOf('CoreStop.runWithin'), lessThan(c.indexOf('tun?.close()')));
    });

    test('Dart waits for the service limit, and its own stop call has a deadline', () {
      expect(bgStopWait, greaterThan(const Duration(seconds: 10)));
      expect(bgStopWait, lessThanOrEqualTo(const Duration(seconds: 15)));
      expect(museStopCallTimeout, const Duration(seconds: 10));
      final m = _src('lib/hiddifycore/core_interface/core_interface_mobile.dart');
      expect(_fnBody(m, 'Future<bool> stop() async'), contains('waitUntilPortFor(portBack, false, bgStopWait)'));
      final svc = _src('lib/hiddifycore/hiddify_core_service.dart');
      expect(svc, contains('await core.bgClient.stop(Empty(), options: PlatformUtils.isAndroid ? CallOptions(timeout: museStopCallTimeout) : null);'));
    });

    test('waitUntilPortFor returns as soon as the port closes, and gives up after the limit', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      server.listen((s) => s.destroy());
      unawaited(Future<void>.delayed(const Duration(milliseconds: 600), server.close));
      final sw = Stopwatch()..start();
      expect(await waitUntilPortFor(port, false, const Duration(seconds: 5)), isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 4)));
      final open = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      open.listen((s) => s.destroy());
      sw.reset();
      expect(await waitUntilPortFor(open.port, false, const Duration(milliseconds: 700)), isFalse);
      expect(sw.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 700)));
      await open.close();
    });

    test('the emulator run fails on any stop longer than 15 s and keeps the app logs', () async {
      final sh = _src('tool/emulator/run_e2e.sh');
      expect(sh, contains('python3 tool/emulator/check_stops.py out/e2e'));
      expect(sh, contains(r'[ "$rc4" != 0 ]'));
      expect(sh, contains('run-as com.chuanyun.app'));
      final py = _src('tool/emulator/check_stops.py');
      expect(py, contains('LIMIT = 15.0'));
      final r = await Process.run('python3', ['tool/emulator/check_stops.py', '--self-test']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });
  });
}
