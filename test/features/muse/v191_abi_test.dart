// 穿云 1.9.1: Android packages for 32-bit ARM and x86_64 next to arm64 — the CI builds one
// 兼容内核 library and one APK per architecture, and the in-app updater takes the file that matches
// the architecture the app runs as.
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';

String _read(String p) => File(p).readAsStringSync();

Map<String, dynamic> _release(List<String> names) => {
  'tag_name': 'v1.9.1',
  'html_url': 'https://github.com/yywgov/muse-vpn/releases/tag/v1.9.1',
  'assets': [
    for (final n in names)
      {'name': n, 'browser_download_url': '${museReleaseDownloadPrefix}v1.9.1/$n', 'size': 7},
  ],
};

void main() {
  const all = [
    'Chuanyun-Android-arm64.apk',
    'Chuanyun-Android-arm64.apk.sha256',
    'Chuanyun-Android-armeabi-v7a.apk',
    'Chuanyun-Android-armeabi-v7a.apk.sha256',
    'Chuanyun-Android-x86_64.apk',
    'Chuanyun-Android-x86_64.apk.sha256',
  ];

  group('updater picks the package of the running architecture', () {
    test('asset names', () {
      expect(museApkAssetFor(Abi.androidArm64), 'Chuanyun-Android-arm64.apk');
      expect(museApkAssetFor(Abi.androidArm), 'Chuanyun-Android-armeabi-v7a.apk');
      expect(museApkAssetFor(Abi.androidX64), 'Chuanyun-Android-x86_64.apk');
      // anything else (desktop test host) keeps the arm64 name
      expect(museApkAssetFor(Abi.linuxX64), museApkAssetName);
    });

    test('each architecture gets its own file', () {
      final arm64 = museParseRelease(_release(all));
      expect(arm64!.apkUrl, endsWith('/Chuanyun-Android-arm64.apk'));
      final v7a = museParseRelease(_release(all), apkAsset: museApkAssetFor(Abi.androidArm));
      expect(v7a!.apkUrl, endsWith('/Chuanyun-Android-armeabi-v7a.apk'));
      final x64 = museParseRelease(_release(all), apkAsset: museApkAssetFor(Abi.androidX64));
      expect(x64!.apkUrl, endsWith('/Chuanyun-Android-x86_64.apk'));
    });

    test('a release without the package of this architecture offers nothing (never the arm64 file)', () {
      final old = _release(['Chuanyun-Android-arm64.apk']);
      expect(museParseRelease(old, apkAsset: museApkAssetFor(Abi.androidArm)), isNull);
      expect(museParseRelease(old, apkAsset: museApkAssetFor(Abi.androidX64)), isNull);
      expect(museParseRelease(old), isNotNull);
    });

    test('the updater asks for the running architecture', () {
      final u = _read('lib/features/muse/update/muse_updater.dart');
      expect(u, contains('museApkAssetFor(Abi.current())'));
      expect(u, isNot(contains('windows: windows)'))); // every call passes the asset
    });
  });

  group('CI builds one package per architecture', () {
    test('兼容内核 library matrix', () {
      final wf = _read('.github/workflows/muse-android.yml');
      for (final cc in ['aarch64-linux-android21-clang', 'armv7a-linux-androideabi21-clang', 'x86_64-linux-android21-clang']) {
        expect(wf, contains(cc));
      }
      expect(wf, contains("goarm: '7'"));
      expect(wf, contains(r'GOARCH=${{ matrix.goarch }}'));
      expect(wf, contains('name: muse-compat-android-\${{ matrix.abi }}'));
    });

    test('three APKs are collected, checksummed and released', () {
      final wf = _read('.github/workflows/muse-android.yml');
      for (final n in ['arm64', 'armeabi-v7a', 'x86_64']) {
        expect(wf, contains('out/Chuanyun-Android-$n.apk\n'));
        expect(wf, contains('out/Chuanyun-Android-$n.apk.sha256'));
      }
      expect(wf, contains('ANDROID_PLATFORM=android-arm\n'));
      expect(wf, contains('ANDROID_PLATFORM=android-x64\n'));
      expect(wf, contains('MUSE_ABI: armeabi-v7a'));
      expect(wf, contains('MUSE_ABI: x86_64'));
      // the arm64 package is collected before the others replace the build output
      expect(wf.indexOf('Collect APK (arm64-v8a)'), lessThan(wf.indexOf('Build + collect APK (armeabi-v7a)')));
    });

    test('each build only carries its own native libraries', () {
      final g = _read('android/app/build.gradle');
      expect(g, contains('System.getenv("MUSE_ABI")'));
      expect(g, contains('"arm64-v8a"'));
      final m = _read('Makefile');
      expect(m, contains('ANDROID_PLATFORM ?= android-arm64'));
      expect(m, contains(r'--build-target-platform=$(ANDROID_PLATFORM)'));
      final c = _read('tool/ci/collect_apk.sh');
      expect(c, contains(r'lib/$abi/libhiddify-core.so'));
      expect(c, contains('83886080')); // 80 MB hard limit per package
      final ig = _read('.gitignore');
      expect(ig, contains('jniLibs/armeabi-v7a/libmusecompat.so'));
      expect(ig, contains('jniLibs/x86_64/libmusecompat.so'));
    });

    test('signing, application id and icons untouched', () {
      final g = _read('android/app/build.gradle');
      expect(g, contains('chuanyun-release.p12'));
      expect(g, contains("applicationId"));
    });
  });
}
