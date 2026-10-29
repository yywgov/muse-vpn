// 穿云 1.7.0 M3-3 (Android): 兼容内核 in its own process (:compat). The app hands over the 内核
// choice with every connect; the service is picked by it; the :compat process skips the standard
// core's set-up, never writes the app's preferences, uses the app's gRPC token and the same
// background port; its VPN service builds the TUN itself with the app outside; CI builds
// libmusecompat.so from the pinned core source and checks it is in the APK. The standard core's
// services and start path stay as they were.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_mobile.dart';

const _kt = 'android/app/src/main/kotlin/com/hiddify/hiddify';
const _compatFiles = [
  '$_kt/bg/ChuanyunProcess.kt',
  '$_kt/bg/CompatCore.kt',
  '$_kt/bg/CompatLaunch.kt',
  '$_kt/bg/CompatService.kt',
  '$_kt/bg/CompatVpnService.kt',
  '$_kt/bg/CompatProxyService.kt',
];

String _read(String p) => File(p).readAsStringSync();

/// code without comments (good enough for these files: no "//" inside strings)
String _code(String p) => _read(p)
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
    .join('\n');

/// The service element of [name] in the manifest.
String _service(String manifest, String name) {
  final i = manifest.indexOf('android:name="$name"');
  expect(i, greaterThan(0), reason: name);
  final start = manifest.lastIndexOf('<service', i);
  final end = manifest.indexOf('</service>', i);
  return manifest.substring(start, end);
}

void main() {
  group('start extras (Dart)', () {
    test('the app passes the 内核 choice and the IPv6 switch with every connect', () {
      expect(museAndroidStartExtras(kind: MuseCoreKind.standard, ipv6: false), {'coreKind': 'standard', 'ipv6': false});
      expect(museAndroidStartExtras(kind: MuseCoreKind.compat, ipv6: true), {'coreKind': 'compat', 'ipv6': true});
      // what a stored value means is decided by fromKey: unknown → standard
      expect(museAndroidStartExtras(kind: MuseCoreKind.fromKey('x'), ipv6: false)['coreKind'], 'standard');
    });

    test('both cores answer on the same background port', () {
      expect(museAndroidBackgroundPort, CoreInterfaceMobile.portBack);
      expect(_read('$_kt/bg/CompatLaunch.kt'), contains('const val GRPC_PORT_BACK = $museAndroidBackgroundPort'));
    });

    test('the connect path hands the extras over on Android only, read at connect time', () {
      final s = _read('lib/hiddifycore/hiddify_core_service.dart');
      expect(s, contains('extras: PlatformUtils.isAndroid'));
      expect(s, contains('kind: MuseCoreKind.fromKey(ref.read(MusePrefs.coreKind))'));
      expect(s, contains('ipv6: ref.read(ConfigOptions.ipv6Mode) != IPv6Mode.disable'));
      final m = _read('lib/hiddifycore/core_interface/core_interface_mobile.dart');
      expect(m, contains('...extras,'));
      final base = _read('lib/hiddifycore/core_interface/core_interface.dart');
      expect(base, contains('{Map<String, Object> extras = const {}}'));
      final handler = _read('$_kt/MethodHandler.kt');
      expect(handler, contains('(args["coreKind"] as String?)?.let { Settings.coreKindFromApp = it }'));
      expect(handler, contains('CompatLaunch.ipv6FromApp = it'));
    });
  });

  group('services', () {
    test('兼容内核 services run in :compat; the standard ones stay in the app process', () {
      final m = _read('android/app/src/main/AndroidManifest.xml');
      for (final name in ['.bg.CompatVpnService', '.bg.CompatProxyService']) {
        final s = _service(m, name);
        expect(s, contains('android:process=":compat"'), reason: name);
        expect(s, contains('android:exported="false"'), reason: name);
        expect(s, contains('android:foregroundServiceType="specialUse"'), reason: name);
      }
      expect(_service(m, '.bg.CompatVpnService'), contains('android:permission="android.permission.BIND_VPN_SERVICE"'));
      for (final name in ['.bg.VPNService', '.bg.ProxyService']) {
        expect(_service(m, name), isNot(contains('android:process')), reason: '$name unchanged');
      }
      expect(':compat'.allMatches(m).length, 2);
    });

    test('the service follows muse_core_kind, and only when the library is in the build', () {
      final s = _code('$_kt/Settings.kt');
      expect(s, contains('coreKindFromApp ?: preferences.getString(SettingsKey.CORE_KIND, "standard")'));
      expect(s, contains('coreKind == "compat" && com.hiddify.hiddify.bg.CompatLibrary.bundled'));
      expect(s, contains('ServiceMode.VPN -> if (compat) CompatVpnService::class.java else VPNService::class.java'));
      expect(s, contains('else -> if (compat) CompatProxyService::class.java else ProxyService::class.java'));
      // the bound service changes with the core too
      expect(s, contains('newMode += if (useCompatCore) "+compat" else ""'));
      expect(_read('$_kt/constant/SettingsKey.kt'), contains('CORE_KIND = "\${KEY_PREFIX}$museCoreKindPrefKey"'));
    });

    test('every start goes through serviceIntent (which hands 兼容内核 its settings)', () {
      expect(_code('$_kt/MainActivity.kt'), contains('Settings.serviceIntent(Application.application, startCore = false)'));
      expect(_code('$_kt/bg/BoxService.kt'), contains('Settings.serviceIntent(Application.application)'));
      for (final p in ['$_kt/MainActivity.kt', '$_kt/bg/BoxService.kt']) {
        expect(_code(p), isNot(contains('Intent(Application.application, Settings.serviceClass())')), reason: p);
      }
      final s = _code('$_kt/Settings.kt');
      expect(s, contains('CompatLaunch.fromSettings(startCore).putInto(intent)'));
    });

    test('asking whether the library is bundled never loads it', () {
      final s = _code('$_kt/bg/CompatCore.kt');
      final core = s.substring(s.indexOf('object CompatCore'), s.indexOf('object CompatLibrary'));
      expect(core, contains('System.loadLibrary(LIBRARY)'));
      expect(core, isNot(contains('bundled')));
      final lib = s.substring(s.indexOf('object CompatLibrary'));
      expect(lib, isNot(contains('loadLibrary')));
      expect(lib, contains('nativeLibraryDir'));
      // the JNI names in the core's jni.c: Java_com_hiddify_hiddify_bg_CompatCore_<name>, static
      expect(_read('$_kt/bg/CompatCore.kt'), startsWith('package com.hiddify.hiddify.bg'));
      for (final f in ['nativeSetup', 'nativeSetTunFd', 'nativeStop', 'nativeVersion']) {
        expect(s, contains('@JvmStatic\n    external fun $f('), reason: f);
      }
      expect(s, contains('@Keep\nobject CompatCore'));
      expect(s, contains('const val LIBRARY = "musecompat"'));
      expect(museCompatAndroidLibrary, 'libmusecompat.so');
    });
  });

  group(':compat process', () {
    test('skips the standard core and the app-process set-up', () {
      final s = _code('$_kt/Application.kt');
      final guard = s.indexOf('if (com.hiddify.hiddify.bg.ChuanyunProcess.isCompat) return');
      expect(guard, greaterThan(0));
      expect(guard, lessThan(s.indexOf('Seq.setContext(this)')));
      expect(guard, lessThan(s.indexOf('RemovedFeatures.cleanUp(this)')));
      final labels = _code('$_kt/bg/ChuanyunLabels.kt');
      expect(labels.indexOf('if (ChuanyunProcess.isCompat) return'), lessThan(labels.indexOf('Mobile.screenOn()')));
      for (final p in _compatFiles) {
        final c = _code(p);
        for (final w in ['Mobile.', 'Libbox.', 'Seq.', 'com.hiddify.core.mobile', 'com.hiddify.core.libbox']) {
          expect(c.contains(w), isFalse, reason: '$p uses $w');
        }
      }
    });

    test('never writes the app preferences; reads what it needs from the start intent', () {
      final s = _code('$_kt/Settings.kt');
      expect('preferences.edit()'.allMatches(s).length, 1, reason: 'every write goes through edit()');
      expect(s, contains('if (ChuanyunProcess.isCompat) NoopEditor else preferences.edit()'));
      for (final g in [
        'perAppMode',
        'perAppEnabled',
        'configPath',
        'profileName',
        'debug',
        'hideNotification',
        'notifyStopButton',
        'grpcPort',
        'workingDir',
        'tempDir',
        'baseDir',
      ]) {
        expect(s, contains('compatLaunch?.$g ?:'), reason: g);
      }
      final svc = _code('$_kt/bg/CompatService.kt');
      expect(svc, isNot(contains('Settings.startedByUser =')));
      expect(svc, isNot(contains('Settings.connectedSince =')));
      expect(svc, contains('Settings.compatLaunch = launch'));
    });

    test('every launch field travels in the intent and comes back out', () {
      final s = _code('$_kt/bg/CompatLaunch.kt');
      final keys = RegExp(r'const val (K_\w+) =').allMatches(s).map((m) => m.group(1)!).toList();
      expect(keys.length, 15);
      final put = s.substring(s.indexOf('fun putInto'), s.indexOf('companion object'));
      final from = s.substring(s.indexOf('fun from(intent'));
      for (final k in keys) {
        expect(put, contains('putExtra($k,'), reason: 'put $k');
        expect(from, contains('Extra($k'), reason: 'read $k');
      }
      // an intent without the app's token (a system restart) does not connect
      expect(s, contains('if (token.isEmpty()) return null'));
      expect(s, contains('token = GrpcAuth.token'));
    });

    test('the app talks to 兼容内核 with its own token', () {
      final auth = _code('$_kt/utils/GrpcAuth.kt');
      expect(auth, contains('val token: String get() = override ?: own'));
      final svc = _code('$_kt/bg/CompatService.kt');
      expect(svc, contains('GrpcAuth.override = launch.token'));
      expect(svc.indexOf('GrpcAuth.override = launch.token'), lessThan(svc.indexOf('CompatCore.nativeSetup(')));
      expect(svc, contains('"127.0.0.1:\${launch.grpcPort}", launch.token, launch.debug'));
      // the app process restarted by the system while 兼容内核 kept the connection takes its token over
      expect(svc, contains('CompatState.saveToken(launch.token)'));
      expect(auth, contains('CompatState.runningToken()?.let { return@lazy it }'));
      final state = _code('$_kt/bg/CompatLaunch.kt');
      expect(state, contains('if (file(SINCE).exists()) file(TOKEN)'), reason: 'only while that connection is up');
      final clearStarted = state.substring(state.indexOf('fun clearStarted()'), state.indexOf('fun saveToken'));
      expect(clearStarted, contains('delete(TOKEN)'));
    });

    test('the TUN descriptor reaches the core before it can start; stop releases both', () {
      final svc = _code('$_kt/bg/CompatService.kt');
      final setup = svc.indexOf('CompatCore.nativeSetup(');
      final fd = svc.indexOf('CompatCore.nativeSetTunFd(fd)');
      final started = svc.indexOf('status.postValue(Status.Started)');
      expect(setup, greaterThan(0));
      expect(fd, greaterThan(setup));
      expect(started, greaterThan(fd));
      final release = svc.substring(svc.indexOf('private fun releaseCore'));
      expect(release, contains('CompatCore.nativeStop()'));
      expect(release, contains('tun?.close()'));
      // tile / boot / shortcut start the core itself (no app around)
      expect(svc, contains('if (launch.startCore)'));
      // the library failing to load is a start failure, not a crash
      expect(svc, contains('} catch (e: Throwable) {'));
    });

    test('its VPN service builds the TUN with the app outside it', () {
      final v = _code('$_kt/bg/CompatVpnService.kt');
      expect(v, contains('.addAddress(CompatService.TUN_ADDRESS_V4, 30)'));
      expect(v, contains('.addRoute("0.0.0.0", 0)'));
      expect(v, contains('.addDnsServer(CompatService.TUN_DNS_V4)'));
      expect(v, contains('if (launch.ipv6) {'));
      expect(v, contains('builder.addDisallowedApplication(app)'));
      expect(v, contains('builder.addAllowedApplication(app)'));
      expect(v, isNot(contains('setHttpProxy')));
      final svc = _code('$_kt/bg/CompatService.kt');
      // include list: only those apps (the app itself never in it); otherwise the app is always excluded
      expect(svc, contains('val apps = list.filter { it.isNotBlank() && it != self }.distinct()'));
      expect(svc, contains('if (enabled && mode == PerAppProxyMode.INCLUDE && apps.isNotEmpty()) return apps to emptyList()'));
      expect(svc, contains('return emptyList<String>() to (excluded + self)'));
    });

    test('no background wake-ups or polling of its own', () {
      for (final p in _compatFiles) {
        final c = _code(p);
        for (final w in ['Timer(', 'Timer.', 'delay(', 'while (', 'AlarmManager', 'WorkManager', 'postDelayed']) {
          expect(c.contains(w), isFalse, reason: '$p: $w');
        }
      }
      expect(_code('$_kt/bg/CompatService.kt'), contains('return Service.START_NOT_STICKY'));
    });
  });

  group('CI and pins', () {
    test('libmusecompat.so is built from the pinned core source and must be in the APK', () {
      final props = _read('dependencies.properties');
      expect(props, contains('muse.compat.ref=a2c6e7d4ff407957302fdfb555e087dd9089b2e7'));
      final wf = _read('.github/workflows/muse-android.yml');
      expect(wf, contains('compat-core:'));
      expect(wf, contains('repository: yywgov/muse-core'));
      expect(wf, contains('needs: compat-core'));
      expect(wf, contains(r'-o "$GITHUB_WORKSPACE/out/libmusecompat.so" ./android'));
      expect(wf, contains('aarch64-linux-android21-clang'));
      expect(wf, contains('Java_com_hiddify_hiddify_bg_CompatCore_'));
      expect(wf, contains('path: android/app/src/main/jniLibs/arm64-v8a'));
      expect(wf, contains("grep -q 'lib/arm64-v8a/libmusecompat.so' /tmp/apk.txt"));
      // the APK size check stays (warn > 60 MB, fail > 80 MB)
      expect(wf, contains('83886080'));
      expect(wf, contains('62914560'));
      expect(_read('.gitignore'), contains('android/app/src/main/jniLibs/arm64-v8a/libmusecompat.so'));
      // Windows builds 兼容内核 from the same pin
      expect(_read('.github/workflows/muse-windows.yml'), contains(r'muse\.compat\.ref='));
    });
  });

  group('sources', () {
    test('new files do not name upstream projects', () {
      for (final p in _compatFiles) {
        final s = File(p)
            .readAsLinesSync()
            .where((l) => !l.startsWith('import ') && !l.startsWith('package '))
            .join('\n')
            .replaceAll('com.hiddify.', '')
            .replaceAll('Java_com_hiddify_hiddify_bg_', '')
            .toLowerCase();
        for (final w in ['flclash', 'clash', 'sing-box', 'singbox', 'mihomo']) {
          expect(s.contains(w), isFalse, reason: '$p: $w');
        }
      }
    });
  });
}
