// 穿云 Windows smoke tests: a local SOCKS5 "node" that forwards to the real internet, so the app
// can be connected in CI with a profile that points at 127.0.0.1:<port>.
//   test_node.exe --port 11080 --counters 11990
// GET http://127.0.0.1:<counters>/counters -> {"connections":N,"bytesUp":..,"bytesDown":..,"hosts":[..]}
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

int connections = 0;
int bytesUp = 0;
int bytesDown = 0;
final hosts = <String>[];

String _arg(List<String> args, String name, String fallback) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

Future<void> main(List<String> args) async {
  final port = int.parse(_arg(args, '--port', '11080'));
  final counters = int.parse(_arg(args, '--counters', '11990'));
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('socks node on 127.0.0.1:$port');
  server.listen((c) => unawaited(_handle(c)));
  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, counters);
  http.listen((req) async {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({
      'connections': connections,
      'bytesUp': bytesUp,
      'bytesDown': bytesDown,
      'hosts': hosts.length > 50 ? hosts.sublist(hosts.length - 50) : hosts,
    }));
    await req.response.close();
  });
}

class _Reader {
  _Reader(Stream<Uint8List> s) {
    _sub = s.listen((d) {
      _buf.addAll(d);
      _wake();
    }, onDone: () {
      _done = true;
      _wake();
    }, onError: (_) {
      _done = true;
      _wake();
    });
  }
  late final StreamSubscription<Uint8List> _sub;
  final _buf = <int>[];
  bool _done = false;
  Completer<void>? _waiter;
  void _wake() {
    _waiter?.complete();
    _waiter = null;
  }

  Future<List<int>> take(int n) async {
    while (_buf.length < n) {
      if (_done) throw const SocketException('closed');
      _waiter = Completer<void>();
      await _waiter!.future.timeout(const Duration(seconds: 10));
    }
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  /// hands the rest of the stream over (pending bytes first)
  void pipeTo(Socket dst, void Function(int) count) {
    if (_buf.isNotEmpty) {
      dst.add(_buf);
      count(_buf.length);
      _buf.clear();
    }
    _sub.onData((d) {
      count(d.length);
      dst.add(d);
    });
    _sub.onDone(() => dst.destroy());
    _sub.onError((_) => dst.destroy());
    if (_done) dst.destroy();
  }
}

Future<void> _handle(Socket client) async {
  final r = _Reader(client);
  try {
    final head = await r.take(2);
    if (head[0] != 5) throw 'not socks5';
    await r.take(head[1]);
    client.add([5, 0]);
    final req = await r.take(4);
    String host;
    if (req[3] == 1) {
      host = (await r.take(4)).join('.');
    } else if (req[3] == 3) {
      final len = (await r.take(1))[0];
      host = utf8.decode(await r.take(len));
    } else if (req[3] == 4) {
      final b = await r.take(16);
      host = InternetAddress.fromRawAddress(Uint8List.fromList(b)).address;
    } else {
      throw 'bad atyp';
    }
    final pb = await r.take(2);
    final port = pb[0] << 8 | pb[1];
    if (req[1] != 1) {
      client.add([5, 7, 0, 1, 0, 0, 0, 0, 0, 0]);
      await client.close();
      return;
    }
    connections++;
    hosts.add('$host:$port');
    final upstream = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
    client.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    r.pipeTo(upstream, (n) => bytesUp += n);
    upstream.listen((d) {
      bytesDown += d.length;
      client.add(d);
    }, onDone: client.destroy, onError: (_) => client.destroy());
  } catch (_) {
    try {
      client.add([5, 1, 0, 1, 0, 0, 0, 0, 0, 0]);
    } catch (_) {}
    client.destroy();
  }
}
