// 穿云 Windows smoke test for the bundled core (run on windows-latest in CI, no real node).
//
// Loads hiddify-core.dll exactly like the app does (FFI `setup` with a gRPC secret), then drives
// it over gRPC with the x-muse-token header, against a tiny SOCKS5 "node" served by this script:
//   * token: calls without / with a wrong token are rejected, the right token is accepted
//   * 系统代理: Start sets HKCU Internet Settings ProxyEnable/ProxyServer, a request through the
//     mixed port reaches www.gstatic.com/generate_204 via the node, Stop clears the proxy
//   * TUN (gVisor, needs admin): a wintun adapter appears, a request without proxy goes
//     through the node, Stop removes the adapter
//
//   dart run tool/smoke/core_smoke.dart --dll <dir with hiddify-core.dll> --work <dir> --out <dir>
//   dart run tool/smoke/core_smoke.dart --app-grpc --out <dir>    (checks the running app's core)
//
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/gen/hiddify_core_generated_bindings.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';

const _mixedPort = 12334;
const _grpcPort = 17179; // not the app's 17078, so a running app can't interfere
const _inetKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
const _probeUrl = 'https://www.gstatic.com/generate_204';

final _results = <Map<String, Object?>>[];
late Directory _out;
var _name = 'core-smoke';

void _record(String id, String name, bool pass, String detail, {bool optional = false}) {
  _results.add({'id': id, 'name': name, 'pass': pass, 'optional': optional, 'detail': detail});
  print('${pass ? "PASS" : (optional ? "WARN" : "FAIL")} [$id] $name — $detail');
}

Future<void> _finish() async {
  final failed = _results.where((r) => r['pass'] != true && r['optional'] != true).length;
  final md = StringBuffer('# 穿云 $_name\n\n| | check | detail |\n|---|---|---|\n');
  for (final r in _results) {
    final mark = r['pass'] == true ? '✅' : (r['optional'] == true ? '⚠️' : '❌');
    md.writeln('| $mark | ${r['name']} | ${(r['detail'] as String).replaceAll('|', '/').replaceAll('\n', ' ')} |');
  }
  md.writeln('\nfailed (required): $failed');
  File('${_out.path}/$_name.md').writeAsStringSync(md.toString());
  File('${_out.path}/$_name.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_results));
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null) File(summary).writeAsStringSync(md.toString(), mode: FileMode.append);
  exit(failed == 0 ? 0 : 1);
}

String _arg(List<String> args, String name, String fallback) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

String _randomSecret(int n) {
  const c = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final r = Random.secure();
  return List.generate(n, (_) => c[r.nextInt(c.length)]).join();
}

Future<void> main(List<String> args) async {
  _out = Directory(_arg(args, '--out', 'smoke-out')).absolute..createSync(recursive: true);
  if (args.contains('--app-grpc')) {
    _name = 'app-grpc';
    await _checkAppGrpc();
    return _finish();
  }
  final dllDir = Directory(_arg(args, '--dll', '.')).absolute;
  final work = Directory(_arg(args, '--work', 'smoke-work')).absolute..createSync(recursive: true);
  final skipTun = args.contains('--no-tun');

  final node = await _SocksNode.start();
  print('SOCKS5 test node on 127.0.0.1:${node.port}');

  // ---- load the dll and set it up exactly like core_interface_desktop.dart ----
  final secret = _randomSecret(100);
  HiddifyCoreNativeLibrary box;
  try {
    Directory.current = dllDir; // libcronet.dll etc. next to it
    box = HiddifyCoreNativeLibrary(DynamicLibrary.open('${dllDir.path}\\hiddify-core.dll'));
    _record('dll', 'hiddify-core.dll loads', true, dllDir.path);
  } catch (e) {
    _record('dll', 'hiddify-core.dll loads', false, '$e');
    return _finish();
  }
  final err = box
      .setup(
        work.path.toNativeUtf8().cast(),
        work.path.toNativeUtf8().cast(),
        Directory.systemTemp.path.toNativeUtf8().cast(),
        SetupMode.GRPC_NORMAL_INSECURE.value,
        '127.0.0.1:$_grpcPort'.toNativeUtf8().cast(),
        secret.toNativeUtf8().cast(),
        0,
        0,
      )
      .cast<Utf8>()
      .toDartString();
  _record('setup', 'core setup() with gRPC secret', err.isEmpty, err.isEmpty ? 'listening 127.0.0.1:$_grpcPort' : err);
  if (err.isNotEmpty) return _finish();

  final channel = ClientChannel(
    '127.0.0.1',
    port: _grpcPort,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );

  // ---- token ----
  Future<String> hello(Map<String, String> md) async {
    try {
      final r = await HelloClient(channel, options: CallOptions(metadata: md, timeout: const Duration(seconds: 10)))
          .sayHello(HelloRequest(name: 'smoke'));
      return 'OK ${r.message}';
    } on GrpcError catch (e) {
      return 'GrpcError ${e.codeName}';
    }
  }

  final noToken = await hello({});
  _record('token-missing', 'gRPC call without x-muse-token is rejected', noToken.contains('UNAUTHENTICATED'), noToken);
  final badToken = await hello({'x-muse-token': 'wrong'});
  _record('token-wrong', 'gRPC call with a wrong token is rejected', badToken.contains('UNAUTHENTICATED'), badToken);
  final goodToken = await hello({'x-muse-token': secret});
  _record('token-ok', 'gRPC call with the token is accepted', goodToken.startsWith('OK'), goodToken);

  final core = CoreClient(channel, options: CallOptions(metadata: {'x-muse-token': secret}));

  // ---- profile: one SOCKS node (this script) ----
  final tmpProfile = File('${work.path}\\profile-temp.json')
    ..writeAsStringSync(
      jsonEncode({
        'outbounds': [
          {'type': 'socks', 'tag': '本地测试节点', 'server': '127.0.0.1', 'server_port': node.port, 'version': '5'},
        ],
      }),
    );
  final profile = '${work.path}\\profile.json';
  try {
    final p = await core.parse(ParseRequest(tempPath: tmpProfile.path, configPath: profile));
    _record('parse', 'profile parses', p.responseCode == ResponseCode.OK, '${p.responseCode} ${p.message}');
  } catch (e) {
    _record('parse', 'profile parses', false, '$e');
    return _finish();
  }

  // ---- 系统代理 ----
  await _setOptions(core, tun: false);
  await _runProxyMode(core, profile, node);

  // ---- TUN (gVisor + wintun) ----
  if (!skipTun) {
    await _setOptions(core, tun: true);
    await _runTunMode(core, profile, node);
  }
  await node.close();
  return _finish();
}

/// Settings as the Windows app sends them (config_option_repository.dart singboxConfigOptions):
/// region cn, direct DNS udp://223.5.5.5, remote tcp://8.8.8.8, gVisor TUN, URL test every 5 min,
/// no LAN sharing, and either 系统代理 or TUN.
Future<void> _setOptions(CoreClient core, {required bool tun}) async {
  final opts = {
    'region': 'cn',
    'balancer-strategy': 'round-robin',
    'log-level': 'info',
    'remote-dns-address': 'tcp://8.8.8.8',
    'direct-dns-address': 'udp://223.5.5.5',
    'mixed-port': _mixedPort,
    'enable-tun': tun,
    'set-system-proxy': !tun,
    'tun-implementation': 'gvisor',
    'mtu': 9000,
    'strict-route': true,
    'connection-test-url': 'http://cp.cloudflare.com',
    'url-test-interval': 300,
    'allow-connection-from-lan': false,
    'enable-clash-api': false,
  };
  try {
    final r = await core.changeHiddifySettings(ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(opts)));
    _record(
      tun ? 'settings-tun' : 'settings-proxy',
      'ChangeHiddifySettings (${tun ? "TUN" : "系统代理"})',
      r.messageType == MessageType.EMPTY,
      '${r.messageType} ${r.message}',
    );
  } catch (e) {
    _record(tun ? 'settings-tun' : 'settings-proxy', 'ChangeHiddifySettings', false, '$e');
  }
}

Future<bool> _start(CoreClient core, String profile, String id) async {
  try {
    final r = await core.start(StartRequest(configPath: profile, configName: '本地测试节点'));
    final ok = r.messageType == MessageType.EMPTY && r.coreState == CoreStates.STARTED;
    _record('$id-start', 'core starts ($id)', ok, '${r.coreState} ${r.messageType} ${r.message}');
    return ok;
  } catch (e) {
    _record('$id-start', 'core starts ($id)', false, '$e');
    return false;
  }
}

Future<void> _stop(CoreClient core, String id) async {
  try {
    final r = await core.stop(Empty());
    _record('$id-stop', 'core stops ($id)', r.coreState == CoreStates.STOPPED, '${r.coreState} ${r.messageType} ${r.message}');
  } catch (e) {
    _record('$id-stop', 'core stops ($id)', false, '$e');
  }
}

Future<({int enable, String server})> _readProxy() async {
  final r = await Process.run('reg', ['query', _inetKey]);
  final out = r.stdout.toString();
  final en = RegExp(r'ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)').firstMatch(out);
  final srv = RegExp(r'ProxyServer\s+REG_SZ\s+(.*)').firstMatch(out);
  return (enable: en == null ? 0 : int.parse(en.group(1)!, radix: 16), server: srv?.group(1)?.trim() ?? '');
}

Future<String> _curl(List<String> extra, String url) async {
  final r = await Process.run('curl.exe', [
    '-sS',
    '-o',
    'NUL',
    '-w',
    '%{http_code}',
    '--max-time',
    '25',
    ...extra,
    url,
  ]);
  return '${r.stdout}'.trim() + ('${r.stderr}'.trim().isEmpty ? '' : ' ${'${r.stderr}'.trim()}');
}

Future<void> _runProxyMode(CoreClient core, String profile, _SocksNode node) async {
  final before = await _readProxy();
  print('proxy before start: $before');
  if (!await _start(core, profile, 'proxy')) return;
  await Future<void>.delayed(const Duration(seconds: 3));

  final on = await _readProxy();
  _record(
    'proxy-set',
    '系统代理 set in registry (ProxyEnable=1, ProxyServer=127.0.0.1:$_mixedPort)',
    on.enable == 1 && on.server.contains('127.0.0.1:$_mixedPort'),
    'ProxyEnable=${on.enable} ProxyServer=${on.server}',
  );

  node.targets.clear();
  final code = await _curl(['-x', 'http://127.0.0.1:$_mixedPort'], _probeUrl);
  _record('proxy-request', 'request via mixed port $_mixedPort → $_probeUrl', code.startsWith('204'), 'http $code');
  final viaNode = node.targets.any((t) => t.contains('gstatic') || t.endsWith(':443'));
  _record('proxy-via-node', 'that request went through the node', viaNode, 'node saw: ${node.targets.take(8).join(', ')}');

  // 国内直连: a CN site must not go through the node (region cn rules)
  node.targets.clear();
  final cn = await _curl(['-x', 'http://127.0.0.1:$_mixedPort'], 'https://www.baidu.com/');
  final cnViaNode = node.targets.any((t) => t.contains('baidu'));
  _record(
    'proxy-cn-direct',
    'www.baidu.com goes direct, not through the node',
    cn.startsWith('200') && !cnViaNode,
    'http $cn; node saw: ${node.targets.take(8).join(', ')}',
    optional: true,
  );

  await _stop(core, 'proxy');
  await Future<void>.delayed(const Duration(seconds: 2));
  final off = await _readProxy();
  _record(
    'proxy-cleared',
    '系统代理 cleared after stop (ProxyEnable=0)',
    off.enable == 0,
    'ProxyEnable=${off.enable} ProxyServer=${off.server}',
  );
}

Future<String> _tunAdapters() async {
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    "Get-NetAdapter -IncludeHidden | Where-Object { \$_.InterfaceDescription -like '*Wintun*' -or \$_.Name -like '*tun*' } | ForEach-Object { \"\$(\$_.Name) | \$(\$_.InterfaceDescription) | \$(\$_.Status)\" }",
  ]);
  return '${r.stdout}'.trim();
}

Future<void> _runTunMode(CoreClient core, String profile, _SocksNode node) async {
  node.allowUpstream = false;
  final admin = (await Process.run('whoami', ['/groups'])).stdout.toString().contains('S-1-16-12288');
  print('elevated: $admin');
  if (!await _start(core, profile, 'tun')) return;
  await Future<void>.delayed(const Duration(seconds: 5));
  final adapters = await _tunAdapters();
  _record('tun-adapter', 'wintun adapter created', adapters.isNotEmpty, adapters.isEmpty ? 'none (admin=$admin)' : adapters);
  final proxy = await _readProxy();
  _record('tun-no-sysproxy', 'TUN mode leaves 系统代理 off', proxy.enable == 0, 'ProxyEnable=${proxy.enable}', optional: true);

  node.targets.clear();
  const tunProbe = 'http://203.0.113.7/generate_204';
  final code = await _curl([], tunProbe);
  final viaNode = node.targets.any((t) => t.startsWith('203.0.113.7'));
  _record(
    'tun-request',
    'request without proxy goes through TUN → core → node ($tunProbe)',
    code.startsWith('204') && viaNode,
    'http $code; node saw: ${node.targets.take(8).join(', ')}',
  );
  await _stop(core, 'tun');
  await Future<void>.delayed(const Duration(seconds: 3));
  final after = await _tunAdapters();
  _record('tun-removed', 'wintun adapter removed after stop', after.isEmpty, after.isEmpty ? 'gone' : after, optional: true);
}

/// The running app's own core (port 17078) must refuse calls without its token.
Future<void> _checkAppGrpc() async {
  final channel = ClientChannel(
    '127.0.0.1',
    port: 17078,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  Future<String> hello(Map<String, String> md) async {
    try {
      final r = await HelloClient(channel, options: CallOptions(metadata: md, timeout: const Duration(seconds: 10)))
          .sayHello(HelloRequest(name: 'smoke'));
      return 'OK ${r.message}';
    } on GrpcError catch (e) {
      return 'GrpcError ${e.codeName} ${e.message}';
    }
  }

  final none = await hello({});
  _record('app-grpc-up', "app's core gRPC is listening on 127.0.0.1:17078", !none.contains('UNAVAILABLE'), none);
  _record('app-grpc-token', "app's core rejects calls without x-muse-token", none.contains('UNAUTHENTICATED'), none);
  final bad = await hello({'x-muse-token': 'wrong'});
  _record('app-grpc-badtoken', "app's core rejects a wrong token", bad.contains('UNAUTHENTICATED'), bad);
  await channel.shutdown();
}

/// Minimal SOCKS5 server (no auth, CONNECT only) standing in for a real node.
class _SocksNode {
  _SocksNode._(this._server);

  final ServerSocket _server;
  final targets = <String>[];

  /// Off during the TUN test: there this process's own connections would be captured by the
  /// TUN and loop back through the core. Targets in 203.0.113.0/24 (TEST-NET-3) are answered by
  /// the node itself with an HTTP 204, so the TUN path is proven without reaching out.
  bool allowUpstream = true;

  int get port => _server.port;

  static Future<_SocksNode> start() async {
    final node = _SocksNode._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    node._server.listen(node._handle);
    return node;
  }

  Future<void> close() => _server.close();

  void _handle(Socket client) {
    final buf = <int>[];
    var stage = 0;
    Socket? upstream;
    late StreamSubscription<List<int>> sub;
    sub = client.listen(
      (data) async {
        if (stage == 2) {
          upstream?.add(data);
          return;
        }
        buf.addAll(data);
        if (stage == 0) {
          if (buf.length < 2 || buf.length < 2 + buf[1]) return;
          buf.removeRange(0, 2 + buf[1]);
          client.add([5, 0]);
          stage = 1;
        }
        if (stage == 1) {
          if (buf.length < 5) return;
          final atyp = buf[3];
          final int len;
          if (atyp == 1) {
            len = 4 + 4 + 2;
          } else if (atyp == 3) {
            len = 4 + 1 + buf[4] + 2;
          } else if (atyp == 4) {
            len = 4 + 16 + 2;
          } else {
            client.destroy();
            return;
          }
          if (buf.length < len) return;
          final cmd = buf[1];
          String host;
          if (atyp == 1) {
            host = buf.sublist(4, 8).join('.');
          } else if (atyp == 3) {
            host = utf8.decode(buf.sublist(5, 5 + buf[4]));
          } else {
            host = InternetAddress.fromRawAddress(Uint8List.fromList(buf.sublist(4, 20))).address;
          }
          final port = (buf[len - 2] << 8) | buf[len - 1];
          final rest = buf.sublist(len);
          buf.clear();
          if (cmd != 1) {
            client.add([5, 7, 0, 1, 0, 0, 0, 0, 0, 0]); // command not supported (UDP)
            await client.flush();
            client.destroy();
            return;
          }
          targets.add('$host:$port');
          stage = 2;
          if (host.startsWith('203.0.113.')) {
            client.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
            client.add(utf8.encode('HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'));
            await client.flush();
            await client.close();
            return;
          }
          if (!allowUpstream) {
            client.add([5, 2, 0, 1, 0, 0, 0, 0, 0, 0]); // not allowed by ruleset
            await client.flush();
            client.destroy();
            return;
          }
          sub.pause();
          try {
            upstream = await Socket.connect(host, port, timeout: const Duration(seconds: 15));
          } catch (_) {
            client.add([5, 4, 0, 1, 0, 0, 0, 0, 0, 0]);
            await client.flush();
            client.destroy();
            return;
          }
          client.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
          if (rest.isNotEmpty) upstream!.add(rest);
          upstream!.listen(client.add, onDone: client.destroy, onError: (_) => client.destroy());
          sub.resume();
        }
      },
      onDone: () => upstream?.destroy(),
      onError: (_) => upstream?.destroy(),
    );
  }
}
