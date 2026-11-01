// 穿云 1.9.0 #18 - first-run guide: three ways to import on the empty home, reusing the add sheet.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';

void main() {
  test('three choices on phones, two on the desktop (no camera scanner)', () {
    expect(museFirstRunActions(qr: true).map((e) => e.$3), ['粘贴链接', '扫码', '从文件导入']);
    expect(museFirstRunActions(qr: true).map((e) => e.$4), [MuseAddAction.paste, MuseAddAction.qr, MuseAddAction.file]);
    expect(museFirstRunActions(qr: false).map((e) => e.$4), [MuseAddAction.paste, MuseAddAction.file]);
  });

  test("the guide runs the add sheet's own import (same functions as its options)", () {
    final modal = File('lib/features/profile/add/add_profile_modal.dart').readAsStringSync();
    expect(modal, contains("'粘贴链接', () => museAddFromClipboard(context, ref))"));
    expect(modal, contains("'扫描二维码', () => museAddByQr(ref))"));
    expect(modal, contains("'从文件导入', () => museAddFromFile(ref))"));
    expect(modal, contains('MuseAddAction.paste => museAddFromClipboard(context, ref)'));
    final home = File('lib/features/muse/home/muse_home_page.dart').readAsStringSync();
    expect(home, contains('showAddProfile(action: action)'));
    expect(File('lib/core/router/bottom_sheets/bottom_sheets_notifier.dart').readAsStringSync(), contains('AddProfileModal(url: url, action: action)'));
  });
}
