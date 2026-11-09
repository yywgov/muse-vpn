// 穿云 1.19.3: Windows recovery smoke "restart-restores" failed now and then (v1.19.0 #244,
// v1.19.1 branch #252, v1.19.2 tag #259; same commits passed elsewhere — timing, not the tag).
//
// Root cause (recovery-logs/ring-after-relaunch.txt of #259 try 1/2): on start-up the app
// re-arms its gRPC log/status streams (listenSingle cancels the previous one → RST_STREAM) while
// the core is already writing that stream's response HEADERS. package:http2 2.3.1 treated a
// HEADERS frame on a stream the client had just cancelled as a connection PROTOCOL_ERROR and
// killed the whole connection ("Connection is being forcefully terminated. (errorCode: 1)"),
// taking the in-flight ChangeHiddifySettings call of the restore-connect down with it →
// "error connecting" → started_by_user=false → next launch did not reconnect.
// http2 3.1.0 handles it (dart-lang/http #1799: "Gracefully handle receiving headers on a stream
// that the client has canceled"); grpc still pins ^2.3.1, so pubspec.yaml overrides it.
//
// These tests drive the real http2 transport over a loopback socket: the server answers a
// stream with HEADERS only after the client has cancelled it. The connection must survive and
// carry the next call.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http2/transport.dart';

String _src(String p) => File(p).readAsStringSync();

List<Header> _req(String path) => [
      Header.ascii(':method', 'POST'),
      Header.ascii(':scheme', 'http'),
      Header.ascii(':path', path),
      Header.ascii(':authority', '127.0.0.1'),
      Header.ascii('content-type', 'application/grpc'),
      Header.ascii('te', 'trailers'),
    ];

void main() {
  test('pubspec overrides http2 to >= 3.1.0 and the lock file resolves it', () {
    final pub = _src('pubspec.yaml');
    final ov = pub.indexOf('\ndependency_overrides:');
    expect(ov, greaterThanOrEqualTo(0), reason: 'dependency_overrides section');
    expect(pub.substring(ov), contains(RegExp(r'\n  http2: \^3\.1\.\d+')));
    final lock = _src('pubspec.lock');
    final m = RegExp(r'\n  http2:\n(?:    .*\n)*?    version: "(\d+)\.(\d+)\.(\d+)"').firstMatch(lock);
    expect(m, isNotNull);
    final major = int.parse(m!.group(1)!);
    final minor = int.parse(m.group(2)!);
    expect(major > 3 || (major == 3 && minor >= 1), isTrue, reason: 'http2 ${m.group(0)}');
  });

  test('HEADERS for a stream the client already cancelled do not kill the connection', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final cancelled = Completer<void>();
    final serverStreams = <ServerTransportStream>[];
    server.listen((socket) {
      final conn = ServerTransportConnection.viaSocket(socket);
      conn.incomingStreams.listen((s) {
        serverStreams.add(s);
        var path = '';
        s.incomingMessages.listen(
          (msg) {
            if (msg is HeadersStreamMessage) {
              for (final h in msg.headers) {
                if (String.fromCharCodes(h.name) == ':path') path = String.fromCharCodes(h.value);
              }
              if (path == '/stream') {
                // like the core: the streaming answer starts only once there is something to
                // send — here, after the client has already cancelled (RST_STREAM in flight)
                unawaited(cancelled.future.then((_) {
                  try {
                    s.sendHeaders([Header.ascii(':status', '200'), Header.ascii('content-type', 'application/grpc')]);
                    s.sendData([0, 0, 0, 0, 0]);
                  } catch (_) {}
                }));
              } else {
                s.sendHeaders([Header.ascii(':status', '200')]);
                s.sendData([1, 2, 3], endStream: true);
              }
            }
          },
          onError: (_) {},
        );
      });
    });

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    final client = ClientTransportConnection.viaSocket(socket);
    Object? connectionError;

    final s1 = client.makeRequest(_req('/stream'));
    final sub = s1.incomingMessages.listen((_) {}, onError: (Object e) => connectionError ??= e);
    // wait until the server has the stream, then cancel it the way listenSingle does
    while (serverStreams.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    s1.terminate();
    await sub.cancel();
    cancelled.complete();
    // the server's late HEADERS/DATA arrive now
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // the next call on the same connection (the restore-connect's ChangeHiddifySettings)
    final s2 = client.makeRequest(_req('/unary'), endStream: true);
    final got = <StreamMessage>[];
    await s2.incomingMessages
        .listen(got.add, onError: (Object e) => connectionError ??= e)
        .asFuture<void>()
        .timeout(const Duration(seconds: 5))
        .catchError((Object e) => connectionError ??= e);
    expect(connectionError, isNull, reason: 'connection was torn down: $connectionError');
    expect(got.whereType<DataStreamMessage>().expand((d) => d.bytes).toList(), [1, 2, 3]);
    expect(client.isOpen, isTrue);

    await client.finish().timeout(const Duration(seconds: 2), onTimeout: () {});
    await server.close();
  });

  test('recovery smoke keeps its checks and the 3-try budget (nothing masked)', () {
    final wf = _src('.github/workflows/muse-windows.yml');
    expect(wf, contains('bash tool/smoke/retry.sh "recovery smoke" 3 powershell'));
    final rs = _src('tool/smoke/recovery_smoke.ps1');
    for (final id in ['restart-restores', 'crash-relaunch', 'crash-reconnect', 'stale-left', 'stale-cleared', 'stale-reconnect']) {
      expect(rs, contains('Rec "$id"'), reason: id);
    }
  });
}
