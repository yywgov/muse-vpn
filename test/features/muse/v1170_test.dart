// 穿云 1.17.0 (批5) tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/muse/desktop/hidden_release.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/desktop/uwp_loopback.dart';
import 'package:hiddify/features/muse/settings/windows_settings.dart';
import 'package:hiddify/features/muse/settings/windows_extras.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _signal = StateProvider<int>((_) => 0);
final _other = Provider<int>((_) => 42);

class _Outdated extends Notifier<int> {
  @override
  int build() {
    ref.watch(_signal);
    return 0;
  }

  /// what ConnectionNotifier did before 1.17.0: the core start bumps a watched signal, then reads
  int bumpThenRefRead() {
    ref.read(_signal.notifier).state++;
    return ref.read(_other);
  }

  int bumpThenContainerRead() {
    ref.read(_signal.notifier).state++;
    return ref.container.read(_other);
  }
}

final _outdated = NotifierProvider<_Outdated, int>(_Outdated.new);

void main() {
  b12();
  b13();
  r18();
  r12();
  r19();
  group('上次异常 riverpod _didChangeDependency', () {
    test('a ref.read after a watched dependency changed trips the debug assertion (the root cause)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(_outdated);
      expect(
        () => c.read(_outdated.notifier).bumpThenRefRead(),
        throwsA(isA<AssertionError>().having((e) => '$e', 'message', contains('_didChangeDependency'))),
      );
    });

    test('reading through the container does not', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(_outdated);
      expect(c.read(_outdated.notifier).bumpThenContainerRead(), 42);
    });

    test('ConnectionNotifier never calls ref.read outside build', () {
      final s = File('lib/features/connection/notifier/connection_notifier.dart').readAsStringSync();
      final start = s.indexOf('class ConnectionNotifier');
      final end = s.indexOf('final museConnectPreparingProvider');
      final body = s.substring(start, end);
      expect(RegExp(r'\bref\s*\.\s*read\(').hasMatch(body), isFalse);
      expect(body, contains('T _read<T>(ProviderListenable<T> provider) => ref.container.read(provider);'));
    });

    test('e2e fails on a riverpod assertion in the crash log', () {
      final s = File('test_driver/muse_e2e_test.dart').readAsStringSync();
      expect(s, contains("cmd('crashLog')"));
      expect(s, contains("crashLog.contains('package:riverpod/')"));
    });
  });
}

void b12() {
  group('B12 应用内更新校验与重试', () {
    const hex = 'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';
    const apk = 'https://github.com/yywgov/muse-vpn/releases/download/v1.17.0/Chuanyun-Android-arm64.apk';
    test('finds the .sha256 asset of the package', () {
      final json = {
        'assets': [
          {'name': 'Chuanyun-Android-arm64.apk', 'browser_download_url': apk},
          {'name': 'Chuanyun-Android-arm64.apk.sha256', 'browser_download_url': '$apk.sha256'},
          {'name': 'Chuanyun-Windows-x64.zip.sha256', 'browser_download_url': 'https://evil.example/x.sha256'},
        ],
      };
      expect(museSha256AssetNameFor(apk), 'Chuanyun-Android-arm64.apk.sha256');
      expect(museSha256AssetUrl(json, apk), '$apk.sha256');
      expect(museSha256AssetUrl(json, 'https://github.com/yywgov/muse-vpn/releases/download/v1/Chuanyun-Windows-x64.zip'), isNull);
    });
    test('parses sha256sum output', () {
      expect(museParseSha256File('$hex  Chuanyun-Android-arm64.apk\n', 'Chuanyun-Android-arm64.apk'), hex);
      expect(museParseSha256File('${hex.toUpperCase()} *out/Chuanyun-Android-arm64.apk', 'Chuanyun-Android-arm64.apk'), hex);
      expect(museParseSha256File(hex, 'x.apk'), hex);
      expect(museParseSha256File('$hex  other.apk', 'x.apk'), isNull);
      expect(museParseSha256File('<html>not found</html>', 'x.apk'), isNull);
    });
    test('digest and file must agree', () {
      expect(museExpectedSha256(digest: hex, file: hex), hex);
      expect(museExpectedSha256(digest: null, file: hex), hex);
      expect(museExpectedSha256(digest: hex, file: null), hex);
      expect(museExpectedSha256(digest: null, file: null), isNull);
      expect(
        () => museExpectedSha256(digest: hex, file: 'f' * 64),
        throwsA(isA<MuseUpdateFailure>().having((e) => e.kind, 'kind', MuseUpdateFailureKind.mismatchInfo)),
      );
    });
    test('resume: continues a half part, keeps the current version only', () {
      final dir = Directory.systemTemp.createTempSync('cy117');
      addTearDown(() => dir.deleteSync(recursive: true));
      final part = File('${dir.path}/p')..writeAsBytesSync(List.filled(30, 1));
      expect(museRangePartHave(part.path, (100, 199)), 30);
      expect(museResumeRange((100, 199), 30), 'bytes=130-199');
      expect(museRangePartHave(part.path, (0, 9)), 0, reason: 'longer than the range: unusable');
      expect(museRangePartHave('${dir.path}/none', (0, 9)), 0);
      expect(
        museStaleUpdateFiles(['Chuanyun-1.17.0-arm64.apk.part0', 'Chuanyun-1.16.0-arm64.apk', 'Chuanyun-1.17.0-arm64.apk'], '1.17.0'),
        ['Chuanyun-1.16.0-arm64.apk'],
      );
    });
    test('Chinese messages; checksum failures start over, others continue', () {
      for (final k in MuseUpdateFailureKind.values) {
        final t = museUpdateFailureText(MuseUpdateFailure(k));
        expect(RegExp('[A-Za-z]{3,}').allMatches(t).map((m) => m.group(0)).toSet().difference({'SHA'}), isEmpty, reason: t);
      }
      expect(const MuseUpdateFailure(MuseUpdateFailureKind.checksum).startsOver, isTrue);
      expect(const MuseUpdateFailure(MuseUpdateFailureKind.network).startsOver, isFalse);
      expect(museUpdateFailureText(Exception('x')), contains('重试'));
      expect(museUpdateFailureText(const MuseUpdateFailure(MuseUpdateFailureKind.checksum)), contains('重新下载'));
      expect(museAboutUpdateStatus(const MuseUpdateVerifying()), '正在校验安装包…');
    });
    test('the updater keeps parts on failure and verifies with the .sha256 file', () {
      final s = File('lib/features/muse/update/muse_updater.dart').readAsStringSync();
      expect(s, isNot(contains('dir.deleteSync(recursive: true)')));
      expect(s, contains('FileAccessMode.append'));
      expect(s, contains('museSha256AssetUrl(json!, release.apkUrl)'));
      final about = File('lib/features/about/widget/about_page.dart').readAsStringSync();
      expect(about, contains("startsOver ? '重新下载' : '重试'"));
    });
  });
}

class _Backend implements MuseHotkeyBackend {
  final applied = <Map<MuseHotkeyAction, MuseHotkey>>[];
  @override
  Future<void> apply(Map<MuseHotkeyAction, MuseHotkey> bindings, void Function(MuseHotkeyAction action) onPressed) async =>
      applied.add(Map.of(bindings));
}

class _Probe implements MuseHotkeyProbe {
  _Probe(this.takenKeys);
  final Set<MuseHotkey> takenKeys;
  @override
  bool isFree(MuseHotkey key) => !takenKeys.contains(key);
}

void b13() {
  group('B13 Windows 全局快捷键', () {
    final k = MuseHotkey(ctrl: true, alt: true, usage: PhysicalKeyboardKey.keyK.usbHidUsage);
    final j = MuseHotkey(ctrl: true, alt: true, usage: PhysicalKeyboardKey.keyJ.usbHidUsage);
    test('virtual-key codes and modifier flags for RegisterHotKey', () {
      expect(museWindowsVk(PhysicalKeyboardKey.keyA), 0x41);
      expect(museWindowsVk(PhysicalKeyboardKey.keyZ), 0x5a);
      expect(museWindowsVk(PhysicalKeyboardKey.digit1), 0x31);
      expect(museWindowsVk(PhysicalKeyboardKey.digit0), 0x30);
      expect(museWindowsVk(PhysicalKeyboardKey.f12), 0x7b);
      expect(museWindowsVk(PhysicalKeyboardKey.arrowDown), 0x28);
      expect(museWindowsVk(PhysicalKeyboardKey.backquote), 0xc0);
      for (final key in museBindableKeys.keys) {
        expect(museWindowsVk(key), isNotNull, reason: museKeyLabel(key));
      }
      expect(museWindowsHotkeyMods(k), 2 | 1 | 0x4000);
      expect(museWindowsHotkeyMods(MuseHotkey(win: true, shift: true, usage: 0x70004)), 8 | 4 | 0x4000);
    });
    test('a combination another program holds is not registered and is reported', () {
      final split = museSplitTakenHotkeys(
        {MuseHotkeyAction.toggleConnection: k, MuseHotkeyAction.showWindow: j},
        const {},
        (x) => x != k,
      );
      expect(split.free, {MuseHotkeyAction.showWindow: j});
      expect(split.taken, {MuseHotkeyAction.toggleConnection});
      // our own registration from last time is not mistaken for another program's
      final again = museSplitTakenHotkeys({MuseHotkeyAction.toggleConnection: k}, {MuseHotkeyAction.toggleConnection: k}, (_) => false);
      expect(again.taken, isEmpty);
    });
    test('provider: off by default (nothing bound), taken keys skipped', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final backend = _Backend();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) async => prefs),
          museHotkeysForceProvider.overrideWithValue(true),
          museHotkeyBackendProvider.overrideWithValue(backend),
          museHotkeyProbeProvider.overrideWithValue(_Probe({k})),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sharedPreferencesProvider.future);
      final sub = c.listen(museHotkeysProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(museParseHotkeys(c.read(MusePrefs.hotkeys)), isEmpty, reason: 'nothing bound by default');
      expect(backend.applied.isEmpty || backend.applied.last.isEmpty, isTrue);
      await c.read(MusePrefs.hotkeys.notifier).update(museHotkeysToRaw({MuseHotkeyAction.toggleConnection: k, MuseHotkeyAction.showWindow: j}));
      c.read(museHotkeysProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(backend.applied.last, {MuseHotkeyAction.showWindow: j});
      expect(c.read(museHotkeysTakenProvider), {MuseHotkeyAction.toggleConnection});
      sub.close();
      expect(museHotkeyTakenText, contains('占用'));
    });
  });
}

void r18() {
  group('R18 托盘切节点 收藏/最近', () {
    final items = [
      (tag: 'hk', name: '香港 01', delay: 80),
      (tag: 'jp', name: '日本 01', delay: 65000),
      (tag: 'us', name: '美国 01', delay: 0),
    ];
    test('收藏 / 最近使用 only list nodes of the group, in the user\'s order, 未测 vs 超时', () {
      final p = museTrayPinned(items, selected: 'hk', favorites: ['us', 'gone', 'hk'], recent: ['jp', 'hk']);
      expect(p.favorites.map((e) => e.label), ['美国 01   未测', '香港 01   80 ms']);
      expect(p.favorites.last.selected, isTrue);
      expect(p.recent.map((e) => e.label), ['日本 01   超时', '香港 01   80 ms']);
      final many = museTrayPinned(
        [for (var i = 0; i < 20; i++) (tag: 'n$i', name: 'N$i', delay: 1)],
        selected: '',
        favorites: [for (var i = 0; i < 20; i++) 'n$i'],
        recent: const [],
      );
      expect(many.favorites.length, 10);
      expect(many.recent, isEmpty);
    });
    test('submenus come first inside 节点, top-level order unchanged', () {
      final p = museTrayPinned(items, selected: 'hk', favorites: ['us'], recent: ['jp']);
      final spec = museTrayMenuSpec(
        const Connected(),
        MuseRouteMode.rule,
        nodes: museTrayNodes(items, selected: 'hk'),
        favorites: p.favorites,
        recent: p.recent,
      );
      expect(spec.where((e) => e.key != '-').map((e) => e.label).toList(), ['断开', '规则', '全局', '节点', '显示窗口', '退出']);
      final sub = spec.firstWhere((e) => e.key == 'nodes').children;
      expect(sub[0].label, '收藏');
      expect(sub[0].children.single.key, 'node:us');
      expect(sub[1].label, '最近使用');
      expect(sub[1].children.single.label, '日本 01   超时');
      expect(sub[2].key, '-');
      final none = museTrayMenuSpec(const Connected(), MuseRouteMode.rule, nodes: museTrayNodes(items, selected: 'hk'));
      expect(none.firstWhere((e) => e.key == 'nodes').children.first.key, startsWith('node:'));
    });
  });
}

void r12() {
  group('R12 商店应用回环豁免', () {
    const a = 'S-1-15-2-1234567890-1111111111-2222222222-3333333333-444444444-555555555-666666666';
    const b = 'S-1-15-2-9876543210-1111111111-2222222222-3333333333-444444444-555555555-777777777';
    test('reads store-app SIDs from reg query and the exempt list', () {
      final reg = '\r\n$museAppContainerKey\\$a\r\n$museAppContainerKey\\${b.toLowerCase()}\r\n$museAppContainerKey\\$a\r\n';
      expect(museParseAppContainerSids(reg), [a, b]);
      expect(museParseAppContainerSids('ERROR: nothing'), isEmpty);
      expect(museParseLoopbackExempt('List Loopback Exempted AppContainers\r\n\r\n[1] -----\r\n    Name: x\r\n    SID:  $a\r\nOK.'), {a});
    });
    test('script adds / removes exactly the given SIDs; elevation is explicit', () {
      final add = museLoopbackScript([a, b]);
      expect(add, contains('CheckNetIsolation.exe LoopbackExempt -a -p=$a'));
      expect(add, contains('-a -p=$b'));
      expect(add, isNot(contains(' -c')), reason: 'never clears exemptions the user made');
      expect(museLoopbackScript([a], remove: true), contains('LoopbackExempt -d -p=$a'));
      final args = museLoopbackElevateArgs(r"C:\Users\o'k\loopback.cmd");
      expect(args.last, contains('-Verb RunAs'));
      expect(args.last, contains("o''k"));
      expect(args.last, contains('exit 1223'));
    });
    test('Chinese results and explanation; tile only runs when tapped', () {
      expect(museLoopbackResultText(const MuseLoopbackDone(3)), contains('3 个商店应用'));
      expect(museLoopbackResultText(const MuseLoopbackDone(0)), contains('不用再开通'));
      expect(museLoopbackResultText(const MuseLoopbackDone(2, removed: true)), contains('撤销'));
      expect(museLoopbackResultText(const MuseLoopbackDeclined()), contains('管理员授权'));
      expect(museLoopbackExplain, contains('管理员授权'));
      expect(museLoopbackExplain, contains('不会自动运行'));
      expect(museUwpAddedFromRaw('["$a"]'), [a]);
      expect(museUwpAddedFromRaw(''), isEmpty);
      final src = File('lib/features/muse/desktop/uwp_loopback.dart').readAsStringSync();
      expect(RegExp('Timer|periodic').hasMatch(src), isFalse);
      expect(File('lib/features/muse/settings/network_page.dart').readAsStringSync(), contains('MuseUwpLoopbackTile()'));
    });
  });
}

void r19() {
  group('R19 隐藏到托盘时释放界面', () {
    test('pages released only on Windows while hidden; events follow the real window', () {
      expect(museReleasePages(windows: true, hidden: true), isTrue);
      expect(museReleasePages(windows: true, hidden: false), isFalse);
      expect(museReleasePages(windows: false, hidden: true), isFalse);
      expect(museHiddenAfterEvent('hide', false), isTrue);
      expect(museHiddenAfterEvent('show', true), isFalse);
      expect(museHiddenAfterEvent('focus', true), isFalse);
      expect(museHiddenAfterEvent('restore', true), isFalse);
      expect(museHiddenAfterEvent('moved', true), isTrue);
      expect(museHiddenAfterEvent('blur', false), isFalse);
    });

    testWidgets('hidden: the page and its animation leave the tree; shown: rebuilt', (t) async {
      var built = 0;
      final c = ProviderContainer(overrides: [museHiddenReleaseForceProvider.overrideWithValue(true)]);
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: MuseHiddenRelease(
              child: Builder(
                builder: (_) {
                  built++;
                  return const Center(child: CircularProgressIndicator(key: ValueKey('spinner')));
                },
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('spinner')), findsOneWidget);
      expect(t.binding.transientCallbackCount, greaterThan(0));
      c.read(museWindowHiddenProvider.notifier).state = true;
      await t.pump();
      expect(find.byKey(const ValueKey('spinner')), findsNothing);
      expect(find.byKey(const ValueKey('muse_pages_released')), findsOneWidget);
      expect(t.binding.transientCallbackCount, 0, reason: 'no animation ticker left running');
      c.read(museWindowHiddenProvider.notifier).state = false;
      await t.pump();
      expect(find.byKey(const ValueKey('spinner')), findsOneWidget);
      expect(built, 2);
    });

    test('wired: app builder, window hide / show / silent start, window events', () {
      expect(File('lib/features/app/widget/app.dart').readAsStringSync(), contains('MuseHiddenRelease(child: routed'));
      final w = File('lib/features/window/notifier/window_notifier.dart').readAsStringSync();
      expect('museWindowHiddenProvider.notifier).state = true'.allMatchesIn(w), 2);
      expect(w, contains('museWindowHiddenProvider.notifier).state = false'));
      expect(File('lib/features/window/widget/window_wrapper.dart').readAsStringSync(), contains('museHiddenAfterEvent(eventName'));
    });
  });
}

extension on String {
  int allMatchesIn(String s) => allMatches(s).length;
}
