// 穿云 1.6.0 C3: the local API client against a fake core on 127.0.0.1 (plain tests: the widget
// test binding would stub every HttpClient).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';

Map<String, Object?> _conn(String id) => {
  'id': id,
  'metadata': {'network': 'tcp', 'type': 'mixed/in', 'destinationIP': '93.184.216.34', 'destinationPort': '443', 'host': 'example.com'},
  'upload': 0,
  'download': 0,
  'start': '2026-10-27T01:00:00Z',
  'chains': ['日本 01'],
  'rule': 'final',
};

String _frame(List<Map<String, Object?>> conns) => jsonEncode({'downloadTotal': 0, 'uploadTotal': 0, 'connections': conns});

/// A stand-in for the core's local API on 127.0.0.1.
class _FakeCore {
  late HttpServer server;
  final deletes = <String>[];
  var openSockets = 0;
  final frames = <String>[];
  String secret = 's3cret-s3cret-s3';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final authed = req.headers.value(HttpHeaders.authorizationHeader) == 'Bearer $secret' || req.uri.queryParameters['token'] == secret;
      if (!authed) {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
        return;
      }
      if (req.method == 'DELETE') {
        deletes.add(req.uri.path);
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        openSockets++;
        ws.done.then((_) => openSockets--);
        if (req.uri.path == '/connections') {
          for (final f in frames) {
            ws.add(f);
          }
        } else if (req.uri.path == '/logs') {
          ws.add(jsonEncode({'type': 'info', 'payload': 'inbound/mixed: connection to example.com'}));
          ws.add(jsonEncode({'type': 'error', 'payload': 'dial tcp: timeout'}));
        }
        await ws.close();
        return;
      }
      req.response.write(jsonEncode({'version': 'test'}));
      await req.response.close();
    });
  }

  int get port => server.port;
}

void main() {
  test('fake core: stream frames, close one / all, wrong key and closed port are errors', () async {
      final core = _FakeCore()..frames.addAll([_frame([_conn('a')]), _frame([_conn('a'), _conn('b')])]);
      await core.start();
      addTearDown(() => core.server.close(force: true));
      final api = MuseLocalApi(port: core.port, secret: core.secret);
      addTearDown(api.close);
      final got = await api.stream('/connections').toList();
      expect(got.length, 2);
      expect(await api.closeConnection('a/b'), isTrue);
      expect(await api.closeAll(), isTrue);
      expect(core.deletes, ['/connections/a%2Fb', '/connections']);
      final wrong = MuseLocalApi(port: core.port, secret: 'nope');
      addTearDown(wrong.close);
      await expectLater(wrong.getJson('/version'), throwsA(isA<MuseLocalApiError>()));
      await expectLater(wrong.stream('/connections').toList(), throwsA(isA<MuseLocalApiError>()));
      final port = core.port;
      await core.server.close(force: true);
      final closed = MuseLocalApi(port: port, secret: core.secret);
      addTearDown(closed.close);
      await expectLater(closed.getJson('/version'), throwsA(isA<MuseLocalApiError>()));
      expect(core.openSockets, 0);
    });

}
