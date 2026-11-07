// 穿云 1.14.0 批2 订阅/节点: R15 订阅更新出错不覆盖, R21 手动添加/编辑节点（本地覆写）, R11 相册扫码,
// B4 只看收藏, B5 二维码分享前提示敏感信息, R14 订阅自定义请求头.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';
import 'package:hiddify/features/muse/logic/qr_image_import.dart';
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
}
