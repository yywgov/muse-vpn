// 穿云 1.20.4：标准内核 5.0.0-chuanyun.25（版本名由 muse 改为 chuanyun；远程 DNS 组并行、远程答案保留真实 TTL，只改内核生成配置），
// 切换节点后清一次内核 DNS 缓存；关于 / 内核与资源页显示的内核版本与 dependencies.properties 一致。
// 普通 test（不是 testWidgets）：清缓存请求打到 127.0.0.1 上的假内核。
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/settings/core_kind_section.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

String _src(String p) => File(p).readAsStringSync();

/// A `read` over fixed values (what museFlushDnsAfterSwitch reads from the container).
T Function<T>(ProviderListenable<T>) _reader(Map<ProviderListenable<Object?>, Object?> values) {
  T read<T>(ProviderListenable<T> p) {
    if (!values.containsKey(p)) throw StateError('unexpected read $p');
    return values[p] as T;
  }

  return read;
}

void main() {
  group('版本 1.20.4', () {
    test('pubspec、更新说明、CHANGELOG.md', () {
      // 1.20.5 起 pubspec 与最新一条是 1.20.5（v1205_release_test）；1.20.4 的条目保留
      expect(_src('pubspec.yaml'), contains(RegExp(r'version: 1\.20\.\d+\+2\d\d')));
      expect(museChangelog.keys, contains('1.20.4'));
      final lines = museChangelog['1.20.4']!;
      expect(lines, hasLength(3));
      final all = lines.join();
      for (final w in ['同时问两台', '不再多等一次', '换节点', '清一次 DNS 缓存', '5.0.0-chuanyun.25', '内核 chuanyun.25']) {
        expect(all, contains(w), reason: w);
      }
      final md = _src('CHANGELOG.md');
      expect(md, contains('### 1.20.4 - 2026-11-12'));
      expect(md.indexOf('### 1.20.4'), lessThan(md.indexOf('### 1.20.3')));
      for (final w in ['mode: parallel', '86400', '真实 TTL', '/cache/dns/flush', 'museCoreRelease']) {
        expect(md, contains(w), reason: w);
      }
    });
  });

  group('内核版本引用', () {
    test('dependencies.properties = chuanyun.25（兼容内核提交 1.20.5 起见 v1205_release_test）', () {
      final props = _src('dependencies.properties');
      expect(RegExp(r'^muse\.core\.version=(\S+)$', multiLine: true).firstMatch(props)?.group(1), '5.0.0-chuanyun.25');
      expect(RegExp(r'^muse\.compat\.ref=([0-9a-f]{40})$', multiLine: true).firstMatch(props)?.group(1), isNotNull);
      // every non-comment line is still key=value (the Makefile and CI read this file)
      for (final line in props.split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith('#'))) {
        expect(line, matches(RegExp(r'^[a-z.]+=\S+$')), reason: line);
      }
    });

    test('关于 / 内核与资源页显示的版本常量与引用一致（不再停在 muse.23）', () {
      final props = _src('dependencies.properties');
      final shipped = RegExp(r'muse\.core\.version=(\S+)').firstMatch(props)!.group(1);
      expect(museCoreRelease, shipped);
      expect(museCoreRelease, isNot(contains('muse.23')));
      expect(museCoreRelease, '5.0.0-chuanyun.25');
      expect(museCoreShort(), 'chuanyun.25');
      expect(museCoreDisplay(), '内核 chuanyun.25');
      expect(museCoreKindVersion(MuseCoreKind.standard), '内核 chuanyun.25');
      expect(museCoreVersionLabel(), '5.0.0-chuanyun.25');
      // no other hard-coded standard-core release constant in lib/
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('resources.dart')) continue;
        expect(f.readAsStringSync().contains(RegExp(r"'5\.0\.0-muse\.\d+'")), isFalse, reason: f.path);
      }
    });
  });

  group('内核版本名 muse → chuanyun：两种前缀都能解析', () {
    test('museCoreReleaseNumber / museCoreShort 认 chuanyun.N 与旧的 muse.N，带不带 v 都行', () {
      expect(museCoreReleaseNumber('5.0.0-chuanyun.25'), 25);
      expect(museCoreReleaseNumber('v5.0.0-chuanyun.25'), 25);
      expect(museCoreReleaseNumber('5.0.0-muse.24'), 24);
      expect(museCoreReleaseNumber('v5.0.0-muse.18'), 18);
      expect(museCoreReleaseNumber(' 5.0.0-chuanyun.100 '), 100);
      for (final bad in ['5.0.0', '5.0.0-beta.1', 'chuanyun.25', '5.0.0-chuanyun.', '5.0.0-musex.3', '']) {
        expect(museCoreReleaseNumber(bad), isNull, reason: bad);
      }
      // one series: the renamed release is newer than the last muse one
      expect(museCoreReleaseNumber('5.0.0-chuanyun.25'), greaterThan(museCoreReleaseNumber('5.0.0-muse.24')!));
      expect(museCoreShort('5.0.0-muse.24'), 'muse.24');
      expect(museCoreShort('v5.0.0-chuanyun.25'), 'chuanyun.25');
      expect(museCoreDisplay('5.0.0-muse.24'), '内核 muse.24');
    });

    test('只改了版本名：仓库、下载地址与产物名、兼容内核引用键不变', () {
      final make = _src('Makefile');
      expect(make, contains(r'MUSE_CORE_URL=https://github.com/yywgov/muse-core/releases/download/v$(muse.core.version)'));
      expect(make, contains(r'$(MUSE_CORE_URL)/$(CORE_NAME)-windows-amd64.tar.gz'));
      final props = _src('dependencies.properties');
      expect(props, contains('muse.core.version='));
      expect(props, contains('muse.compat.ref='));
      // CI reads the release only through the Makefile; nothing there parses a "muse." prefix
      for (final wf in ['.github/workflows/muse-android.yml', '.github/workflows/muse-windows.yml']) {
        final s = _src(wf);
        expect(s.contains(RegExp(r'5\.0\.0-muse|-muse\.')), isFalse, reason: wf);
      }
    });
  });

  group('切换节点后清一次 DNS 缓存', () {
    late HttpServer server;
    final hits = <String>[];
    const secret = 'abcdefghijklmnop';

    setUp(() async {
      hits.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final authed = req.headers.value(HttpHeaders.authorizationHeader) == 'Bearer $secret';
        hits.add('${req.method} ${req.uri.path}${authed ? '' : ' (no auth)'}');
        req.response.statusCode = authed ? HttpStatus.noContent : HttpStatus.unauthorized;
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('已连接：向内核发一次 POST /cache/dns/flush（与活动页「清空缓存」同一接口）', () async {
      final read = _reader({museRunningProvider: true, ConfigOptions.clashApiPort: server.port, museWebSecretProvider: secret});
      expect(await museFlushDnsAfterSwitch(read), isTrue);
      expect(hits, ['POST /cache/dns/flush']);
    });

    test('未连接：什么也不发', () async {
      final read = _reader({museRunningProvider: false});
      expect(await museFlushDnsAfterSwitch(read), isFalse);
      expect(hits, isEmpty);
    });

    test('内核没有回应：静默返回 false，不抛错', () async {
      final port = server.port;
      await server.close(force: true);
      final read = _reader({museRunningProvider: true, ConfigOptions.clashApiPort: port, museWebSecretProvider: secret});
      expect(await museFlushDnsAfterSwitch(read), isFalse);
    });

    test('手动切换（节点页 / 托盘 / 快捷方式）与节点失效自动切换都会调用；不加计时器或轮询', () {
      final memory = _src('lib/features/muse/home/node_memory.dart');
      expect(memory, contains('unawaited(museFlushDnsAfterSwitch(read));'));
      expect(memory.indexOf('museFlushDnsAfterSwitch'), greaterThan(memory.indexOf('changeProxy(groupTag, tag)')));
      final failover = _src('lib/features/muse/home/node_failover.dart');
      expect(failover, contains('unawaited(museFlushDnsAfterSwitch(ref.read));'));
      expect(failover.indexOf('museFlushDnsAfterSwitch(ref.read)'), greaterThan(failover.indexOf('changeProxy(group.tag, target)')));
      final api = _src('lib/features/muse/local_api/local_api_providers.dart');
      final start = api.indexOf('Future<bool> museFlushDnsAfterSwitch');
      final body = api.substring(start, api.indexOf('\n}\n', start));
      for (final w in ['Timer', 'Stream', 'periodic', 'Future.delayed']) {
        expect(body.contains(w), isFalse, reason: w);
      }
      expect(body, contains('flushDnsCache()'));
    });
  });
}
