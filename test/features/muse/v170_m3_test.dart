// 穿云 1.7.0 M3 (client): 内核 choice — default 标准内核 and nothing changes for anyone who never
// chose; device-local preference; 设置 › 内核 (switch needs the connection off, Windows offers a
// restart, Android uses it from the next connect); settings search; 320 px at 2× text.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/sync_service.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/core_kind_section.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

class _Toasts extends InAppNotificationController {
  final shown = <String>[];
  @override
  ToastificationItem? showInfoToast(String message, {ToastAction? action}) {
    shown.add(message);
    return null;
  }
}

class _Dialogs extends DialogNotifier {
  _Dialogs(this.log, this.answer);
  final List<String> log;
  final bool answer;
  @override
  Future<bool> showConfirmation({required String title, required String message, IconData? icon, String? positiveBtnTxt}) async {
    log.add('$title|$message|$positiveBtnTxt');
    return answer;
  }
}

class _Conn extends ConnectionNotifier {
  _Conn(this.status);
  final ConnectionStatus status;
  @override
  Stream<ConnectionStatus> build() => Stream.value(status);
}

Future<(ProviderContainer, _Toasts, List<String>)> _pump(
  WidgetTester t, {
  required bool desktop,
  Map<String, Object> prefs = const {},
  ConnectionStatus status = const Disconnected(),
  double width = 400,
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final toasts = _Toasts();
  final dialogs = <String>[];
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      inAppNotificationControllerProvider.overrideWithValue(toasts),
      dialogNotifierProvider.overrideWith(() => _Dialogs(dialogs, false)),
      connectionNotifierProvider.overrideWith(() => _Conn(status)),
    ],
  );
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  c.listen(connectionNotifierProvider, (_, _) {});
  t.view.physicalSize = Size(width, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 860), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: ListView(children: [MuseCoreKindSection(desktop: desktop)])),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return (c, toasts, dialogs);
}

void main() {
  tearDown(() => MuseCoreSelection.init(null));

  group('core kind logic', () {
    test('missing / unknown values are 标准内核 (nothing changes for anyone who never chose)', () {
      expect(MuseCoreKind.fromKey(null), MuseCoreKind.standard);
      expect(MuseCoreKind.fromKey(''), MuseCoreKind.standard);
      expect(MuseCoreKind.fromKey('standard'), MuseCoreKind.standard);
      expect(MuseCoreKind.fromKey('weird'), MuseCoreKind.standard);
      expect(MuseCoreKind.fromKey(1), MuseCoreKind.standard);
      expect(MuseCoreKind.fromKey('compat'), MuseCoreKind.compat);
      for (final k in MuseCoreKind.values) {
        expect(MuseCoreKind.fromKey(k.key), k);
      }
    });

    test('the start-up selection is read once and defaults to 标准内核', () {
      expect(MuseCoreSelection.startup, MuseCoreKind.standard);
      MuseCoreSelection.init('compat');
      expect(MuseCoreSelection.startup, MuseCoreKind.compat);
      MuseCoreSelection.init(null);
      expect(MuseCoreSelection.startup, MuseCoreKind.standard);
    });

    test('switch steps: same / connected / Windows / Android', () {
      MuseCoreSwitchStep step(MuseCoreKind cur, MuseCoreKind p, {bool off = true, bool desktop = true}) =>
          museCoreSwitchStep(current: cur, picked: p, disconnected: off, desktop: desktop);
      const s = MuseCoreKind.standard;
      const x = MuseCoreKind.compat;
      expect(step(s, s), MuseCoreSwitchStep.none);
      expect(step(s, s, off: false), MuseCoreSwitchStep.none);
      expect(step(s, x, off: false), MuseCoreSwitchStep.disconnectFirst);
      expect(step(x, s, off: false, desktop: false), MuseCoreSwitchStep.disconnectFirst);
      expect(step(s, x), MuseCoreSwitchStep.restartApp);
      expect(step(x, s), MuseCoreSwitchStep.restartApp);
      expect(step(s, x, desktop: false), MuseCoreSwitchStep.nextConnect);
    });

    test('重启后生效 only on desktop and only when the saved choice differs from the loaded core', () {
      const s = MuseCoreKind.standard;
      const x = MuseCoreKind.compat;
      expect(museCoreRestartPending(saved: x, running: s, desktop: true), isTrue);
      expect(museCoreRestartPending(saved: s, running: s, desktop: true), isFalse);
      expect(museCoreRestartPending(saved: x, running: s, desktop: false), isFalse);
    });

    test('the choice stays on this device: not synced, not backed up', () {
      expect(museSyncedPrefKeys, isNot(contains(museCoreKindPrefKey)));
      expect(museSyncedPrefs.keys, isNot(contains(museCoreKindPrefKey)));
    });

    test('preference default is 标准内核', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
      addTearDown(c.dispose);
      await c.read(sharedPreferencesProvider.future);
      expect(c.read(MusePrefs.coreKind), 'standard');
      expect(MuseCoreKind.fromKey(c.read(MusePrefs.coreKind)), MuseCoreKind.standard);
    });

    test('versions: 标准内核 = the release in dependencies.properties, 兼容内核 = the pinned engine', () {
      expect(museCoreKindVersion(MuseCoreKind.standard), museCoreRelease);
      expect(museCoreKindVersion(MuseCoreKind.compat), museCompatEngineVersion);
    });

    test('settings search finds 内核', () {
      final hits = museSearchSettings('内核', android: true, windows: false).map((e) => e.title).toList();
      expect(hits, contains('内核'));
      expect(museSearchSettings('兼容内核', android: false, windows: true).map((e) => e.title), contains('内核'));
    });
  });

  group('设置 › 内核', () {
    testWidgets('default: 标准内核 and its version, no restart note', (t) async {
      await _pump(t, desktop: true);
      expect(find.text('内核'), findsWidgets);
      expect(find.text('标准内核'), findsOneWidget);
      expect(find.text(museCoreRelease), findsOneWidget);
      expect(find.textContaining('重启应用后生效'), findsNothing);
    });

    testWidgets('Android, disconnected: picking 兼容内核 saves it, used from the next connect', (t) async {
      final (c, toasts, dialogs) = await _pump(t, desktop: false);
      await t.tap(find.byKey(const ValueKey('core_kind')));
      await t.pumpAndSettle();
      expect(find.text('兼容内核'), findsOneWidget);
      expect(find.textContaining(museCompatEngineVersion), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('core_kind_compat')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.coreKind), 'compat');
      expect(toasts.shown, ['下次连接时使用兼容内核']);
      expect(dialogs, isEmpty);
      expect(find.text('兼容内核'), findsOneWidget);
      expect(find.text(museCompatEngineVersion), findsOneWidget, reason: 'Android runs the chosen core from the next connect');
    });

    testWidgets('connected: nothing is saved, asks to disconnect first', (t) async {
      final (c, toasts, dialogs) = await _pump(t, desktop: true, status: const Connected());
      await t.tap(find.byKey(const ValueKey('core_kind')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('core_kind_compat')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.coreKind), 'standard');
      expect(toasts.shown, ['请先断开连接，再切换内核']);
      expect(dialogs, isEmpty);
    });

    testWidgets('Windows: saved, restart offered; until then 已选…重启应用后生效 and the loaded version', (t) async {
      final (c, toasts, dialogs) = await _pump(t, desktop: true);
      await t.tap(find.byKey(const ValueKey('core_kind')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('core_kind_compat')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.coreKind), 'compat');
      expect(dialogs, ['重启应用后生效|切换到兼容内核需要重新打开穿云。|立即重启']);
      expect(toasts.shown, isEmpty);
      expect(find.text('已选兼容内核，重启应用后生效'), findsOneWidget);
      expect(find.text(museCoreRelease), findsOneWidget, reason: 'this run still uses 标准内核');
    });

    testWidgets('Windows: back to the loaded core needs no restart', (t) async {
      final (c, _, dialogs) = await _pump(t, desktop: true, prefs: {'flutter.$museCoreKindPrefKey': 'compat'});
      expect(find.text('已选兼容内核，重启应用后生效'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('core_kind')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('core_kind_standard')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.coreKind), 'standard');
      expect(dialogs, isEmpty);
      expect(find.textContaining('重启应用后生效'), findsNothing);
    });

    testWidgets('320 px wide at 2× text: no overflow', (t) async {
      await _pump(t, desktop: true, width: 320, textScale: 2, prefs: {'flutter.$museCoreKindPrefKey': 'compat'});
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('core_kind')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('sources', () {
    test('new files do not name upstream projects', () {
      for (final p in [
        'lib/features/muse/logic/core_kind.dart',
        'lib/features/muse/settings/core_kind_section.dart',
      ]) {
        final s = File(p).readAsLinesSync().where((l) => !l.startsWith('import ')).join('\n').toLowerCase();
        for (final w in ['flclash', 'clash', 'hiddify', 'sing-box', 'singbox', 'mihomo']) {
          expect(s.contains(w), isFalse, reason: '$p: $w');
        }
      }
    });

    test('the settings page shows 内核 on Windows and Android', () {
      final s = File('lib/features/settings/overview/settings_page.dart').readAsStringSync();
      expect(s, contains('if (PlatformUtils.isWindows || android) const MuseCoreKindSection()'));
    });
  });
}
