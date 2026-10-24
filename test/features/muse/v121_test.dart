// 穿云 1.2.1 unit tests: latency colours, group icons/subtitles, per-app count, removed features
// (按网络自动开关, 我的宽带) and their upgrade migration.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/preferences_migration.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/logic/latency.dart';
import 'package:hiddify/features/muse/settings/per_app_proxy_page.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Dirs extends AppDirectories {
  _Dirs(this.dir);
  final Directory dir;
  @override
  Future<Directories> build() async => (baseDir: dir, workingDir: dir, tempDir: dir);
}

void main() {
  group('latency colours (one rule everywhere)', () {
    test('boundaries 299 / 300 / 600 / 601 / timeout', () {
      expect(museLatencyLevel(1), MuseLatencyLevel.good);
      expect(museLatencyLevel(226), MuseLatencyLevel.good); // was red in 1.2.0
      expect(museLatencyLevel(299), MuseLatencyLevel.good);
      expect(museLatencyLevel(300), MuseLatencyLevel.fair);
      expect(museLatencyLevel(600), MuseLatencyLevel.fair);
      expect(museLatencyLevel(601), MuseLatencyLevel.bad);
      expect(museLatencyLevel(65535), MuseLatencyLevel.bad); // timeout
      expect(museLatencyLevel(-1), MuseLatencyLevel.bad);
      expect(museLatencyLevel(0), MuseLatencyLevel.unknown); // not tested yet
    });
    test('the old 100/200 ms thresholds are gone', () {
      final src = File('lib/features/muse/widget/grouped_list.dart').readAsStringSync();
      expect(src, isNot(contains('delay < 100')));
      expect(src, contains('museLatencyLevel(delay)'));
    });
  });

  group('groups on the 首页', () {
    test('负载均衡 has its own icon, 自动最快 keeps the lightning', () {
      expect(museGroupIconKind(type: 'Balancer', name: 'balance', selectedDisplay: 'round-robin'), MuseGroupIcon.loadBalance);
      expect(museGroupIconKind(type: 'Balancer', name: 'lowest', selectedDisplay: 'PPFlight-Direct'), MuseGroupIcon.autoFastest);
      expect(museGroupIconKind(type: 'URLTest', name: 'auto'), MuseGroupIcon.autoFastest);
      expect(museGroupIconKind(type: 'Selector', name: 'select'), MuseGroupIcon.manual);
      final home = File('lib/features/muse/nodes/node_list.dart').readAsStringSync();
      // 1.5.0: one line-icon set (outlined)
      expect(home, contains('MuseGroupIcon.loadBalance => Icons.balance_outlined'));
    });
    test('负载均衡 subtitle no longer repeats its name', () {
      final s = museGroupSubtitle(type: 'Balancer', name: 'balance', selectedDisplay: 'round-robin', nodeCount: 23);
      expect(s, '23 个节点');
      expect(s, isNot(contains('负载均衡')));
    });
    test('node rows keep the protocol name', () {
      final home = File('lib/features/muse/nodes/node_list.dart').readAsStringSync();
      expect(home, contains('museProtocolShort(proxy.type)')); // 1.5.3: as a small tag
    });
  });

  group('status / navigation bar icons', () {
    test('dark icons on the light theme, light icons on dark / true black', () {
      final light = museSystemOverlayStyle(Brightness.light);
      expect(light.statusBarIconBrightness, Brightness.dark);
      expect(light.systemNavigationBarIconBrightness, Brightness.dark);
      final dark = museSystemOverlayStyle(Brightness.dark);
      expect(dark.statusBarIconBrightness, Brightness.light);
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    });
    test('every app bar uses it (no guess from a transparent background)', () {
      final theme = AppTheme(AppThemeMode.light, '');
      expect(theme.lightTheme(null).appBarTheme.systemOverlayStyle?.statusBarIconBrightness, Brightness.dark);
      expect(AppTheme(AppThemeMode.black, '').darkTheme(null).appBarTheme.systemOverlayStyle?.statusBarIconBrightness, Brightness.light);
      expect(theme.lightTheme(null).dialogTheme.barrierColor, museLightScrim);
      final scaffold = File('lib/features/muse/widget/grouped_list.dart').readAsStringSync();
      expect(scaffold, contains('systemOverlayStyle: museSystemOverlayStyle(Theme.of(context).brightness)'));
    });
  });

  test('分应用代理 shows the total', () {
    expect(museAppCountLabel(23), '共 23 个 App');
    final src = File('lib/features/muse/settings/per_app_proxy_page.dart').readAsStringSync();
    expect(src, isNot(contains('moreApps(')));
    expect(src, isNot(contains('Icons.sync_rounded')));
  });

  group('按网络自动开关 removed', () {
    test('no page, no Android code, no location / Wi-Fi permission', () {
      expect(File('lib/features/muse/settings/network_auto_page.dart').existsSync(), isFalse);
      expect(File('android/app/src/main/kotlin/com/hiddify/hiddify/bg/NetworkAuto.kt').existsSync(), isFalse);
      expect(File('android/app/src/main/kotlin/com/hiddify/hiddify/bg/NetworkChangeReceiver.kt').existsSync(), isFalse);
      expect(File('lib/features/settings/overview/settings_page.dart').readAsStringSync(), isNot(contains('按网络自动开关')));
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, isNot(contains('NetworkChangeReceiver')));
      for (final p in ['ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION', 'ACCESS_BACKGROUND_LOCATION', 'ACCESS_WIFI_STATE', 'NEARBY_WIFI_DEVICES']) {
        final line = manifest.split('\n').firstWhere((l) => l.contains('permission.$p'), orElse: () => '');
        expect(line, contains('tools:node="remove"'), reason: p);
      }
    });
    test('the Android side cleans up what 1.2.0 left behind', () {
      final app = File('android/app/src/main/kotlin/com/hiddify/hiddify/Application.kt').readAsStringSync();
      expect(app, contains('RemovedFeatures.cleanUp(this)'));
      final clean = File('android/app/src/main/kotlin/com/hiddify/hiddify/bg/RemovedFeatures.kt').readAsStringSync();
      expect(clean, contains('unregisterNetworkCallback(pi)'));
      expect(clean, contains('com.hiddify.hiddify.bg.NetworkChangeReceiver'));
      expect(clean, contains('NET_AUTO_ENABLED'));
    });
  });

  group('upgrade from 1.2.0', () {
    test('migration deletes the 按网络自动开关 and 我的宽带 prefs', () async {
      SharedPreferences.setMockInitialValues({
        'preferences_version': 4,
        'net_auto_enabled': true,
        'net_trusted_ssids': 'gonghui',
        'net_auto_paused': true,
        'hysteria2-up-mbps': 100,
        'hysteria2-down-mbps': 500,
        'theme_mode': 'black',
      });
      final prefs = await SharedPreferences.getInstance();
      await PreferencesMigration(sharedPreferences: prefs).migrate();
      for (final k in MuseRemovedFeaturesV121Migration.removedKeys) {
        expect(prefs.containsKey(k), isFalse, reason: k);
      }
      expect(prefs.getString('theme_mode'), 'black'); // other settings untouched
      expect(prefs.getInt('preferences_version'), 5);
    });

    test('a stored 「我的宽带」 value never reaches the generated config', () async {
      SharedPreferences.setMockInitialValues({'hysteria2-up-mbps': 100, 'hysteria2-down-mbps': 500});
      final prefs = await SharedPreferences.getInstance();
      final dir = Directory.systemTemp.createTempSync('muse121');
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => prefs),
          appDirectoriesProvider.overrideWith(() => _Dirs(dir)),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sharedPreferencesProvider.future);
      await c.read(appDirectoriesProvider.future);
      // keep the providers alive until their start-up microtasks (rules list) are done
      final sub = c.listen(ConfigOptions.singboxConfigOptions, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final json = jsonEncode(sub.read().toJson());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(json, contains('direct-dns-address')); // it is the real config
      expect(json, isNot(contains('hysteria2')));
      expect(json, isNot(contains('mbps')));
    });
  });
}
