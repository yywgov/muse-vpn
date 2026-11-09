// 穿云 1.19.0: the Windows smoke tests' local SOCKS node (tool/smoke/test_node.dart) must survive a
// client that resets its connection while the node is still writing to it (sing-box does that when
// it reloads or cancels a fetch). Unhandled, that write error ended the node process and every
// later recovery check failed with "connection refused" (tag run #244, attempt 1).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/smoke/test_node.dart' as node;

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

/// SOCKS5 CONNECT to 127.0.0.1:[target] through the node on [nodePort]; returns the socket and
/// its byte stream after the node's success reply.
Future<(Socket, StreamIterator<Uint8List>)> _connect(int nodePort, int target) async {
  final s = await Socket.connect(InternetAddress.loopbackIPv4, nodePort);
  final it = StreamIterator<Uint8List>(s);
  final buf = <int>[];
  Future<void> need(int n) async {
    while (buf.length < n) {
      if (!await it.moveNext()) throw StateError('closed');
      buf.addAll(it.current);
    }
  }

  s.add([5, 1, 0]);
  await need(2);
  buf.removeRange(0, 2);
  s.add([5, 1, 0, 1, 127, 0, 0, 1, target >> 8, target & 0xff]);
  await need(10);
  expect(buf[1], 0, reason: 'CONNECT accepted');
  return (s, it);
}

void main() {
  test('the node keeps serving after clients reset connections mid-transfer', () async {
    // upstream that keeps sending as fast as it can
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final chunk = Uint8List(64 * 1024);
    upstream.listen((c) {
      c.done.catchError((_) {});
      Timer.periodic(const Duration(milliseconds: 1), (t) {
        try {
          c.add(chunk);
        } catch (_) {
          t.cancel();
        }
      });
      c.listen((_) {}, onError: (_) {}, onDone: () {});
    });
    final nodePort = await _freePort();
    final countersPort = await _freePort();
    unawaited(node.main(['--port', '$nodePort', '--counters', '$countersPort']));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    for (var i = 0; i < 20; i++) {
      final (s, it) = await _connect(nodePort, upstream.port);
      await it.moveNext(); // data is flowing
      // abrupt close (RST, SO_LINGER 0) while the node is still writing to this client
      final linger = Uint8List(8)..buffer.asByteData().setInt32(0, 1, Endian.host);
      s.setRawOption(RawSocketOption(RawSocketOption.levelSocket, Platform.isLinux ? 13 : 0x0080, linger));
      s.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    // still alive and forwarding
    final (s, it) = await _connect(nodePort, upstream.port);
    expect(await it.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    s.destroy();
    await upstream.close();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
