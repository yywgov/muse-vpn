// 穿云 1.20.5：兼容内核引擎 1.19.33 → 1.19.34（上游稳定版），muse.compat.ref 66d82b1 → muse 分支新提交；
// 设置 › 内核与资源 › 内核版本里兼容内核显示为「兼容内核 chuanyun.25 · 引擎 1.19.34」，与标准内核命名一致。
// 标准内核不变（5.0.0-chuanyun.25）。
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/settings/core_kind_section.dart';

String _src(String p) => File(p).readAsStringSync();

const _newRef = 'c456a830a321c60efcb53ffd18319177fc7f5513';
const _oldRef = '66d82b1502a3b735643faf0e8102aa95f217dd34';

void main() {
  group('版本 1.20.5', () {
    test('pubspec、更新说明、CHANGELOG.md', () {
      expect(_src('pubspec.yaml'), contains('version: 1.20.5+218'));
      expect(museChangelog.keys.first, '1.20.5');
      expect(museChangelog.keys.elementAt(1), '1.20.4');
      final lines = museChangelog['1.20.5']!;
      expect(lines, hasLength(3));
      final all = lines.join();
      for (final w in ['兼容内核', '1.19.34', 'HTTPUpgrade', '测速失败原因', '限定地区', '兼容内核 chuanyun.25 · 引擎 1.19.34', '内核 chuanyun.25']) {
        expect(all, contains(w), reason: w);
      }
      // in-app copy names no upstream project
      for (final w in ['mihomo', 'Mihomo', 'Clash', 'sing-box', 'Meta']) {
        expect(all.contains(w), isFalse, reason: w);
      }
      final md = _src('CHANGELOG.md');
      expect(md, contains(RegExp(r'### 1\.20\.5 - 2026-\d\d-\d\d')));
      expect(md.indexOf('### 1.20.5'), lessThan(md.indexOf('### 1.20.4')));
      for (final w in ['v1.19.33', 'v1.19.34', 'muse.compat.ref', 'v2ray-http-upgrade', '.mrs', 'museCompatDisplay']) {
        expect(md, contains(w), reason: w);
      }
    });
  });

  group('兼容内核引用', () {
    test('muse.compat.ref 改到新提交，标准内核引用不变', () {
      final props = _src('dependencies.properties');
      final ref = RegExp(r'^muse\.compat\.ref=(\S+)$', multiLine: true).firstMatch(props)?.group(1);
      expect(ref, _newRef);
      expect(ref, isNot(_oldRef));
      expect(ref, matches(RegExp(r'^[0-9a-f]{40}$')), reason: 'CI reads a 40-hex commit');
      expect(RegExp(r'^muse\.core\.version=(\S+)$', multiLine: true).firstMatch(props)?.group(1), '5.0.0-chuanyun.25');
      expect(museCoreRelease, '5.0.0-chuanyun.25');
      for (final line in props.split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith('#'))) {
        expect(line, matches(RegExp(r'^[a-z.]+=\S+$')), reason: line);
      }
    });

    test('Android / Windows CI 仍从 muse.compat.ref 构建，引擎版本取自内核仓库的 mihomo.yml', () {
      for (final wf in ['.github/workflows/muse-android.yml', '.github/workflows/muse-windows.yml']) {
        final s = _src(wf);
        expect(s, contains(r"sed -n 's/^muse\.compat\.ref=\([0-9a-f]\{40\}\)$/\1/p' dependencies.properties"), reason: wf);
        expect(s, contains(r"sed -n 's/^  MIHOMO_VERSION: \(.*\)$/\1/p' ../.github/workflows/mihomo.yml"), reason: wf);
        expect(s.contains('1.19.33'), isFalse, reason: wf);
      }
    });
  });

  group('兼容内核版本显示与 chuanyun 命名一致', () {
    test('museCompatDisplay', () {
      expect(museCompatEngineVersion, '1.19.34');
      expect(museCompatRelease, '5.0.0-chuanyun.25');
      // compat ref is on the muse branch after chuanyun.25 and differs only in the compatible core
      expect(museCompatRelease, museCoreRelease);
      expect(museCompatDisplay(), '兼容内核 chuanyun.25 · 引擎 1.19.34');
      expect(museCompatDisplay(release: '5.0.0-chuanyun.26', engine: '1.19.40'), '兼容内核 chuanyun.26 · 引擎 1.19.40');
      expect(museCompatDisplay(release: '5.0.0-muse.24'), '兼容内核 muse.24 · 引擎 1.19.34');
      expect(museCoreKindVersion(MuseCoreKind.compat), '兼容内核 chuanyun.25 · 引擎 1.19.34');
      expect(museCoreKindVersion(MuseCoreKind.standard), '内核 chuanyun.25');
      // the old bare engine string is gone from lib/
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        expect(f.readAsStringSync().contains('1.19.33'), isFalse, reason: f.path);
      }
    });

    testWidgets('选择内核对话框里兼容内核一行带新版本，320 px 大字不溢出', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  for (final k in MuseCoreKind.values)
                    ListTile(title: Text(k.title), subtitle: Text('${k.blurb} · ${museCoreKindVersion(k)}')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('兼容内核 chuanyun.25 · 引擎 1.19.34'), findsOneWidget);
      expect(find.textContaining('内核 chuanyun.25'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });
  });
}
