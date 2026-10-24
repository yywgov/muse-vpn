// 穿云 1.4.1 - 局域网同步: the host side (a short-lived HTTP listener on the LAN address, only while
// the pairing sheet is open) and the client side (scan / type the code, push, take the merge).
// Protocol: client POSTs /sync with its stamped snapshot sealed with the pairing key; the host
// asks its user, merges, applies, answers with the merged snapshot sealed the same way and stops
// listening (one pairing = one sync). Both devices end with the same merged state.
// Part of 穿云 (GPLv3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/logic/lan_sync.dart';

// The key derivation is slow on purpose, so sealing/opening runs off the UI isolate. The closures
// are built here, in a scope holding only sendable values: a closure made inside a request handler
// would drag the HttpRequest/HttpResponse (unsendable) into the isolate message.
Future<MuseLanMessage> _openAsync(String body, String key, String expectType) {
  final now = DateTime.now();
  return Isolate.run(() => museLanOpen(body, key, expectType: expectType, now: now));
}

Future<String> _sealAsync(MuseLanMessage m, String key) => Isolate.run(() => museLanSeal(m, key));

enum MuseLanHostState { starting, waiting, syncing, done, expired, failed }

/// The host: listens on the LAN address until one sync is done, the pairing expires or [stop].
class MuseLanHost {
  MuseLanHost(this._sync, {required this.confirm, this.onChange});

  final MuseSyncService _sync;

  /// Asks this device's user whether [device] may sync (both sides confirm).
  final Future<bool> Function(String device) confirm;
  final void Function()? onChange;

  HttpServer? _server;
  Timer? _expiry;
  int _bad = 0;
  bool _busy = false;

  MuseLanPairing? pairing;
  MuseLanHostState state = MuseLanHostState.starting;
  String message = '';
  MuseSyncResult? result;

  void _set(MuseLanHostState s, [String msg = '']) {
    state = s;
    message = msg;
    onChange?.call();
  }

  /// The address to listen on (null = not on a LAN).
  static Future<String?> lanAddress() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return musePickLanAddress([
        for (final i in ifs)
          for (final a in i.addresses) (i.name, a.address),
      ]);
    } catch (_) {
      return null;
    }
  }

  Future<void> start({String? address, Duration ttl = museLanPairingTtl}) async {
    final ip = address ?? await lanAddress();
    if (ip == null) {
      _set(MuseLanHostState.failed, '没有连接局域网（Wi‑Fi 或有线）');
      return;
    }
    try {
      // bound to the LAN address only, never 0.0.0.0
      _server = await HttpServer.bind(ip, 0);
    } catch (e) {
      _set(MuseLanHostState.failed, '无法开始监听：$e');
      return;
    }
    pairing = MuseLanPairing(
      host: ip,
      port: _server!.port,
      key: museNewLanKey(),
      expiresAt: DateTime.now().add(ttl).millisecondsSinceEpoch,
      device: MuseSyncService.deviceName,
    );
    _expiry = Timer(ttl, () {
      if (state == MuseLanHostState.waiting) _set(MuseLanHostState.expired, '配对码已过期');
      unawaited(_close());
    });
    _server!.listen(_handle, onError: (_) {});
    _set(MuseLanHostState.waiting);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    Future<void> reply(int code, [String body = '']) async {
      try {
        res.statusCode = code;
        res.headers.contentType = ContentType.text;
        res.write(body);
        await res.close();
      } catch (_) {}
    }

    final p = pairing;
    final from = req.connectionInfo?.remoteAddress.address ?? '';
    if (p == null || req.method != 'POST' || req.uri.path != '/sync' || !museIsLanAddress(from)) {
      return reply(HttpStatus.forbidden);
    }
    if (_busy || state != MuseLanHostState.waiting || p.expired(DateTime.now())) return reply(HttpStatus.gone);
    _busy = true;
    try {
      final body = await _readBody(req);
      if (body == null) return reply(HttpStatus.requestEntityTooLarge);
      final MuseLanMessage msg;
      try {
        msg = await _openAsync(body, p.key, 'push');
      } on MuseLanException catch (e) {
        await reply(HttpStatus.forbidden, e.message);
        if (++_bad >= museLanMaxBadRequests) {
          _set(MuseLanHostState.failed, '收到多次错误的请求，已停止');
          unawaited(_close());
        }
        return;
      }
      if (!await confirm(msg.device.isEmpty ? from : msg.device)) {
        // answer first: closing the server force-closes the open connection
        await reply(HttpStatus.forbidden, '对方拒绝了同步');
        _set(MuseLanHostState.failed, '已拒绝');
        unawaited(_close());
        return;
      }
      _set(MuseLanHostState.syncing);
      final local = await _sync.stampedLocal(remoteKeys: msg.snapshot.entries.keys.toSet());
      final merged = museLanMerge(local, msg);
      final out = MuseLanMessage(
        type: 'merged',
        session: museLanSession(p.key),
        at: DateTime.now().millisecondsSinceEpoch,
        device: MuseSyncService.deviceName,
        snapshot: merged,
      );
      final sealed = await _sealAsync(out, p.key);
      result = await _sync.applyMerged(merged);
      await reply(HttpStatus.ok, sealed);
      _set(MuseLanHostState.done, result!.summary);
      unawaited(_close());
    } catch (e) {
      await reply(HttpStatus.internalServerError);
      _set(MuseLanHostState.failed, '同步失败：$e');
      unawaited(_close());
    } finally {
      _busy = false;
    }
  }

  static Future<String?> _readBody(HttpRequest req) async {
    final bytes = <int>[];
    await for (final chunk in req.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > museLanMaxBody) return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> _close() async {
    _expiry?.cancel();
    final s = _server;
    _server = null;
    pairing = state == MuseLanHostState.waiting ? pairing : null;
    try {
      await s?.close(force: true);
    } catch (_) {}
  }

  bool get listening => _server != null;

  /// Stops listening (the sheet closed).
  Future<void> stop() => _close();
}

/// The client: sends this device's state to the host shown in [p] and applies the merge.
Future<MuseSyncResult> museLanSyncWith(MuseSyncService sync, MuseLanPairing p, {Duration timeout = const Duration(seconds: 90)}) async {
  if (!museIsLanAddress(p.host)) throw const MuseLanException('只能和局域网内的设备同步');
  if (p.expired(DateTime.now())) throw const MuseLanException('配对码已过期，请在对方设备上重新打开');
  final local = await sync.stampedLocal();
  final msg = MuseLanMessage(
    type: 'push',
    session: museLanSession(p.key),
    at: DateTime.now().millisecondsSinceEpoch,
    device: MuseSyncService.deviceName,
    snapshot: local,
    firstSync: sync.lastSynced().entries.isEmpty,
  );
  final key = p.key;
  final sealed = await _sealAsync(msg, key);
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    // straight to the LAN device, never through 穿云's own proxy
    ..findProxy = (_) => 'DIRECT';
  String body;
  int status;
  try {
    final req = await client.postUrl(Uri(scheme: 'http', host: p.host, port: p.port, path: '/sync')).timeout(const Duration(seconds: 10));
    req.headers.contentType = ContentType.text;
    req.write(sealed);
    // the other user has to confirm: allow time
    final res = await req.close().timeout(timeout);
    status = res.statusCode;
    body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
  } on TimeoutException {
    throw const MuseLanException(museLanNoAnswerHint);
  } on HttpException {
    throw const MuseLanException('连接被对方中断，请重新扫码');
  } on SocketException {
    throw const MuseLanException(museLanUnreachableHint);
  } finally {
    client.close(force: true);
  }
  if (status == HttpStatus.gone) throw const MuseLanException('配对码已用过或已过期');
  if (status != HttpStatus.ok) throw MuseLanException(body.isNotEmpty ? body : '对方返回 $status');
  final reply = await _openAsync(body, key, 'merged');
  return sync.applyMerged(reply.snapshot);
}

