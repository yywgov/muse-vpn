// 穿云 1.6.1 滚动到底: every scrolling page, inside the real shell, scrolls far enough that its
// last element sits fully above the bottom bar (floating and docked) and above the system
// gesture / three-button area; on a Windows-sized window (sidebar) and an Android tablet (rail)
// it ends above the window edge / system area. 1.6.0 let pages run under the floating bar,
// which hid the last ~100 dp of every list.

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/about/widget/open_source_page.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/config/muse_config_page.dart';
import 'package:hiddify/features/muse/connections/connections_page.dart';
import 'package:hiddify/features/muse/desktop/hotkeys.dart';
import 'package:hiddify/features/muse/desktop/on_demand.dart';
import 'package:hiddify/features/muse/home/exit_card.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/exit_check.dart';
import 'package:hiddify/features/muse/logs/logs_page.dart';
import 'package:hiddify/features/muse/nodes/muse_nodes_page.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart';
import 'package:hiddify/features/muse/settings/resources_page.dart';
import 'package:hiddify/features/muse/settings/theme_preview_page.dart';
import 'package:hiddify/features/muse/settings/windows_extras.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart';
import 'package:hiddify/features/muse/widget/muse_common.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Info extends AppInfo {
  @override
  Future<AppInfoEntity> build() async => const AppInfoEntity(
    name: '穿云',
    version: '1.6.1',
    buildNumber: '161',
    release: Release.general,
    operatingSystem: 'android',
    operatingSystemVersion: '14',
    environment: Environment.prod,
  );
}

class _Exit extends MuseExitNotifier {
  _Exit() : super(() => 0) {
    state = const MuseExitResult(info: MuseExitInfo(ip: '45.76.112.9', country: 'JP'));
  }
}

class _Reach extends MuseReachNotifier {
  _Reach() : super(() => 0) {
    state = MuseReach.ok;
  }
}

class _History extends MuseSpeedHistory {
  @override
  List<int> build() => [for (var i = 0; i < 30; i++) 1000 * i];
}

class _Profiles extends ProfilesNotifier {
  @override
  Stream<List<ProfileEntity>> build() => Stream.value([
    for (var i = 0; i < 12; i++)
      ProfileEntity.remote(id: 'p$i', active: i == 0, name: '订阅 $i', url: 'https://sub.example.com/p$i', lastUpdate: DateTime(2026, 10)),
  ]);
}

final _group = OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: '节点 0',
  selectable: true,
  items: [for (var i = 0; i < 60; i++) OutboundInfo(tag: '节点 $i', tagDisplay: '节点 $i', type: 'vless', urlTestDelay: 50 + i)],
);

MuseConn _conn(int i) => MuseConn(
  id: 'c$i',
  host: 'host$i.example.com',
  destination: '1.2.3.4:443',
  network: 'tcp',
  inbound: 'mixed',
  chains: const ['节点 1'],
  rule: 'final',
  process: '',
  upload: i,
  download: i * 10,
  start: DateTime(2026),
);

/// A screen the page is checked on.
class _Screen {
  const _Screen(this.name, this.size, {this.bottomInset = 0, this.mobile = true, this.docked = false});

  final String name;
  final Size size;

  /// the system gesture bar (≈24 dp) or three-button bar (≈48 dp)
  final double bottomInset;
  final bool mobile;
  final bool docked;
}

const _screens = [
  _Screen('手机 手势导航 浮动底栏', Size(390, 844), bottomInset: 24),
  _Screen('手机 三键导航 浮动底栏', Size(390, 844), bottomInset: 48),
  _Screen('手机 手势导航 固定底栏', Size(390, 844), bottomInset: 24, docked: true),
  _Screen('手机 三键导航 固定底栏', Size(360, 740), bottomInset: 48, docked: true),
  _Screen('Android 平板 侧栏 手势导航', Size(800, 1280), bottomInset: 24, mobile: false),
  _Screen('Windows 窗口', Size(1100, 720), mobile: false),
];

/// (name, tab, page, extra prefs, after-pump action)
final _pages = <(String, int, Widget, Map<String, Object>, Future<void> Function(WidgetTester)?)>[
  ('首页', 0, const MuseHomePage(), {}, null),
  ('节点', 1, const MuseNodesPage(), {}, null),
  ('订阅', 2, const MuseConfigPage(), {}, null),
  ('设置', 3, const SettingsPage(), {}, null),
  ('连接', 3, const MuseConnectionsPage(), {}, null),
  (
    '请求',
    3,
    const MuseConnectionsPage(),
    {},
    (t) async {
      await t.tap(find.text('请求 80'));
      await t.pump(const Duration(milliseconds: 300));
    },
  ),
  ('日志', 3, const MuseLogsPage(), {'muse_log_capture': true}, null),
  ('外观', 3, const MuseAppearancePage(), {}, null),
  ('节点设置', 3, const MuseNodeSettingsPage(), {}, null),
  ('分流', 3, const MuseRoutingPage(), {}, null),
  ('预设', 3, const MusePresetsPage(), {}, null),
  ('节点规则', 3, const MuseNodeRulesPage(), {}, null),
  ('远程规则集', 3, const MuseRemoteRuleSetsPage(), {}, null),
  ('规则测试', 3, const MuseRuleTesterPage(), {}, null),
  ('网络', 3, const MuseNetworkPage(), {}, null),
  ('同步与备份', 3, const MuseSyncPage(), {}, null),
  ('WebDAV', 3, const MuseWebdavPage(), {}, null),
  ('统计', 3, const MuseStatsPage(), {}, null),
  ('开发者选项', 3, const MuseDeveloperPage(), {'muse_dev_mode': true}, null),
  ('按需运行', 3, const MuseOnDemandPage(), {}, null),
  ('快捷键', 3, const MuseHotkeysPage(), {}, null),
  ('资源', 3, const MuseResourcesPage(), {}, null),
  ('主题预览', 3, const MuseThemePreviewPage(), {}, null),
  ('关于', 3, const AboutPage(), {}, null),
  ('开源许可', 3, const OpenSourcePage(), {}, null),
];

Future<void> _pump(WidgetTester t, _Screen s, int tab, Widget page, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues({
    'muse_node_sort': 'original',
    if (s.docked) 'muse_dock_style': 'docked',
    ...prefs,
  });
  final sp = await SharedPreferences.getInstance();
  final history = MuseRequestHistory();
  for (var i = 0; i < 80; i++) {
    history.add(_conn(1000 + i));
  }
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => sp),
      appInfoProvider.overrideWith(_Info.new),
      museConnectionProvider.overrideWithValue(const AsyncData(Connected())),
      museConnectPreparingProvider.overrideWith((ref) => false),
      museRunningProvider.overrideWithValue(true),
      museHasProfileProvider.overrideWithValue(true),
      museActiveProfileIdProvider.overrideWithValue('p0'),
      museActiveProfileNameProvider.overrideWithValue('订阅 0'),
      museAppVersionProvider.overrideWithValue(null),
      museStatsProvider.overrideWithValue(SystemInfo(uplink: Int64(1000), downlink: Int64(2000))),
      museNodeGroupProvider.overrideWithValue(AsyncData(_group)),
      museConnectedSinceProvider.overrideWith((ref) async => null),
      museEngineVersionProvider.overrideWith((ref) async => null),
      profilesNotifierProvider.overrideWith(_Profiles.new),
      museSubInfoProvider.overrideWithValue(null),
      museSpeedHistoryProvider.overrideWith(_History.new),
      museExitProvider.overrideWith((ref) => _Exit()),
      museReachProvider.overrideWith((ref) => _Reach()),
      museConnectionsProvider.overrideWith((ref) => Stream.value(MuseConnState(connections: [for (var i = 0; i < 80; i++) _conn(i)]))),
      museRequestHistoryProvider.overrideWithValue(history),
      museLogsProvider.overrideWith(
        (ref) => Stream.value([for (var i = 0; i < 120; i++) MuseLogLine('info', 'line $i', DateTime(2026))]),
      ),
      museHotkeysForceProvider.overrideWithValue(true),
      museOnDemandForceProvider.overrideWithValue(true),
    ],
  );
  addTearDown(c.dispose);
  await t.runAsync(() => c.read(sharedPreferencesProvider.future));
  await t.runAsync(() => c.read(translationsProvider.future));
  await t.runAsync(() => c.read(appInfoProvider.future));
  const dpr = 2.0;
  t.view.physicalSize = s.size * dpr;
  t.view.devicePixelRatio = dpr;
  t.view.padding = FakeViewPadding(bottom: s.bottomInset * dpr);
  t.view.viewPadding = FakeViewPadding(bottom: s.bottomInset * dpr);
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: MuseShellFrame(isMobile: s.mobile, currentIndex: tab, onTap: (_) {}, child: page),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// The page's main vertical scroll view: the tallest one on screen.
ScrollableState? _mainScrollable(WidgetTester t) {
  ScrollableState? best;
  var bestHeight = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final st = (e as StatefulElement).state as ScrollableState;
    if (axisDirectionToAxis(st.axisDirection) != Axis.vertical) continue;
    if (e.findAncestorWidgetOfExactType<MuseSidebar>() != null) continue;
    final box = st.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) continue;
    if (box.size.height > bestHeight) {
      bestHeight = box.size.height;
      best = st;
    }
  }
  return best;
}

/// The lowest edge of anything painted inside [st] (text, icons, switches…).
double _contentBottom(WidgetTester t, ScrollableState st) {
  var bottom = 0.0;
  final vp = st.context.findRenderObject()! as RenderBox;
  final vpRect = vp.localToGlobal(Offset.zero) & vp.size;
  void visit(Element e) {
    final r = e.renderObject;
    if (e.widget is RichText || e.widget is Icon || e.widget is Switch || e.widget is FilledButton || e.widget is OutlinedButton) {
      if (r is RenderBox && r.hasSize && r.attached) {
        final rect = r.localToGlobal(Offset.zero) & r.size;
        // only what is inside the viewport's horizontal span and not scrolled away above it
        if (rect.top >= vpRect.top - 1 && rect.top < vpRect.bottom && rect.overlaps(vpRect.inflate(4))) {
          if (rect.bottom > bottom) bottom = rect.bottom;
        }
      }
    }
    e.visitChildren(visit);
  }

  st.context.visitChildElements(visit);
  return bottom;
}

/// The top edge of the bottom bar, or the lowest point the system area leaves free.
double _clearLine(WidgetTester t, _Screen s) {
  final docked = find.byKey(const ValueKey('muse_dock_docked'));
  final floating = find.byKey(const ValueKey('muse_dock_floating'));
  if (docked.evaluate().isNotEmpty) return t.getTopLeft(docked).dy;
  if (floating.evaluate().isNotEmpty) return t.getTopLeft(floating).dy;
  return s.size.height - s.bottomInset;
}

void main() {
  for (final s in _screens) {
    for (final (name, tab, page, prefs, after) in _pages) {
      testWidgets('$name · ${s.name}: scrolls to the end, last element fully above the bar', (t) async {
        await _pump(t, s, tab, page, prefs);
        if (after != null) await after(t);
        final st = _mainScrollable(t);
        expect(st, isNotNull, reason: '$name has a scroll view');
        // lazy lists grow their extent as they build, so jump a few times
        // a reversed list (日志, newest at the bottom) ends at its minimum
        final reversed = st!.axisDirection == AxisDirection.up;
        for (var i = 0; i < 6; i++) {
          st.position.jumpTo(reversed ? st.position.minScrollExtent : st.position.maxScrollExtent);
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(st.position.pixels, reversed ? st.position.minScrollExtent : st.position.maxScrollExtent);
        final bottom = _contentBottom(t, st);
        final line = _clearLine(t, s);
        expect(bottom, greaterThan(0), reason: '$name painted something');
        expect(bottom, lessThanOrEqualTo(line + 0.5), reason: '$name: last element bottom $bottom vs bar/system top $line');
        // the scroll view itself never reaches under the bar either
        final vp = st.context.findRenderObject()! as RenderBox;
        expect(vp.localToGlobal(Offset(0, vp.size.height)).dy, lessThanOrEqualTo(line + 0.5));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 61));
      });
    }
  }

}
