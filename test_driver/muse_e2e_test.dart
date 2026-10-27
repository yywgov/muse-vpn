// 穿云 1.2.1 - host side of the emulator end-to-end run (see test_driver/muse_e2e.dart).
// Takes real device screenshots (adb screencap, status bar included) of every main page in the
// light and true-black themes, connects the real VPN with SOCKS test nodes served by the CI host,
// drives traffic from another app uid (adb shell) through the tunnel (served by the SOCKS nodes
// themselves, see tool/emulator/socks_nodes.py), compares the speeds and totals the app shows
// with the nodes' byte counters per phase (connected, reconnect, node switch, background/resume),
// and times a full manual node test.
// Writes out/e2e/results.json and out/e2e/*.png. Exit code != 0 when connecting fails or the
// speeds stay 0 while traffic flows.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

const pkg = 'com.chuanyun.app';
final out = Directory('out/e2e');
final results = <String, Object?>{};
final failures = <String>[];

Future<ProcessResult> adb(List<String> args) => Process.run('adb', args);

Future<void> sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

late FlutterDriver driver;

Future<String> cmd(String c) async {
  final r = await driver.requestData(c, timeout: const Duration(seconds: 120));
  if (r.startsWith('error:')) stdout.writeln('[e2e] $c -> $r');
  return r;
}

/// System "isn't responding" dialogs of other apps (the emulator's launcher) would cover the
/// screenshot: dismiss them first.
Future<void> dismissSystemDialogs() async {
  for (var i = 0; i < 3; i++) {
    final w = await adb(['shell', 'dumpsys window | grep -E "mCurrentFocus|Application Not Responding|isn.t responding"']);
    final text = '${w.stdout}';
    if (!text.contains('Not Responding') && !text.contains('responding')) return;
    stdout.writeln('[e2e] dismissing system dialog: ${text.trim()}');
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
    await sleep(800);
  }
}

Future<void> shot(String name, {int settleMs = 1600}) async {
  await sleep(settleMs);
  await dismissSystemDialogs();
  final r = await Process.run('adb', ['exec-out', 'screencap', '-p'], stdoutEncoding: null);
  File('${out.path}/$name.png').writeAsBytesSync(r.stdout as List<int>);
  stdout.writeln('[e2e] shot $name');
}

Future<void> nightMode(bool on) async {
  await adb(['shell', 'cmd', 'uimode', 'night', on ? 'yes' : 'no']);
  await sleep(1200);
}

/// The test subscription: SOCKS5 nodes on the CI host (10.0.2.2 from the emulator) with added
/// latency per port, plus two unreachable nodes that time out (protocol names must show).
const profile = '''
{"outbounds":[
 {"type":"socks","tag":"🇭🇰 香港 01","server":"10.0.2.2","server_port":11080,"version":"5"},
 {"type":"socks","tag":"🇯🇵 日本 02","server":"10.0.2.2","server_port":11081,"version":"5"},
 {"type":"socks","tag":"🇸🇬 新加坡 03","server":"10.0.2.2","server_port":11082,"version":"5"},
 {"type":"socks","tag":"🇺🇸 美国 04","server":"10.0.2.2","server_port":11083,"version":"5"},
 {"type":"socks","tag":"🇹🇼 台湾 05","server":"10.0.2.2","server_port":11084,"version":"5"},
 {"type":"socks","tag":"🇰🇷 韩国 06","server":"10.0.2.2","server_port":11085,"version":"5"},
 {"type":"socks","tag":"🇬🇧 英国 07","server":"10.0.2.2","server_port":11086,"version":"5"},
 {"type":"socks","tag":"🇩🇪 德国 08","server":"10.0.2.2","server_port":11087,"version":"5"},
 {"type":"vless","tag":"🇫🇷 法国 09","server":"10.0.2.2","server_port":9,"uuid":"6e5a4c1e-1a2b-4c3d-8e9f-0a1b2c3d4e5f"},
 {"type":"hysteria2","tag":"🇨🇦 加拿大 10","server":"10.0.2.2","server_port":9,"password":"x","tls":{"enabled":true,"server_name":"example.com","insecure":true}}
]}
''';

Future<Map<String, dynamic>> status() async => jsonDecode(await cmd('status')) as Map<String, dynamic>;

Future<bool> waitRunning(bool want, {int seconds = 60}) async {
  for (var i = 0; i < seconds * 2; i++) {
    final s = await status();
    if (s['running'] == want) return true;
    await sleep(500);
  }
  return false;
}

/// Byte counters of the SOCKS test nodes (tool/emulator/socks_nodes.py control port).
Future<Map<String, dynamic>> nodeCounters({bool stop = false}) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:11990/${stop ? 'stop' : 'counters'}'));
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Map<String, int> portBytes(Map<String, dynamic> c) =>
    (c['ports'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));

const stopFile = '/data/local/tmp/e2e_stop';

/// Test traffic that needs no outside host: a CONNECT to 203.0.113.7 (TEST-NET-3, not CN, so the
/// rules send it through the node) is answered by the SOCKS node itself at ~1 MiB/s.
const sinkIp = '203.0.113.7';

String loopFor(String host, {String path = '/stream'}) =>
    'rm -f $stopFile; while [ ! -f $stopFile ]; do printf "GET $path HTTP/1.1\\r\\nHost: $host\\r\\nUser-Agent: curl/8\\r\\nConnection: close\\r\\n\\r\\n" | toybox nc -w 10 $host 80 > /dev/null 2>&1; sleep 1; done';

Future<void> stopTraffic(Process proc) async {
  await adb(['shell', 'touch $stopFile; pkill -f "toybox nc" ; pkill nc ; true']);
  if (await nodeCountersSafe(stop: true) == null) stdout.writeln('[e2e] control port not reachable');
  proc.kill();
  await sleep(2500); // let the last samples drain
}

Future<Map<String, dynamic>?> nodeCountersSafe({bool stop = false}) async {
  try {
    return await nodeCounters(stop: stop);
  } catch (e) {
    stdout.writeln('[e2e] node counters: $e');
    return null;
  }
}

/// One traffic phase: runs [shellLoop] in the emulator shell (uid 2000, so it goes through the
/// VPN), samples the speeds the app shows once a second for [seconds], then stops the loop and
/// compares what the app counted with what the SOCKS nodes carried in the same window.
/// [proxied] phases must show speed on (almost) every sample once the traffic is flowing.
Future<Map<String, Object?>> trafficPhase(String name, String shellLoop, int seconds,
    {bool proxied = true, String? shotName, String? expectPort, Future<void> Function()? afterStart}) async {
  final before = jsonDecode(await cmd('stats')) as Map<String, dynamic>;
  final nodesBefore = await nodeCountersSafe();
  final proc = await Process.start('adb', ['shell', shellLoop]);
  if (afterStart != null) await afterStart();
  var maxUp = 0, maxDown = 0, zeroDown = 0;
  final samples = <String>[];
  for (var i = 0; i < seconds; i++) {
    await sleep(1000);
    final s = jsonDecode(await cmd('stats')) as Map<String, dynamic>;
    final up = s['up'] as int, down = s['down'] as int;
    samples.add('$up/$down');
    if (up > maxUp) maxUp = up;
    if (down > maxDown) maxDown = down;
    if (i >= 3 && down <= 0) zeroDown++; // the first seconds are connection set-up
    if (shotName != null && i == seconds ~/ 2) await shot(shotName, settleMs: 0);
  }
  await stopTraffic(proc);
  final after = jsonDecode(await cmd('stats')) as Map<String, dynamic>;
  final nodesAfter = await nodeCountersSafe();
  final perPort = <String, int>{};
  var nodeDelta = 0;
  if (nodesBefore != null && nodesAfter != null) {
    final b = portBytes(nodesBefore), a = portBytes(nodesAfter);
    for (final k in a.keys) {
      final d = a[k]! - (b[k] ?? 0);
      if (d > 0) perPort[k] = d;
      nodeDelta += d;
    }
  }
  final appDown = (after['downTotal'] as int) - (before['downTotal'] as int);
  final r = <String, Object?>{
    'maxUp': maxUp,
    'maxDown': maxDown,
    'zeroDownSamples': zeroDown,
    'appDownDelta': appDown,
    'appUpDelta': (after['upTotal'] as int) - (before['upTotal'] as int),
    'nodeDelta': nodeDelta,
    'nodePerPort': perPort,
    'current': after['current'],
  };
  results['traffic_$name'] = {...r, 'samples': samples};
  stdout.writeln('[e2e] traffic $name: $r');
  if (proxied) {
    if (nodeDelta < 2 * 1024 * 1024) {
      failures.add('$name: test traffic did not flow through the nodes (node bytes $nodeDelta) - test setup, not the app');
    } else {
      if (maxDown <= 0) failures.add('$name: app showed ↓0B/s the whole time while the node carried $nodeDelta B');
      if (zeroDown > 1) failures.add('$name: app showed ↓0B/s on $zeroDown samples while traffic flowed');
      // the app's own total must roughly match what the node carried (other traffic is small)
      if (appDown < nodeDelta * 0.5 || appDown > nodeDelta * 2 + 4 * 1024 * 1024) {
        failures.add('$name: app counted $appDown B down, node carried $nodeDelta B');
      }
      if (expectPort != null && (perPort[expectPort] ?? 0) < nodeDelta * 0.8) {
        failures.add('$name: traffic was expected on node port $expectPort, got $perPort');
      }
    }
  }
  return r;
}

Future<void> pages(String theme) async {
  await cmd('go:home');
  await shot('$theme-01-home-connected', settleMs: 2500);
  await driver.scroll(find.byValueKey('home_node_list'), 0, -260, const Duration(milliseconds: 400));
  await shot('$theme-02-home-mid-scroll');
  await driver.scroll(find.byValueKey('home_node_list'), 0, 900, const Duration(milliseconds: 300));
  for (final (i, page) in ['config', 'settings', 'perAppProxy', 'appList', 'nodes', 'tlsTricks', 'connections', 'logs', 'about', 'openSource'].indexed) {
    await cmd('go:$page');
    // the installed-app list loads from the system first
    await shot('$theme-${(i + 3).toString().padLeft(2, '0')}-$page', settleMs: page == 'appList' ? 6000 : 1600);
  }
  await cmd('go:home');
  await sleep(800);
  await cmd('sheet');
  await shot('$theme-13-bottom-sheet');
  await cmd('back');
  await sleep(600);
  await cmd('go:settings');
  await sleep(800);
  await cmd('dialog');
  await shot('$theme-14-dialog');
  await cmd('back');
  await cmd('go:home');
}

Future<void> main() async {
  out.createSync(recursive: true);
  driver = await FlutterDriver.connect(timeout: const Duration(minutes: 3));
  await driver.waitUntilFirstFrameRasterized();
  for (var i = 0; i < 60; i++) {
    final r = await driver.requestData('ready');
    if (r == 'ok') break;
    await sleep(1000);
  }
  // the CI host grants what a user would tap through: VPN consent and notifications
  await adb(['shell', 'appops', 'set', pkg, 'ACTIVATE_VPN', 'allow']);
  await adb(['shell', 'pm', 'grant', pkg, 'android.permission.POST_NOTIFICATIONS']);
  await cmd('prefs');

  // disconnected home, both themes
  await nightMode(false);
  await cmd('theme:light');
  await cmd('go:home');
  await shot('light-00-home-disconnected', settleMs: 3000);
  await nightMode(true);
  await cmd('theme:black');
  await shot('black-00-home-disconnected', settleMs: 2500);
  await nightMode(false);
  await cmd('theme:light');

  final added = await cmd('addProfile:$profile');
  results['addProfile'] = added;
  stdout.writeln('[e2e] addProfile -> $added');

  await cmd('connect');
  final connected = await waitRunning(true, seconds: 90);
  results['connected'] = connected;
  results['statusAfterConnect'] = await status();
  if (!connected) failures.add('VPN did not connect: ${results['statusAfterConnect']}');
  await sleep(10000); // first node tests

  if (connected) {
    // 2: speeds while another app's traffic goes through the tunnel
    final nc = await adb(['shell', 'toybox nc --help 2>&1 | head -1; which toybox nc']);
    results['nc'] = '${nc.stdout}'.trim();
    // CN site, direct by rule: recorded only (depends on the runner reaching www.baidu.com)
    await trafficPhase('direct_cn', loopFor('www.baidu.com', path: '/'), 10, proxied: false);
    await cmd('go:home');
    await trafficPhase('proxied', loopFor(sinkIp), 15, shotName: 'light-home-speed-during-traffic');

    // the paths the user takes on a phone: reconnect, switch node, app to background and back
    await cmd('disconnect');
    await waitRunning(false, seconds: 30);
    await cmd('connect');
    if (await waitRunning(true, seconds: 60)) {
      await sleep(4000);
      await trafficPhase('after_reconnect', loopFor(sinkIp), 12, shotName: 'light-home-speed-after-reconnect');
    } else {
      failures.add('reconnect failed');
    }
    results['selectNode'] = await cmd('select:🇭🇰 香港 01');
    await sleep(2000);
    await trafficPhase('after_node_switch', loopFor(sinkIp), 12, expectPort: '11080', shotName: 'light-home-speed-after-node-switch');
    await cmd('select:lowest');
    await sleep(1000);
    await adb(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
    await sleep(30000);
    await adb(['shell', 'am', 'start', '-n', '$pkg/com.hiddify.hiddify.MainActivity']);
    await sleep(3000);
    await trafficPhase('after_resume', loopFor(sinkIp), 12, shotName: 'light-home-speed-after-resume');
    // traffic that started while the app was in the background, then the app comes back
    await trafficPhase('after_resume_2', loopFor(sinkIp), 10, shotName: 'light-home-speed-after-resume-2', afterStart: () async {
      await sleep(1500);
      await adb(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
      await sleep(15000);
      await adb(['shell', 'am', 'start', '-n', '$pkg/com.hiddify.hiddify.MainActivity']);
      await sleep(2000);
    });

    // 11: how long a full manual node test takes (3 samples + warm-up per node in 1.2.1)
    final timings = <Object?>[];
    for (var i = 0; i < 2; i++) {
      timings.add(jsonDecode(await cmd('urltest')));
      await sleep(2000);
    }
    results['urltest'] = timings;
    results['nodes'] = jsonDecode(await cmd('nodes'));

    // 1.6.0 C9: automation intent — TOGGLE twice flips the connection twice (connected → off → on)
    final toggles = <Object?>[];
    for (final want in [false, true]) {
      await adb(['shell', 'am', 'start', '-a', 'com.chuanyun.app.action.TOGGLE', '-p', pkg]);
      final ok = await waitRunning(want, seconds: 45);
      toggles.add({'want': want, 'ok': ok});
      if (!ok) failures.add('TOGGLE intent did not switch to running=$want');
    }
    results['toggleIntent'] = toggles;
    await adb(['shell', 'am', 'start', '-n', '$pkg/com.hiddify.hiddify.MainActivity']);
    await sleep(2000);
  }

  results['pickApps'] = await cmd('pickApps:com.android.chrome,com.google.android.youtube,com.google.android.apps.maps,'
      'com.android.settings,com.android.contacts,com.google.android.calendar,com.android.camera2,com.google.android.deskclock');
  await pages('light');
  await nightMode(true);
  await cmd('theme:black');
  await pages('black');
  // the app's theme, not the system's, decides the icons
  await cmd('theme:light');
  await cmd('go:home');
  await shot('cross-light-app-on-dark-system-home', settleMs: 2500);
  await cmd('go:perAppProxy');
  await shot('cross-light-app-on-dark-system-perAppProxy');
  await nightMode(false);
  await cmd('theme:black');
  await cmd('go:home');
  await shot('cross-black-app-on-light-system-home', settleMs: 2500);
  await cmd('theme:light');

  await cmd('disconnect');
  results['disconnected'] = await waitRunning(false, seconds: 30);
  results['failures'] = failures;
  File('${out.path}/results.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln('[e2e] results: ${jsonEncode(results)}');
  await driver.close();
  exit(failures.isEmpty ? 0 : 1);
}
