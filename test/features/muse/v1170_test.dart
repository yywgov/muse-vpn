// 穿云 1.17.0 (批5) tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/settings/windows_extras.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';
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
