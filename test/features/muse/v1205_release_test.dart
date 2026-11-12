// 穿云 1.20.5：兼容内核引擎 1.19.33 → 1.19.34（上游稳定版），muse.compat.ref 66d82b1 → muse 分支新提交；
// 设置 › 内核与资源 › 内核版本里兼容内核显示为「兼容内核 chuanyun.25 · 引擎 1.19.34」，与标准内核命名一致。
// 标准内核不变（5.0.0-chuanyun.25）。
// 用户 2026-11-12 15:50 要求并入本版：取消「打开即连接」（打开软件自动连接）——开关、搜索项、启动时的自动连接都删掉；
// 旧键 muse_auto_run 留在存储里不读（降级可读）；开机自启、恢复连接、Wi‑Fi 规则、小组件 / 磁贴 / 快捷方式不动。
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/android_settings.dart' show museAndroidAutomationNote;
import 'package:hiddify/features/muse/settings/auto_connect_page.dart';
import 'package:hiddify/features/muse/settings/core_kind_section.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String p) => File(p).readAsStringSync();

const _newRef = 'c456a830a321c60efcb53ffd18319177fc7f5513';
const _oldRef = '66d82b1502a3b735643faf0e8102aa95f217dd34';

void main() {
  group('版本 1.20.5', () {
    test('pubspec、更新说明、CHANGELOG.md', () {
      // 1.21.0 起 pubspec 与最新一条更新说明是 1.21.0（v1210_test）；1.20.5 的条目保留在它后面
      expect(_src('pubspec.yaml'), contains(RegExp(r'version: 1\.2\d\.\d+\+2\d\d')));
      final keys = museChangelog.keys.toList();
      expect(keys.indexOf('1.20.4'), keys.indexOf('1.20.5') + 1);
      final lines = museChangelog['1.20.5']!;
      expect(lines, hasLength(4));
      final all = lines.join();
      for (final w in ['取消「打开即连接」', '不再自动连接', '开机自启', '恢复连接', '兼容内核', '1.19.34', 'HTTPUpgrade', '测速失败原因', '限定地区', '兼容内核 chuanyun.25 · 引擎 1.19.34', '内核 chuanyun.25']) {
        expect(all, contains(w), reason: w);
      }
      // in-app copy names no upstream project
      for (final w in ['mihomo', 'Mihomo', 'Clash', 'sing-box', 'Meta']) {
        expect(all.contains(w), isFalse, reason: w);
      }
      final md = _src('CHANGELOG.md');
      expect(md, contains(RegExp(r'### 1\.20\.5 - 2026-\d\d-\d\d')));
      expect(md.indexOf('### 1.20.5'), lessThan(md.indexOf('### 1.20.4')));
      for (final w in ['v1.19.33', 'v1.19.34', 'muse.compat.ref', 'v2ray-http-upgrade', '.mrs', 'museCompatDisplay', '打开即连接', 'muse_auto_run']) {
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
  group('取消「打开即连接」', () {
    test('没有开关、没有搜索项；旧名也搜不到它', () {
      expect(museSettingEntries.where((e) => e.title == '打开即连接'), isEmpty);
      for (final e in museSettingEntries) {
        expect(e.keywords, isNot(contains('打开即连接')), reason: e.title);
      }
      for (final q in ['打开即连接', '自动运行', '启动时连接']) {
        expect(museSearchSettings(q, android: true, windows: false).map((e) => e.title), isNot(contains('打开即连接')), reason: q);
      }
      // the page itself is still found under its names
      expect(museSearchSettings('自动连接', android: true, windows: false).first.page, MuseSettingPage.autoConnect);
      expect(museAutoConnectSummary(onDemand: false, schedule: const MuseSchedule(), autoStart: false), '关');
    });

    test('启动时不再自动连接：自动运行的代码与监听都删了，lib 里没有任何地方读旧键', () {
      expect(File('lib/features/muse/home/auto_run.dart').existsSync(), isFalse);
      final app = _src('lib/features/app/widget/app.dart');
      expect(app, isNot(contains('museAutoRun')));
      expect(app, isNot(contains('auto_run.dart')));
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        expect(src.contains('MusePrefs.autoRun'), isFalse, reason: f.path);
        expect(src.contains('museShouldAutoRun'), isFalse, reason: f.path);
        if (!f.path.endsWith('muse_prefs.dart')) {
          expect(src.contains('muse_auto_run') || src.contains('legacyAutoRunKey'), isFalse, reason: f.path);
        }
      }
      // the key name is kept (documented, never read) so an older build still finds it
      expect(MusePrefs.legacyAutoRunKey, 'muse_auto_run');
      expect(_src('lib/features/muse/data/muse_prefs.dart'), isNot(contains('PreferencesNotifier.create<bool, bool>("muse_auto_run"')));
    });

    test('不动的几项还在：开机自启、恢复连接、Wi‑Fi 规则（按需运行）、快捷方式 / 磁贴 / 小组件的连接入口', () {
      final app = _src('lib/features/app/widget/app.dart');
      expect(app, contains('ref.listen(museOnDemandProvider'));
      expect(app, contains('ref.listen(museWifiModeProvider'));
      expect(File('lib/features/muse/logic/startup_restore.dart').existsSync(), isTrue);
      expect(_src('lib/features/muse/settings/auto_connect_page.dart'), contains("title: '开机自启'"));
      expect(_src('lib/features/muse/settings/auto_connect_page.dart'), contains("ValueKey('settings_wifi_rules')"));
      expect(museAndroidAutomationNote, contains('com.chuanyun.app.action.START'));
      for (final kt in ['QuickActionActivity.kt', 'ShortcutActivity.kt']) {
        expect(File('android/app/src/main/kotlin/com/hiddify/hiddify/$kt').existsSync(), isTrue, reason: kt);
      }
    });

    testWidgets('已开启过的用户：启动与断线页（Android）没有这个开关，旧键原样留在存储里', (t) async {
      SharedPreferences.setMockInitialValues({'muse_auto_run': true});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(sharedPreferencesProvider.future));
      t.view.physicalSize = const Size(400, 860);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const MaterialApp(home: MuseAutoConnectPage(android: true, windows: false))),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('打开即连接'), findsNothing);
      expect(find.byKey(const ValueKey('settings_auto_run')), findsNothing);
      expect(find.byKey(const ValueKey('keep_alive')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_wifi_rules')), findsOneWidget);
      expect(t.takeException(), isNull);
      // downgrade-readable: nothing removed or rewritten it
      expect(sp.getBool('muse_auto_run'), isTrue);
    });
  });
}
