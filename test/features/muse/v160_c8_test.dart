// 穿云 1.6.0 C8 Windows: tray menu (系统代理/TUN, 开机自启, 复制终端代理命令, 节点 30 + 更多…),
// global hotkeys (validation, registration, recorder), 按需运行 (netsh parsing, pause/resume and the
// user's manual choice), 开机自启时静默, title bar (46×32 buttons, drag / double-click / pin).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/wifi_ssid.dart';
import 'package:hiddify/features/muse/desktop/desktop_actions.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/desktop/title_bar.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/proxy_env.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/settings/windows_extras.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _k = 0x0007000e; // K
const _c = 0x00070006; // C

Future<ProviderContainer> _container(Map<String, Object> prefs, {List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp), ...overrides]);
  await c.read(sharedPreferencesProvider.future);
  return c;
}

Future<ProviderContainer> _pump(
  WidgetTester t,
  Widget home, {
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp), ...overrides]);
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  t.view.physicalSize = const Size(900, 680);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: ThemeData(colorScheme: museSeededScheme(brightness: Brightness.light)),
        home: home,
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return c;
}

/// the `tray menu:` line the smoke test reads (same format as SystemTrayNotifier._trayMenu)
String _logLine(List<MuseTrayItem> spec) =>
    "tray menu: ${spec.where((e) => e.key != 'speed').map((e) => e.key == '-' ? '|' : '${e.label}${e.checked ? '*' : ''}').join(' ')}";

/// the app_smoke.ps1 tray-menu check: the five words in order
bool _smokeOrder(String line) {
  var pos = 0;
  for (final w in ['连接', '规则', '全局', '显示窗口', '退出']) {
    final i = line.indexOf(w, pos);
    if (i < 0) return false;
    pos = i + w.length;
  }
  return true;
}

class _FakeBackend implements MuseHotkeyBackend {
  final applied = <Map<MuseHotkeyAction, MuseHotkey>>[];
  void Function(MuseHotkeyAction)? handler;

  @override
  Future<void> apply(
    Map<MuseHotkeyAction, MuseHotkey> bindings,
    void Function(MuseHotkeyAction action) onPressed,
  ) async {
    applied.add(Map.of(bindings));
    handler = onPressed;
  }
}

class _FakeOps implements MuseWindowOps {
  final calls = <String>[];
  bool max = false;

  @override
  Future<void> close() async => calls.add('close');
  @override
  Future<bool> isMaximized() async => max;
  @override
  Future<void> maximize() async {
    max = true;
    calls.add('maximize');
  }

  @override
  Future<void> minimize() async => calls.add('minimize');
  @override
  Future<void> setAlwaysOnTop(bool on) async => calls.add('top:$on');
  @override
  Future<void> startDragging() async => calls.add('drag');
  @override
  Future<void> unmaximize() async {
    max = false;
    calls.add('unmaximize');
  }
}

void main() {
  group('C8 托盘', () {
    test('Windows menu: new items between 全局 and 显示窗口, smoke order kept', () {
      for (final conn in const <ConnectionStatus>[Disconnected(), Connected()]) {
        final spec = museTrayMenuSpec(
          conn,
          MuseRouteMode.rule,
          nodes: const [MuseTrayNode('a', 'A', selected: true)],
          serviceMode: ServiceMode.systemProxy,
          autoStart: true,
          copyEnv: true,
        );
        final labels = spec.where((e) => e.key != '-').map((e) => e.label).toList();
        expect(labels.first, conn is Connected ? '断开' : '连接');
        expect(labels.sublist(labels.length - 6), ['系统代理', 'TUN 模式', '开机自启', '复制终端代理命令', '显示窗口', '退出']);
        expect(labels.indexOf('全局'), lessThan(labels.indexOf('系统代理')));
        if (conn is Connected) expect(labels.indexOf('节点'), lessThan(labels.indexOf('系统代理')));
        // the line the Windows smoke test checks (disconnected: first item is 连接)
        final line = _logLine(spec);
        if (conn is Disconnected) expect(_smokeOrder(line), isTrue, reason: line);
        // no two separators in a row, none at the end
        for (var i = 1; i < spec.length; i++) {
          expect(spec[i].key == '-' && spec[i - 1].key == '-', isFalse);
        }
        expect(spec.last.key, 'quit');
      }
    });

    test('checks follow 运行模式 / 开机自启; copy submenu has three terminals', () {
      final spec = museTrayMenuSpec(
        const Disconnected(),
        MuseRouteMode.global,
        serviceMode: ServiceMode.tun,
        autoStart: false,
        copyEnv: true,
      );
      expect(spec.firstWhere((e) => e.key == 'svc:tun').checked, isTrue);
      expect(spec.firstWhere((e) => e.key == 'svc:proxy').checked, isFalse);
      expect(spec.firstWhere((e) => e.key == 'autostart').checked, isFalse);
      expect(spec.firstWhere((e) => e.key == 'env').children.map((e) => e.key), [
        'env:cmd',
        'env:powershell',
        'env:bash',
      ]);
      expect(spec.firstWhere((e) => e.key == 'svc:proxy').checkable, isTrue);
    });

    test('without the Windows values the menu is the old five items', () {
      final spec = museTrayMenuSpec(const Disconnected(), MuseRouteMode.rule);
      expect(spec.where((e) => e.key != '-').map((e) => e.label), ['连接', '规则', '全局', '显示窗口', '退出']);
    });

    test('节点 submenu: at most 30, 更多… when the group has more', () {
      expect(museTrayMaxNodes, 30);
      final items = [for (var i = 0; i < 80; i++) (tag: 'n$i', name: 'N$i', delay: 100 + i)];
      final nodes = museTrayNodes(items, selected: 'n3');
      expect(nodes.length, 30);
      final spec = museTrayMenuSpec(const Connected(), MuseRouteMode.rule, nodes: nodes, moreNodes: true);
      final sub = spec.firstWhere((e) => e.key == 'nodes').children;
      expect(sub.where((e) => e.key.startsWith('node:')).length, 30);
      expect(sub.map((e) => e.key), containsAllInOrder(['nodes:more', 'urltest']));
      expect(sub.firstWhere((e) => e.key == 'nodes:more').label, '更多…');
      final few = museTrayMenuSpec(const Connected(), MuseRouteMode.rule, nodes: nodes.take(3).toList());
      expect(few.firstWhere((e) => e.key == 'nodes').children.any((e) => e.key == 'nodes:more'), isFalse);
    });

    test('tray handler routes the new keys through the shared actions (source)', () {
      final src = File('lib/features/system_tray/notifier/system_tray_notifier.dart').readAsStringSync();
      for (final k in ["'svc:proxy'", "'svc:tun'", "'autostart'", "'env:'", "'nodes:more'"]) {
        expect(src, contains(k));
      }
      expect(src, contains('museRunDesktopAction('));
      // tray / hotkeys never change the connection state directly
      final actions = File('lib/features/muse/desktop/desktop_actions.dart').readAsStringSync();
      expect(actions, contains('toggleConnection()'));
      expect(actions.contains('state ='), isFalse);
    });
  });

  group('C8 复制终端代理命令', () {
    test('three formats on the mixed port', () {
      expect(
        museProxyEnvCommand(MuseShellKind.cmd, 2334),
        'set http_proxy=http://127.0.0.1:2334 & set https_proxy=http://127.0.0.1:2334 & set no_proxy=localhost,127.0.0.1,::1',
      );
      expect(
        museProxyEnvCommand(MuseShellKind.powershell, 7890),
        r'$env:http_proxy="http://127.0.0.1:7890"; $env:https_proxy="http://127.0.0.1:7890"; $env:no_proxy="localhost,127.0.0.1,::1"',
      );
      expect(
        museProxyEnvCommand(MuseShellKind.bash, 1080),
        'export http_proxy=http://127.0.0.1:1080 https_proxy=http://127.0.0.1:1080 no_proxy=localhost,127.0.0.1,::1',
      );
      expect(MuseShellKind.fromKey('cmd'), MuseShellKind.cmd);
      expect(MuseShellKind.fromKey('nope'), MuseShellKind.powershell);
      expect(museOtherRouteMode(MuseRouteMode.rule), MuseRouteMode.global);
      expect(museOtherRouteMode(MuseRouteMode.global), MuseRouteMode.rule);
    });
  });

  group('C8 快捷键', () {
    test('raw round trip and labels', () {
      const k = MuseHotkey(ctrl: true, alt: true, usage: _k);
      expect(k.toRaw(), 'ctrl+alt+0x7000e');
      expect(MuseHotkey.parse(k.toRaw()), k);
      expect(k.label, 'Ctrl + Alt + K');
      expect(const MuseHotkey(win: true, shift: true, usage: 0x0007003b).label, 'Shift + Win + F2');
      expect(MuseHotkey.parse('ctrl+hyper+0x7000e'), isNull);
      expect(MuseHotkey.parse('ctrl+zz'), isNull);
      final map = {
        MuseHotkeyAction.toggleConnection: k,
        MuseHotkeyAction.quit: const MuseHotkey(ctrl: true, shift: true, usage: 0x00070014),
      };
      expect(museParseHotkeys(museHotkeysToRaw(map)), map);
      expect(museParseHotkeys('{"connection":"ctrl+alt+0x7000e","bogus":"ctrl+0x70004","quit":"x"}').keys, [
        MuseHotkeyAction.toggleConnection,
      ]);
      expect(museParseHotkeys('not json'), isEmpty);
      expect(museHotkeysToRaw(const {}), '');
    });

    test('validation: modifier required, reserved, conflicts, unsupported keys', () {
      const a = MuseHotkeyAction.toggleConnection;
      expect(museHotkeyProblem(const MuseHotkey(usage: _k), a, const {}), contains('Ctrl、Alt 或 Win'));
      expect(museHotkeyProblem(const MuseHotkey(shift: true, usage: _k), a, const {}), contains('Ctrl、Alt 或 Win'));
      expect(museHotkeyProblem(const MuseHotkey(ctrl: true, usage: _c), a, const {}), contains('常用快捷键'));
      expect(
        museHotkeyProblem(MuseHotkey(alt: true, usage: PhysicalKeyboardKey.f4.usbHidUsage), a, const {}),
        isNotNull,
      );
      expect(
        museHotkeyProblem(MuseHotkey(ctrl: true, usage: PhysicalKeyboardKey.audioVolumeUp.usbHidUsage), a, const {}),
        contains('不支持'),
      );
      const ok = MuseHotkey(ctrl: true, alt: true, usage: _k);
      expect(museHotkeyProblem(ok, a, const {}), isNull);
      expect(museHotkeyProblem(ok, a, const {MuseHotkeyAction.quit: ok}), '已被「退出」使用');
      // re-saving the same key on the same action is fine
      expect(museHotkeyProblem(ok, a, const {a: ok}), isNull);
    });

    test('from key events: modifiers alone make nothing', () {
      expect(museHotkeyFromEvent(PhysicalKeyboardKey.controlLeft, {PhysicalKeyboardKey.controlLeft}), isNull);
      final k = museHotkeyFromEvent(PhysicalKeyboardKey.keyK, {
        PhysicalKeyboardKey.controlRight,
        PhysicalKeyboardKey.altLeft,
        PhysicalKeyboardKey.keyK,
      });
      expect(k, const MuseHotkey(ctrl: true, alt: true, usage: _k));
    });

    test('provider registers the bindings; off / recording release them', () async {
      final backend = _FakeBackend();
      final pressed = <MuseHotkeyAction>[];
      const k = MuseHotkey(ctrl: true, alt: true, usage: _k);
      final c = await _container(
        {
          'muse_hotkeys': museHotkeysToRaw(const {MuseHotkeyAction.toggleMode: k}),
        },
        overrides: [
          museHotkeysForceProvider.overrideWithValue(true),
          museHotkeyBackendProvider.overrideWithValue(backend),
          museHotkeyHandlerProvider.overrideWithValue(pressed.add),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(museHotkeysProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      expect(backend.applied.last, {MuseHotkeyAction.toggleMode: k});
      backend.handler!(MuseHotkeyAction.toggleMode);
      expect(pressed, [MuseHotkeyAction.toggleMode]);

      c.read(museHotkeyRecordingProvider.notifier).state = true;
      c.read(museHotkeysProvider);
      await Future<void>.delayed(Duration.zero);
      expect(backend.applied.last, isEmpty);
      c.read(museHotkeyRecordingProvider.notifier).state = false;
      c.read(museHotkeysProvider);
      await Future<void>.delayed(Duration.zero);
      expect(backend.applied.last, isNotEmpty);

      await c.read(MusePrefs.hotkeysOn.notifier).update(false);
      c.read(museHotkeysProvider);
      await Future<void>.delayed(Duration.zero);
      expect(backend.applied.last, isEmpty);
      expect(museActiveHotkeys(on: true, recording: false, raw: ''), isEmpty);
    });

    test('nothing bound by default; every action maps to a desktop action', () async {
      final c = await _container({});
      addTearDown(c.dispose);
      expect(c.read(MusePrefs.hotkeys), '');
      expect(c.read(MusePrefs.hotkeysOn), isTrue);
      expect({for (final a in MuseHotkeyAction.values) a.desktopAction}.length, MuseHotkeyAction.values.length);
      expect(MuseHotkeyAction.showWindow.desktopAction, MuseDesktopAction.toggleWindow);
    });

    testWidgets('recorder: Ctrl+Alt+K saved; Ctrl+C refused; clear', (t) async {
      final c = await _pump(t, const MuseHotkeysPage());
      expect(find.text('未设置'), findsNWidgets(MuseHotkeyAction.values.length));
      await t.tap(find.byKey(const ValueKey('hotkey_connection')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hotkey_recorder')), findsOneWidget);
      expect(c.read(museHotkeyRecordingProvider), isTrue);

      await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await simulateKeyDownEvent(LogicalKeyboardKey.keyC);
      await t.pump();
      expect(find.byKey(const ValueKey('hotkey_recorder_problem')), findsOneWidget);
      await simulateKeyUpEvent(LogicalKeyboardKey.keyC);
      await simulateKeyDownEvent(LogicalKeyboardKey.altLeft);
      await simulateKeyDownEvent(LogicalKeyboardKey.keyK);
      await t.pump();
      expect(find.text('Ctrl + Alt + K'), findsOneWidget);
      expect(find.byKey(const ValueKey('hotkey_recorder_problem')), findsNothing);
      await simulateKeyUpEvent(LogicalKeyboardKey.keyK);
      await simulateKeyUpEvent(LogicalKeyboardKey.altLeft);
      await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.tap(find.byKey(const ValueKey('hotkey_save')));
      await t.pumpAndSettle();
      expect(
        museParseHotkeys(c.read(MusePrefs.hotkeys))[MuseHotkeyAction.toggleConnection],
        const MuseHotkey(ctrl: true, alt: true, usage: _k),
      );
      expect(c.read(museHotkeyRecordingProvider), isFalse);
      expect(find.text('Ctrl + Alt + K'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('hotkey_connection')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('hotkey_clear')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.hotkeys), '');
    });
  });

  group('C8 按需运行', () {
    const en = '''
There is 1 interface on the system:

    Name                   : Wi-Fi
    Description            : Intel(R) Wi-Fi 6 AX201 160MHz
    GUID                   : 1b2c
    Physical address       : aa:bb:cc:dd:ee:ff
    State                  : connected
    SSID                   : Home 5G
    BSSID                  : 11:22:33:44:55:66
    Network type           : Infrastructure
''';
    const zh = '''
系统上有 1 个接口:

    名称                   : WLAN
    描述                   : Realtek 8822CE
    状态                   : 已连接
    SSID                   : 公司网络
    AP BSSID               : 11:22:33:44:55:66
''';
    const off = '''
There is 1 interface on the system:

    Name                   : Wi-Fi
    State                  : disconnected
''';

    test('netsh parsing (English / Chinese / off / failures)', () {
      expect(museParseNetshInterfaces(en).ssid, 'Home 5G');
      expect(museParseNetshInterfaces(zh).ssid, '公司网络');
      final o = museParseNetshInterfaces(off);
      expect((o.ok, o.ssid), (true, null));
      expect(museParseNetshInterfaces('There is no wireless interface on the system.').ok, isTrue);
      final loc = museParseNetshInterfaces(
        'Network shell commands need location permission to access WLAN information. ms-settings:privacy-location',
      );
      expect(loc.ok, isFalse);
      expect(loc.hint, museWifiLocationHint);
      expect(museParseNetshInterfaces('The Wireless AutoConfig Service (wlansvc) is not running.').ok, isFalse);
    });

    test('Wi‑Fi list kept in the existing rules (other rules untouched)', () {
      const raw = '{"Cafe":"connect","Home":"disconnect"}';
      expect(museOnDemandSsids(raw), ['Home']);
      final next = museOnDemandWithSsids(raw, ['Home', 'Office', ' ']);
      expect(museOnDemandSsids(next), ['Home', 'Office']);
      expect(museParseWifiRules(next)['Cafe'], MuseWifiAction.connect);
      expect(museOnDemandWithSsids('', []), '');
      expect(museOnDemandSsids('broken'), isEmpty);
    });

    MuseSsidRead on(String? s) => MuseSsidRead.ok(s);
    const fail = MuseSsidRead.failed('x');
    const list = ['Home'];

    test('pause on a listed Wi‑Fi, resume after leaving it', () {
      final m = MuseOnDemand();
      expect(m.tick(ssids: list, read: on('Cafe'), running: true, generation: 1), MuseOnDemandStep.none);
      expect(m.tick(ssids: list, read: on('Home'), running: true, generation: 1), MuseOnDemandStep.pause);
      m.paused(2);
      expect(m.tick(ssids: list, read: on('Home'), running: false, generation: 2), MuseOnDemandStep.none);
      // netsh failing keeps the pause
      expect(m.tick(ssids: list, read: fail, running: false, generation: 2), MuseOnDemandStep.none);
      expect(m.pausedByUs, isTrue);
      expect(m.tick(ssids: list, read: on('Cafe'), running: false, generation: 2), MuseOnDemandStep.resume);
      m.resumed();
      expect(m.tick(ssids: list, read: on(null), running: true, generation: 3), MuseOnDemandStep.none);
      // not connected on the listed Wi‑Fi: nothing to pause
      expect(MuseOnDemand().tick(ssids: list, read: on('Home'), running: false, generation: 1), MuseOnDemandStep.none);
    });

    test('a manual 断开 while paused is never resumed', () {
      final m = MuseOnDemand()..paused(2);
      // user pressed 连接 then 断开 on the home Wi‑Fi (generation moved on)
      expect(m.tick(ssids: list, read: on('Home'), running: false, generation: 4), MuseOnDemandStep.none);
      expect(m.pausedByUs, isFalse);
      expect(m.tick(ssids: list, read: on('Cafe'), running: false, generation: 4), MuseOnDemandStep.none);
    });

    test('a manual 连接 on the listed Wi‑Fi is not paused again until the Wi‑Fi changes', () {
      final m = MuseOnDemand()..paused(2);
      expect(m.tick(ssids: list, read: on('Home'), running: true, generation: 3), MuseOnDemandStep.none);
      expect(m.overrideSsid, 'Home');
      expect(m.tick(ssids: list, read: on('Home'), running: true, generation: 3), MuseOnDemandStep.none);
      expect(m.tick(ssids: list, read: on('Cafe'), running: true, generation: 3), MuseOnDemandStep.none);
      expect(m.tick(ssids: list, read: on('Home'), running: true, generation: 3), MuseOnDemandStep.pause);
    });

    test('provider is idle while off or with no Wi‑Fi listed (no netsh at start-up)', () async {
      var reads = 0;
      final c = await _container(
        {'muse_on_demand': true},
        overrides: [
          museOnDemandForceProvider.overrideWithValue(true),
          museSsidReaderProvider.overrideWithValue(() async {
            reads++;
            return const MuseSsidRead.ok(null);
          }),
        ],
      );
      addTearDown(c.dispose);
      c.listen(museOnDemandProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reads, 0);
      expect(museOnDemandInterval, const Duration(seconds: 15));
    });

    testWidgets('page: add by name, add current (location hint), remove', (t) async {
      final c = await _pump(
        t,
        const MuseOnDemandPage(),
        overrides: [
          museSsidReaderProvider.overrideWithValue(() async => const MuseSsidRead.failed(museWifiLocationHint)),
        ],
      );
      await t.enterText(find.byKey(const ValueKey('on_demand_input')), 'Home');
      await t.tap(find.byKey(const ValueKey('on_demand_add')));
      await t.pumpAndSettle();
      expect(museOnDemandSsids(c.read(MusePrefs.wifiRules)), ['Home']);
      expect(find.byKey(const ValueKey('on_demand_ssid_Home')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('on_demand_add_current')));
      await t.pumpAndSettle();
      expect(find.text(museWifiLocationHint), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('on_demand_switch')));
      await t.pumpAndSettle();
      expect(c.read(MusePrefs.onDemand), isTrue);
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('on_demand_ssid_Home')),
          matching: find.byIcon(Icons.delete_outlined),
        ),
      );
      await t.pumpAndSettle();
      expect(museOnDemandSsids(c.read(MusePrefs.wifiRules)), isEmpty);
    });
  });

  group('C8 开机自启 / 静默启动', () {
    test('--autostart is told apart from --silent', () {
      final a = museParseCliArgs(['--autostart']);
      expect((a.autostart, a.silent, a.isEmpty, a.connect), (true, false, false, false));
      expect(museParseCliArgs(['--tray']).silent, isTrue);
      expect(museParseCliArgs(['--silent']).autostart, isFalse);
    });

    test('silent start decision', () {
      const none = MuseCliArgs();
      const auto = MuseCliArgs(autostart: true);
      bool s({bool pref = false, bool crash = false, MuseCliArgs args = none, bool autoSilent = false}) =>
          museStartSilently(silentStart: pref, afterCrash: crash, args: args, autostartSilent: autoSilent);
      expect(s(), isFalse);
      expect(s(pref: true), isTrue);
      expect(s(crash: true), isTrue);
      expect(s(args: const MuseCliArgs(silent: true)), isTrue);
      expect(s(args: auto), isFalse);
      expect(s(args: auto, autoSilent: true), isTrue);
      // 开机自启时静默 alone never hides a start by hand
      expect(s(autoSilent: true), isFalse);
    });

    test('start-up entry carries --autostart and old entries are rewritten (source)', () {
      final src = File('lib/features/auto_start/notifier/auto_start_notifier.dart').readAsStringSync();
      expect(src, contains("museAutostartArgs = ['--autostart']"));
      expect(src, contains('setup(const [])'));
      final win = File('lib/features/window/notifier/window_notifier.dart').readAsStringSync();
      expect(win, contains('museStartSilentlyNow(ref.read)'));
      expect(File('lib/bootstrap.dart').readAsStringSync(), contains('museStartSilentlyNow(container.read)'));
    });
  });

  group('C8 标题栏', () {
    testWidgets('46×32 buttons; min / max / restore / close / pin; drag and double-click', (t) async {
      final ops = _FakeOps();
      final c = await _pump(
        t,
        const MuseTitleBarFrame(child: Scaffold(body: Text('page'))),
        overrides: [museTitleBarForceProvider.overrideWithValue(true), museWindowOpsProvider.overrideWithValue(ops)],
      );
      expect(find.byKey(const ValueKey('muse_title_bar')), findsOneWidget);
      expect(find.text('page'), findsOneWidget);
      for (final k in ['muse_title_pin', 'muse_title_min', 'muse_title_max', 'muse_title_close']) {
        expect(t.getSize(find.byKey(ValueKey(k))), const Size(MuseSize.captionButton, MuseSize.titleBar));
      }
      expect(t.getSize(find.byKey(const ValueKey('muse_title_bar'))).height, MuseSize.titleBar);
      await t.tap(find.byKey(const ValueKey('muse_title_min')));
      await t.tap(find.byKey(const ValueKey('muse_title_max')));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('还原'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('muse_title_max')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('muse_title_close')));
      await t.tap(find.byKey(const ValueKey('muse_title_pin')));
      await t.pumpAndSettle();
      expect(ops.calls, ['minimize', 'maximize', 'unmaximize', 'close', 'top:true']);

      ops.calls.clear();
      final drag = find.byKey(const ValueKey('muse_title_drag'));
      await t.drag(drag, const Offset(40, 0));
      await t.pumpAndSettle();
      expect(ops.calls, ['drag']);
      ops.calls.clear();
      await t.tap(drag);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(drag);
      await t.pumpAndSettle();
      expect(ops.calls, ['maximize']);

      // pinned: the pin turns brand-coloured and offers 取消置顶
      await c.read(MusePrefs.alwaysOnTop.notifier).update(true);
      await t.pump();
      expect(find.bySemanticsLabel('取消置顶'), findsOneWidget);
      expect(t.widget<Icon>(find.byIcon(Icons.push_pin_outlined)).color, MusePalette.brand);
      // off: the pages only, no bar
      await c.read(MusePrefs.customTitleBar.notifier).update(false);
      await t.pump();
      expect(find.byKey(const ValueKey('muse_title_bar')), findsNothing);
      expect(find.text('page'), findsOneWidget);
    });

    testWidgets('off Windows (default) there is no bar', (t) async {
      await _pump(t, const MuseTitleBarFrame(child: Text('page')));
      expect(find.byKey(const ValueKey('muse_title_bar')), findsNothing);
    });

    test('window title string and native frame API (source)', () {
      final win = File('lib/features/window/notifier/window_notifier.dart').readAsStringSync();
      expect(win, contains('TitleBarStyle.hidden'));
      expect(win, contains('setAlwaysOnTop'));
      final smoke = File('tool/smoke/app_smoke.ps1').readAsStringSync();
      expect(smoke, contains('(32 + 56 + 52 * 2 + 26)'));
      // the five tray words the smoke test checks are unchanged
      expect(
        smoke,
        contains(
          r'$expect = @((Cn 0x8FDE,0x63A5), (Cn 0x89C4,0x5219), (Cn 0x5168,0x5C40), (Cn 0x663E,0x793A,0x7A97,0x53E3), (Cn 0x9000,0x51FA))',
        ),
      );
    });
  });

  group('C8 设置', () {
    test('search entries (Windows only; 按需运行 is Android\'s too since C9)', () {
      for (final title in ['开机自启时静默', '穿云标题栏', '窗口置顶', '快捷键']) {
        final e = museSettingEntries.where((x) => x.title == title).single;
        expect(e.windowsOnly, isTrue, reason: title);
      }
      final onDemand = museSettingEntries.where((x) => x.title == '按需运行').single;
      expect(onDemand.windowsOnly || onDemand.androidOnly, isFalse);
    });

    test('new code and text never name the upstream projects', () {
      for (final p in [
        'lib/features/muse/desktop/hotkeys.dart',
        'lib/features/muse/desktop/on_demand.dart',
        'lib/features/muse/desktop/title_bar.dart',
        'lib/features/muse/desktop/desktop_actions.dart',
        'lib/features/muse/data/wifi_ssid.dart',
        'lib/features/muse/logic/proxy_env.dart',
        'lib/features/muse/settings/windows_extras.dart',
      ]) {
        // the package itself is still called that in import lines
        final s = File(p).readAsLinesSync().where((l) => !l.startsWith('import ')).join('\n').toLowerCase();
        for (final w in ['flclash', 'clash', 'hiddify', 'sing-box']) {
          expect(s.contains(w), isFalse, reason: '$p mentions $w');
        }
      }
    });
  });
}
