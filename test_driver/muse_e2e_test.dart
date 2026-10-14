// 穿云 1.2.1 - host side of the emulator end-to-end run (see test_driver/muse_e2e.dart).
// Takes real device screenshots (adb screencap, status bar included) of every main page in the
// light and true-black themes, connects the real VPN with SOCKS test nodes served by the CI host,
// drives traffic from another app uid (adb shell) through the tunnel to a direct (CN rule) and a
// proxied destination, records the speeds the app shows, and times a full manual node test.
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

Future<void> shot(String name, {int settleMs = 1600}) async {
  await sleep(settleMs);
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

/// Runs [shellLoop] in the emulator shell (uid 2000, so it goes through the VPN) while sampling
/// the app's stats once a second for [seconds]. Returns the max speeds the app reported.
Future<Map<String, int>> trafficPhase(String name, String shellLoop, int seconds) async {
  final before = jsonDecode(await cmd('stats')) as Map<String, dynamic>;
  final proc = await Process.start('adb', ['shell', shellLoop]);
  var maxUp = 0, maxDown = 0;
  final samples = <String>[];
  for (var i = 0; i < seconds; i++) {
    await sleep(1000);
    final s = jsonDecode(await cmd('stats')) as Map<String, dynamic>;
    final up = s['up'] as int, down = s['down'] as int;
    samples.add('$up/$down');
    if (up > maxUp) maxUp = up;
    if (down > maxDown) maxDown = down;
  }
  proc.kill();
  final after = jsonDecode(await cmd('stats')) as Map<String, dynamic>;
  final r = {
    'maxUp': maxUp,
    'maxDown': maxDown,
    'totalDownDelta': (after['downTotal'] as int) - (before['downTotal'] as int),
    'totalUpDelta': (after['upTotal'] as int) - (before['upTotal'] as int),
  };
  results['traffic_$name'] = {...r, 'samples': samples, 'current': after['current']};
  stdout.writeln('[e2e] traffic $name: $r');
  return r;
}

String httpLoop(String host, {String path = '/'}) =>
    'i=0; while [ \$i -lt 400 ]; do printf "GET $path HTTP/1.1\\r\\nHost: $host\\r\\nUser-Agent: curl/8\\r\\nConnection: close\\r\\n\\r\\n" | toybox nc -w 5 $host 80 > /dev/null 2>&1; i=\$((i+1)); done';

Future<void> pages(String theme) async {
  await cmd('go:home');
  await shot('$theme-01-home-connected', settleMs: 2500);
  await driver.scroll(find.byValueKey('home_node_list'), 0, -260, const Duration(milliseconds: 400));
  await shot('$theme-02-home-mid-scroll');
  await driver.scroll(find.byValueKey('home_node_list'), 0, 900, const Duration(milliseconds: 300));
  for (final (i, page) in ['config', 'settings', 'perAppProxy', 'appList', 'privacy', 'advanced', 'tlsTricks', 'connections', 'about', 'openSource'].indexed) {
    await cmd('go:$page');
    await shot('$theme-${(i + 3).toString().padLeft(2, '0')}-$page');
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
    final direct = await trafficPhase('direct_cn', httpLoop('www.baidu.com'), 15);
    final proxied = await trafficPhase('proxied', httpLoop('www.google.com'), 15);
    await cmd('go:home');
    final bg = await Process.start('adb', ['shell', httpLoop('www.google.com')]);
    await shot('light-home-speed-during-traffic', settleMs: 3500);
    bg.kill();
    if (proxied['maxDown']! <= 0 && proxied['maxUp']! <= 0) failures.add('speed stayed 0 for proxied traffic');
    if (direct['maxDown']! <= 0 && direct['maxUp']! <= 0) failures.add('speed stayed 0 for direct (CN) traffic');

    // 11: how long a full manual node test takes (3 samples + warm-up per node in 1.2.1)
    final timings = <Object?>[];
    for (var i = 0; i < 2; i++) {
      timings.add(jsonDecode(await cmd('urltest')));
      await sleep(2000);
    }
    results['urltest'] = timings;
    results['nodes'] = jsonDecode(await cmd('nodes'));
  }

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
