// 穿云 1.14.0 批2 订阅/节点: R15 订阅更新出错不覆盖, R21 手动添加/编辑节点（本地覆写）, R11 相册扫码,
// B4 只看收藏, B5 二维码分享前提示敏感信息, R14 订阅自定义请求头.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/qr_image_import.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/node_form.dart';
import 'package:hiddify/features/muse/logic/sub_override.dart';
import 'package:hiddify/features/muse/nodes/node_form_dialog.dart';
import 'dart:convert';
import 'package:hiddify/features/muse/logic/redact.dart';
import 'package:hiddify/features/muse/logic/sub_headers.dart';
import 'package:hiddify/features/muse/settings/sub_headers_dialog.dart';
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/logic/sub_guard.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/muse/widget/qr_view.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('B5 二维码分享前提示敏感信息', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showMuseQrDialog(context, title: '节点', data: 'vless://u@a.example.com:443#a', warning: museQrNodeWarning),
                child: const Text('分享'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();
    }

    testWidgets('取消 shows no code', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('qr_sensitive_dialog')), findsOneWidget);
      expect(find.textContaining('密码'), findsOneWidget);
      expect(find.byKey(const ValueKey('muse_qr')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('qr_sensitive_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('muse_qr')), findsNothing);
    });

    testWidgets('继续分享 shows the code with the reminder under it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('qr_sensitive_ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('muse_qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('qr_sensitive_note')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('node and subscription QR both pass a warning', () {
      expect(_src('lib/features/muse/nodes/node_details.dart'), contains('warning: museQrNodeWarning'));
      expect(_src('lib/features/profile/widget/profile_tile.dart'), contains('warning: museQrSubscriptionWarning'));
      expect(museQrSubscriptionWarning, contains('订阅链接'));
    });
  });

  group('R11 相册图片扫码导入', () {
    test('found / not found / cancelled / failed', () async {
      final f = File('${Directory.systemTemp.path}/cy_qr_${DateTime.now().microsecondsSinceEpoch}.png')..writeAsStringSync('x');
      var r = await museScanQrFromImage(pick: () async => f.path, decode: (p) async => ' vless://u@a.example.com:443#a ');
      expect(r.outcome, MuseQrImageOutcome.found);
      expect(r.text, 'vless://u@a.example.com:443#a');
      expect(f.existsSync(), isFalse, reason: 'the copy the picker made is removed');
      r = await museScanQrFromImage(pick: () async => '/nope.png', decode: (p) async => null);
      expect(r.outcome, MuseQrImageOutcome.notFound);
      expect(r.message, contains('没有找到二维码'));
      r = await museScanQrFromImage(pick: () async => null, decode: (p) async => fail('not asked'));
      expect(r.outcome, MuseQrImageOutcome.cancelled);
      expect(r.message, isNull);
      r = await museScanQrFromImage(pick: () async => '/nope.png', decode: (p) async => throw StateError('bad image'));
      expect(r.outcome, MuseQrImageOutcome.failed);
      expect(r.message, contains('读取图片失败'));
      r = await museScanQrFromImage(pick: () async => throw StateError('picker'));
      expect(r.outcome, MuseQrImageOutcome.failed);
    });

    test('system picker, no storage permission, the camera is not disposed', () {
      final src = _src('lib/features/muse/logic/qr_image_import.dart');
      expect(src, contains('FileType.image'));
      expect(src, contains('compressionQuality: 0'));
      expect(src, contains('MobileScannerPlatform.instance.analyzeImage'));
      expect(src, isNot(contains('MobileScannerController(')));
      final manifest = _src('android/app/src/main/AndroidManifest.xml');
      for (final p in ['READ_EXTERNAL_STORAGE', 'READ_MEDIA_IMAGES', 'READ_MEDIA_VISUAL_USER_SELECTED', 'MANAGE_EXTERNAL_STORAGE']) {
        expect(manifest, isNot(contains('android.permission.$p"')), reason: p);
      }
      final screen = _src('lib/features/common/qr_code_scanner_screen.dart');
      expect(screen, contains("ValueKey('qr_pick_image')"));
      expect(screen, contains('从相册选择'));
      expect(screen, contains('museScanQrFromImage('));
      expect(_src('pubspec.yaml'), isNot(contains('image_picker')), reason: 'no new dependency');
    });
  });

  group('R15 订阅更新出错不覆盖', () {
    String links(int n) => [for (var i = 0; i < n; i++) 'vless://u@n$i.example.com:443#n$i'].join('\n');
    String singbox(int n) =>
        '{"outbounds":[{"type":"selector","tag":"select","outbounds":[]},${[for (var i = 0; i < n; i++) '{"type":"vless","tag":"n$i","server":"n$i.example.com","server_port":443}'].join(',')}]}';

    test('empty, web page, no nodes', () {
      expect(museSubUpdateProblem(singbox(20), '   \n'), contains('空内容'));
      expect(museSubUpdateProblem(singbox(20), '<!DOCTYPE html><html><body>登录</body></html>'), contains('网页'));
      expect(museSubUpdateProblem(singbox(20), '{"outbounds":[{"type":"direct","tag":"direct"}]}'), contains('没有任何节点'));
      expect(museSubUpdateProblem(singbox(20), 'proxies:\nproxy-groups:\n'), anyOf(isNull, contains('没有任何节点')));
      for (final m in [museSubUpdateProblem(singbox(20), ''), museSubUpdateProblem('', '<html><body></body></html>')]) {
        expect(m, endsWith(museSubKeptNote));
      }
    });

    test('steep drop is held back unless forced; normal changes pass', () {
      final drop = museSubUpdateProblem(singbox(40), links(5));
      expect(drop, museSubDropMessage(40, 5));
      expect(museSubIsDropMessage(drop), isTrue);
      expect(museSubUpdateProblem(singbox(40), links(5), force: true), isNull);
      expect(museSubUpdateProblem(singbox(40), links(30)), isNull);
      expect(museSubUpdateProblem(singbox(8), links(1)), isNull, reason: 'small lists are not judged by count');
      expect(museSubUpdateProblem('', links(1)), isNull, reason: 'first download');
      expect(museSubUpdateProblem(singbox(40), 'some-format-the-preview-cannot-count'), isNull, reason: 'left to the core');
      expect(museSubIsDropMessage('订阅里没有任何节点，$museSubKeptNote'), isFalse);
    });

    test('a reason for every failure, in Chinese', () {
      expect(museSubFailureReason(const ProfileFailure.invalidConfig('订阅返回了空内容，$museSubKeptNote')), '订阅返回了空内容，$museSubKeptNote');
      expect(museSubFailureReason(const ProfileFailure.invalidConfig('unmarshal: bad yaml')), '订阅内容无法解析，$museSubKeptNote');
      expect(museSubFailureReason(const ProfileFailure.unexpected('连接超时，请检查网络')), '连接超时，请检查网络，$museSubKeptNote');
      expect(museSubFailureReason(const ProfileFailure.unexpected('SocketException')), '更新出错，$museSubKeptNote');
      expect(museSubFailureReason(const ProfileFailure.cancelByUser()), isNull);
      expect(museSubBulkFailText(['甲', '乙'], null), '甲、乙：已保留原有节点');
    });

    test('wired into update: guard before the core, last good file put back, drop can be confirmed', () {
      final repo = _src('lib/features/profile/data/profile_repository.dart');
      final update = repo.substring(repo.indexOf('.updateRemote(rp: existing'), repo.indexOf('// Add'));
      expect(update.indexOf('_guardUpdate('), lessThan(update.indexOf('validateConfig(')));
      expect(update, contains('_keepOnFailure('));
      expect(repo, contains("File('\$path.prev')"));
      final n = _src('lib/features/profile/notifier/profile_notifier.dart');
      expect(n, contains('upsertRemote(profile.url, force: force)'));
      expect(n, contains('museSubIsDropMessage(message)'));
      expect(n, contains("positiveBtnTxt: '仍然更新'"));
      final bulk = _src('lib/features/profile/notifier/profiles_update_notifier.dart');
      expect(bulk, contains('museSubFailureReason(result.error)'));
    });
  });

  group('B4 只看收藏（收藏、置顶、搜索、按地区折叠已有）', () {
    test('filter', () {
      final f = MuseNodeFilter.parse(MuseNodeFilter.favorites.toRaw());
      expect(f, MuseNodeFilter.favorites);
      expect(f.label, '收藏');
      expect(f.passes(protocolShort: 'VLESS', tags: const [], favorite: true), isTrue);
      expect(f.passes(protocolShort: 'VLESS', tags: const []), isFalse);
      expect(f.within(protocols: const ['VLESS'], tags: const [], hasFavorites: true), f);
      expect(f.within(protocols: const ['VLESS'], tags: const []).isNone, isTrue, reason: 'never an empty list');
      expect(MuseNodeFilter.parse('p:VLESS').passes(protocolShort: 'VLESS', tags: const []), isTrue);
    });

    test('the existing parts are still there', () {
      final list = _src('lib/features/muse/nodes/node_list.dart');
      for (final k in ["'node_search_field'", "'node_filter_fav'", 'museFavoritesFirst', 'museToggleRegionFold', 'showMuseFavoriteOrder']) {
        expect(list, contains(k), reason: k);
      }
    });
  });

  group('R14 订阅自定义请求头', () {
    test('editor lines', () {
      final r = museParseHeaderLines('# 面板令牌\nX-Token: abc123456\n\nX-Device-Id：dev-1\nx-token: newer');
      expect(r.error, isNull);
      expect(r.headers, {'X-Device-Id': 'dev-1', 'x-token': 'newer'});
      expect(museParseHeaderLines('没有冒号').error, contains('第 1 行'));
      expect(museParseHeaderLines('Host: a.example.com').error, contains('自动设置'));
      expect(museParseHeaderLines('坏 名: 1').error, contains('不允许的字符'));
      expect(museHeaderValueError('a\nb'), isNotNull);
      expect(museHeaderLines({'A': '1', 'B': '2'}), 'A: 1\nB: 2');
    });

    test('stored by subscription, removed when emptied, broken value reads as none', () {
      var raw = museEncodeSubHeaders(const {}, 'p1', {'X-Token': 'secret-1'});
      raw = museEncodeSubHeaders(museParseSubHeaders(raw), 'p2', {'X-Device-Id': 'd'});
      expect(museSubHeadersFor(raw, 'p1'), {'X-Token': 'secret-1'});
      expect(museSubHeadersFor(raw, 'p3'), isEmpty);
      expect(museSubHeadersFor(raw, null), isEmpty);
      raw = museEncodeSubHeaders(museParseSubHeaders(raw), 'p1', const {});
      expect(museParseSubHeaders(raw).keys, ['p2']);
      expect(museParseSubHeaders('not json'), isEmpty);
      expect(museParseSubHeaders('{"p":{"Host":"x","Ok":"1"}}'), {'p': {'Ok': '1'}});
    });

    test('masked in summaries and logs; never synced or backed up', () {
      expect(museMaskHeaderValue('abcdefgh123'), 'ab****');
      expect(museMaskHeaderValue('abc'), '****');
      expect(museMaskedHeaderSummary({'X-Token': 'abcdefgh123'}), 'X-Token: ab****');
      final log = museRedact('GET sub with Authorization: Bearer eyJhbGci.x.y, X-Token: abcdef123 and cookie=sid=42');
      expect(log, isNot(contains('eyJhbGci')));
      expect(log, isNot(contains('abcdef123')));
      expect(log, isNot(contains('sid=42')));
      expect(museSyncedPrefs.keys, isNot(contains('muse_sub_headers')));
      expect(_src('lib/features/muse/data/muse_prefs.dart'), contains('"muse_sub_headers"'));
    });

    test('sent only with that subscription\'s own download', () {
      final parser = _src('lib/features/profile/data/profile_parser.dart');
      expect(parser, contains('extraHeaders: museSubHeadersFor(_ref.read(MusePrefs.subHeaders), profileId)'));
      expect(parser, contains('profileId: rp.id'));
      expect(parser, contains('profileId: id'));
      final dio = _src('lib/core/http_client/dio_http_client.dart');
      expect(dio, contains('Map<String, String> extraHeaders = const {}'));
      expect(_src('lib/features/profile/widget/profile_tile.dart'), contains('showMuseSubHeadersDialog(context, ref, remote.id)'));
    });

    testWidgets('dialog checks before saving', (tester) async {
      Map<String, String>? out;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => out = await showDialog<Map<String, String>>(
                context: context,
                builder: (_) => const MuseSubHeadersDialog(initial: {'X-Token': 'a'}),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('X-Token: a'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('sub_headers_field')), 'bad line');
      await tester.tap(find.byKey(const ValueKey('sub_headers_save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('第 1 行'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('sub_headers_field')), 'X-Device-Id: 9');
      await tester.tap(find.byKey(const ValueKey('sub_headers_save')));
      await tester.pumpAndSettle();
      expect(out, {'X-Device-Id': '9'});
    });
  });

  group('R21 手动添加 / 编辑节点（本地覆写）', () {
    const uuid = '1b2c3d4e-0000-1111-2222-333344445555';

    test('form checks and links for the common protocols', () {
      expect(const MuseNodeForm().error, '请填写名称');
      expect(const MuseNodeForm(name: 'a', server: 'http://x.com').error, contains('地址格式'));
      expect(const MuseNodeForm(name: 'a', server: 'x.com', port: '70000').error, contains('端口'));
      expect(const MuseNodeForm(name: 'a', server: 'x.com', uuid: 'nope').error, contains('UUID'));
      expect(const MuseNodeForm(name: 'a', server: 'x.com', protocol: MuseFormProtocol.trojan).error, '请填写密码');
      expect(const MuseNodeForm(name: 'a', server: 'x.com', uuid: uuid, ws: true, path: 'ws').error, contains('/'));

      final vless = const MuseNodeForm(name: '自建 东京', server: 'jp.example.com', uuid: uuid, sni: 'cdn.example.com', ws: true, path: '/ray').toLink()!;
      expect(vless, startsWith('vless://$uuid@jp.example.com:443?encryption=none&security=tls&sni=cdn.example.com&type=ws&path=%2Fray#'));
      expect(Uri.decodeComponent(vless.split('#').last), '自建 东京');
      final trojan = const MuseNodeForm(protocol: MuseFormProtocol.trojan, name: 't', server: '1.2.3.4', port: '8443', password: 'p@ss').toLink()!;
      expect(trojan, startsWith('trojan://p%40ss@1.2.3.4:8443?security=tls&type=tcp#t'));
      final hy2 = const MuseNodeForm(protocol: MuseFormProtocol.hysteria2, name: 'h', server: 'h.example.com', password: 'x', insecure: true).toLink()!;
      expect(hy2, 'hysteria2://x@h.example.com:443?insecure=1#h');
      final ss = const MuseNodeForm(protocol: MuseFormProtocol.shadowsocks, name: 's', server: 's.example.com', port: '8388', password: 'pw', method: 'aes-256-gcm').toLink()!;
      final user = ss.substring(5, ss.indexOf('@'));
      expect(utf8.decode(base64Url.decode(base64Url.normalize(user))), 'aes-256-gcm:pw');
      final vmess = const MuseNodeForm(protocol: MuseFormProtocol.vmess, name: 'v', server: 'v.example.com', uuid: uuid, tls: false).toLink()!;
      final j = jsonDecode(utf8.decode(base64.decode(vmess.substring(8)))) as Map;
      expect([j['add'], j['port'], j['id'], j['net'], j['tls']], ['v.example.com', '443', uuid, 'tcp', '']);
      expect(museOverrideLinks(vless), [vless], reason: 'a link the 覆写 keeps');
    });

    final original = <String, dynamic>{
      'type': 'vless',
      'tag': '东京 01',
      'server': 'jp.example.com',
      'server_port': 443,
      'uuid': uuid,
      'tls': {'enabled': true, 'server_name': 'jp.example.com'},
    };

    test('edit keeps only what changed and lays it over the node', () {
      final e = MuseNodeEdit.diff(original, server: 'jp.example.com', port: '8443', sni: 'cdn.example.com', uuid: uuid);
      expect(e.toJson(), {'server_port': 8443, 'sni': 'cdn.example.com'});
      final applied = e.applyTo(original);
      expect(applied['server_port'], 8443);
      expect((applied['tls'] as Map)['server_name'], 'cdn.example.com');
      expect((original['tls'] as Map)['server_name'], 'jp.example.com', reason: 'the subscription copy is untouched');
      expect(MuseNodeEdit.diff(original, server: 'jp.example.com', port: '443').isEmpty, isTrue);
      expect(const MuseNodeEdit(password: 'x').applyTo(original).containsKey('password'), isFalse, reason: 'no field the node lacks');
      expect(MuseNodeEdit.fromJson({'server_port': '99999', 'server': ' '}).isEmpty, isTrue);
    });

    test('the patch survives a subscription update and an encode round trip', () {
      var o = const MuseSubOverride().withEdit('东京 01', const MuseNodeEdit(port: 8443));
      expect(o.changesBody, isTrue);
      o = museParseOverrides(museEncodeOverrides({'p1': o}))['p1']!;
      expect(o.edits['东京 01']!.port, 8443);
      String sub(List<Map<String, dynamic>> nodes) => jsonEncode({
        'outbounds': [
          {'type': 'selector', 'tag': 'select', 'outbounds': [for (final n in nodes) n['tag']]},
          ...nodes,
        ],
      });
      // before and after an update that renamed nothing but changed another node
      for (final body in [
        sub([original]),
        sub([original, {'type': 'trojan', 'tag': '新加坡 02', 'server': 'sg.example.com', 'server_port': 443, 'password': 'x'}]),
      ]) {
        final run = jsonDecode(museOverrideBody(body, o)!) as Map;
        final tokyo = (run['outbounds'] as List).firstWhere((e) => e['tag'] == '东京 01') as Map;
        expect(tokyo['server_port'], 8443);
        expect(tokyo['server'], 'jp.example.com');
        expect((run['outbounds'] as List).first['type'], 'selector');
      }
      // a node gone from the subscription: nothing to patch, the patch is kept
      final gone = jsonDecode(museOverrideBody(sub([{'type': 'vless', 'tag': '别的', 'server': 'b', 'server_port': 1, 'uuid': uuid}]), o)!) as Map;
      expect((gone['outbounds'] as List).last['server_port'], 1);
      expect(o.withEdit('东京 01', const MuseNodeEdit()).edits, isEmpty, reason: '恢复订阅原值');
      expect(museEncodeOverrides({'p1': const MuseSubOverride().withEdit('x', const MuseNodeEdit(port: 1))}), contains('"edits"'));
    });

    testWidgets('add dialog: protocol fields, checks, link', (tester) async {
      String? out;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => out = await showDialog<String>(context: context, builder: (_) => const MuseNodeFormDialog()),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('node_add_uuid')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('node_add_save')));
      await tester.pumpAndSettle();
      expect(find.text('请填写名称'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('node_add_name')), '自建');
      await tester.enterText(find.byKey(const ValueKey('node_add_server')), 'my.example.com');
      await tester.enterText(find.byKey(const ValueKey('node_add_uuid')), uuid);
      await tester.tap(find.byKey(const ValueKey('node_add_save')));
      await tester.pumpAndSettle();
      expect(out, startsWith('vless://$uuid@my.example.com:443?'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('edit dialog saves the change only, and can go back to the subscription', (tester) async {
      MuseNodeEdit? out;
      Future<void> open(MuseNodeEdit current) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => out = await showDialog<MuseNodeEdit>(
                  context: context,
                  builder: (_) => MuseNodeEditDialog(original: original, current: current),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
      }

      await open(const MuseNodeEdit());
      expect(find.byKey(const ValueKey('node_edit_reset')), findsNothing);
      expect(find.byKey(const ValueKey('node_edit_password')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('node_edit_port')), '2053');
      await tester.tap(find.byKey(const ValueKey('node_edit_save')));
      await tester.pumpAndSettle();
      expect(out!.toJson(), {'server_port': 2053});
      await open(const MuseNodeEdit(port: 2053));
      expect(find.text('2053'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('node_edit_reset')));
      await tester.pumpAndSettle();
      expect(out!.isEmpty, isTrue);
    });

    test('wired into the node pages', () {
      final list = _src('lib/features/muse/nodes/node_list.dart');
      expect(list, contains("('add', '手动添加节点')"));
      expect(list, contains('museAddNodeFromMenu(context, ref'));
      expect(_src('lib/features/muse/nodes/node_form_dialog.dart'), contains('showMuseAddNodeDialog(context, ref, profileId)'));
      final details = _src('lib/features/muse/nodes/node_details.dart');
      expect(details, contains("ValueKey('node_edit')"));
      expect(details, contains('showMuseEditNodeDialog(context, ref, editProfileId, proxy.tag, editOriginal)'));
      expect(_src('lib/features/muse/config/sub_override_page.dart'), contains("'修改 \${o.edits.length}'"));
    });
  });

  group('版本 1.14.0', () {
    test('pubspec, changelog, CHANGELOG.md', () {
      expect(_src('pubspec.yaml'), contains('version: 1.14.0+203'));
      expect(museChangelog.keys.first, '1.14.0');
      final lines = museChangelog['1.14.0']!.join();
      for (final w in ['保留上次成功的节点', '手动添加节点', '从相册选择', '只看收藏', '二维码', '请求头']) {
        expect(lines, contains(w));
      }
      expect(_src('CHANGELOG.md'), contains('### 1.14.0'));
    });
  });
}
