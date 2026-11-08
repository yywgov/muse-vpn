// 穿云 1.16.0 批4 界面/统计/隐私: B7 按天/按应用流量图, B8 敏感页禁截屏与后台模糊, B9 纯黑深色,
// B10 新用户一步引导, B11 读屏标签, R25 小组件常用节点, R17 国内应用识别.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/muse/home/first_guide.dart';
import 'package:hiddify/features/muse/home/home_data.dart' show museHasProfileProvider;
import 'package:hiddify/features/muse/data/secure_screen.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiddify/features/muse/logic/domestic_apps.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/logic/app_traffic.dart';
import 'package:hiddify/features/muse/data/app_traffic_recorder.dart';
import 'package:hiddify/features/muse/local_api/local_api_client.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show museAppBars;
import 'package:hiddify/features/muse/home/widget_sync.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/features/muse/nodes/node_list.dart' show museNodeSemanticsLabel;
import 'package:hiddify/features/muse/widget/grouped_list.dart' show MuseSwitchTile;
import 'package:hiddify/features/profile/add/add_profile_modal.dart' show MuseAddAction;
import 'package:hiddify/features/muse/logic/per_app_tools.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('R17 国内应用识别', () {
    MuseAppRow app(String p) => MuseAppRow(packageName: p, name: p);

    test('only installed, listed and not yet selected packages', () {
      final installed = [app('com.tencent.mm'), app('org.example.foo'), app('com.eg.android.AlipayGphone'), app('tv.danmaku.bili')];
      final flags = {'com.eg.android.AlipayGphone': 1};
      expect(museDomesticTargets(installed, flags), ['com.tencent.mm', 'tv.danmaku.bili']);
      expect(museDomesticTargets(const [], const {}), isEmpty);
    });

    test('the list is local, exact package names, no foreign apps', () {
      expect(museDomesticPackages.length, greaterThan(80));
      final pkg = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$');
      for (final p in museDomesticPackages) {
        expect(pkg.hasMatch(p), isTrue, reason: p);
      }
      for (final p in ['com.google.android.youtube', 'org.telegram.messenger', 'com.twitter.android', 'com.whatsapp']) {
        expect(museDomesticPackages, isNot(contains(p)));
      }
      final src = _src('lib/features/muse/logic/domestic_apps.dart');
      expect(src, isNot(contains('http')));
      expect(src, isNot(contains('Timer')));
    });

    test('summary', () {
      expect(museDomesticSummary(added: 0, already: 0), '没有找到常见国内应用');
      expect(museDomesticSummary(added: 3, already: 0), '已选中 3 个常见国内应用');
      expect(museDomesticSummary(added: 0, already: 2), '常见国内应用已全部选中（2 个）');
      expect(museDomesticSummary(added: 1, already: 2), contains('另有 2 个'));
    });

    test('menu entry only in 以下 App 不走代理 mode', () {
      final src = _src('lib/features/app_based_routing/overview/app_list_page.dart');
      expect(src, contains("if (mode == AppProxyMode.exclude)\n                      MuseMenuItem(label: '选中常见国内应用'"));
      expect(src, contains('museDomesticTargets(installed, flags)'));
    });
  });

  group('B9 纯黑深色', () {
    test('跟随系统 + 纯黑 is black only while the system is dark', () {
      bool b(AppThemeMode m, bool f, Brightness br) => museUsePureBlack(m, blackWhenSystemDark: f, brightness: br);
      expect(b(AppThemeMode.system, true, Brightness.dark), isTrue);
      expect(b(AppThemeMode.system, true, Brightness.light), isFalse);
      expect(b(AppThemeMode.system, false, Brightness.dark), isFalse);
      expect(b(AppThemeMode.black, false, Brightness.dark), isTrue);
      expect(b(AppThemeMode.dark, true, Brightness.dark), isFalse); // 深色 keeps its own 纯黑 switch
      expect(b(AppThemeMode.light, true, Brightness.dark), isFalse);
    });

    test('the dark scheme surface is #000000, the light one is not', () {
      final t = AppTheme(AppThemeMode.system, '', blackWhenSystemDark: true);
      expect(t.scheme(Brightness.dark).surface, const Color(0xFF000000));
      expect(t.scheme(Brightness.light).surface, isNot(const Color(0xFF000000)));
      expect(AppTheme(AppThemeMode.system, '').scheme(Brightness.dark).surface, isNot(const Color(0xFF000000)));
    });

    test('外观 shows 纯黑 under 跟随系统; app applies the saved switch', () {
      final page = _src('lib/features/muse/settings/appearance_page.dart');
      expect(page, contains("ValueKey('appearance_pure_black_follow')"));
      expect(page, contains('if (shownTheme == AppThemeMode.system)'));
      final app = _src('lib/features/app/widget/app.dart');
      expect(app, contains('blackWhenSystemDark: blackFollow'));
      expect(_src('lib/features/muse/data/muse_prefs.dart'), contains('"muse_pure_black_follow", false'));
    });
  });

  group('B10 新用户一步引导', () {
    test('new install shows it once; upgrades and existing users never see it', () {
      expect(museFirstGuideFor(done: false, hasProfile: false, changelogShown: ''), MuseFirstGuide.show);
      expect(museFirstGuideFor(done: true, hasProfile: false, changelogShown: ''), MuseFirstGuide.none);
      expect(museFirstGuideFor(done: false, hasProfile: null, changelogShown: ''), MuseFirstGuide.none); // still reading
      expect(museFirstGuideFor(done: false, hasProfile: true, changelogShown: ''), MuseFirstGuide.markDone);
      expect(museFirstGuideFor(done: false, hasProfile: false, changelogShown: '1.15.0'), MuseFirstGuide.markDone);
    });

    test('actions: paste always, 扫码 only with a camera scanner', () {
      expect([for (final a in museGuideActions(qr: true)) a.$4], [MuseAddAction.paste, MuseAddAction.qr]);
      expect([for (final a in museGuideActions(qr: false)) a.$4], [MuseAddAction.paste]);
    });

    testWidgets('sheet: 粘贴 / 扫码 return the action, 跳过 returns nothing', (tester) async {
      MuseAddAction? got;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                got = await showModalBottomSheet<MuseAddAction>(context: context, builder: (_) => const MuseFirstGuideSheet(qr: true));
                closed = true;
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('欢迎使用穿云'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide_qr')));
      await tester.pumpAndSettle();
      expect(got, MuseAddAction.qr);
      closed = false;
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide_skip')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(got, isNull);
    });

    testWidgets('e2e #20: the guide closes by itself when a subscription is added some other way', (tester) async {
      final has = StateProvider<bool?>((_) => false);
      final container = ProviderContainer(overrides: [museHasProfileProvider.overrideWith((ref) => ref.watch(has))]);
      addTearDown(container.dispose);
      MuseAddAction? got = MuseAddAction.paste;
      var closed = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  got = await showModalBottomSheet<MuseAddAction>(
                    context: context,
                    builder: (_) => const MuseFirstGuideCloser(child: MuseFirstGuideSheet(qr: true)),
                  );
                  closed = true;
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('first_guide_sheet')), findsOneWidget);
      // still no subscription: stays open
      container.read(has.notifier).state = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('first_guide_sheet')), findsOneWidget);
      // a subscription arrives (import link, 订阅 page, backup): closes as 跳过, no 「现在连接？」
      container.read(has.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('first_guide_sheet')), findsNothing);
      expect(closed, isTrue);
      expect(got, isNull);
      expect(find.text('打开'), findsOneWidget); // only the guide closed, not the page under it
      expect(container.read(museGuideAwaitConnectProvider), isFalse);
    });

    test('the home guide is shown wrapped in the closer', () {
      expect(_src('lib/features/muse/home/first_guide.dart'), contains('MuseFirstGuideCloser(child: MuseFirstGuideSheet(qr: qr))'));
    });

    test('home decides before the 更新说明 effect records the version, and records the guide as done first', () {
      final home = _src('lib/features/muse/home/muse_home_page.dart');
      expect(home, contains('final shownBefore = ref.read(Preferences.museChangelogShown);'));
      expect(home, contains('museGuideAskConnect(context, ref)'));
      final g = _src('lib/features/muse/home/first_guide.dart');
      final i = g.indexOf('await ref.read(MusePrefs.onboardingDone.notifier).update(true)');
      expect(i, greaterThan(0));
      expect(i, lessThan(g.indexOf('showModalBottomSheet')));
      expect(g, isNot(contains('Timer')));
      expect(g, isNot(contains('Clipboard')));
    });
  });

  group('B11 读屏标签', () {
    testWidgets('a switch row is one item: title + switch state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(child: MuseSwitchTile(title: '开机自动连接', value: true, onChanged: (_) {})),
        ),
      );
      final node = tester.getSemantics(find.byType(ListTile));
      final data = node.getSemanticsData();
      expect(data.label, contains('开机自动连接'));
      expect(data.hasFlag(SemanticsFlag.hasToggledState), isTrue);
      expect(data.hasFlag(SemanticsFlag.isToggled), isTrue);
      handle.dispose();
    });

    test('node card label (Chinese)', () {
      expect(museNodeSemanticsLabel('香港 01', '85 ms', selected: false), '节点 香港 01，延迟 85 ms');
      expect(museNodeSemanticsLabel('日本', '', selected: true), '当前节点，节点 日本');
      final src = _src('lib/features/muse/nodes/node_rows.dart');
      expect(src, contains("hint: selected ? null : '点按切换到这个节点'"));
    });

    test('the big connect switch speaks 连接 / 断开 / 取消连接', () {
      final home = _src('lib/features/muse/home/muse_home_page.dart');
      expect(home, contains("MuseConnectAction.cancel => '取消连接'"));
      expect(home, contains("MuseConnectAction.disconnect => '断开'"));
    });

    test('every icon-only button on the 穿云 pages has a Chinese tooltip (read aloud)', () {
      final bad = <String>[];
      final start = RegExp(r'IconButton(?:\.filled|\.outlined|\.filledTonal)?\(');
      for (final f in Directory('lib/features/muse').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync();
        for (final m in start.allMatches(s)) {
          var i = m.end;
          var depth = 1;
          while (depth > 0 && i < s.length) {
            if (s[i] == '(') depth++;
            if (s[i] == ')') depth--;
            i++;
          }
          final body = s.substring(m.start, i);
          if (!body.contains('tooltip')) bad.add('${f.path}:${'\n'.allMatches(s.substring(0, m.start)).length + 1}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  });

  group('B8 敏感页禁截屏与后台模糊', () {
    late List<bool> calls;
    setUp(() {
      calls = [];
      museSecureSetter = (on) async {
        calls.add(on);
        return true;
      };
    });

    Future<ProviderContainer> container({bool? on}) async {
      SharedPreferences.setMockInitialValues({if (on != null) 'muse_secure_sensitive': on});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWith((ref) async => sp)]);
      await c.read(sharedPreferencesProvider.future);
      addTearDown(c.dispose);
      return c;
    }

    test('counter: on with the first page, off with the last', () {
      final c = MuseSecureCounter();
      expect(c.enter(), isTrue);
      expect(c.enter(), isFalse);
      expect(c.leave(), isFalse);
      expect(c.leave(), isTrue);
      expect(c.leave(), isFalse); // never below zero
    });

    test('default on: secured while open, cleared after (also on error)', () async {
      final c = await container();
      expect(c.read(MusePrefs.secureSensitive), isTrue);
      await museWithSecureScreen(c, () async {
        expect(calls, [true]);
        await museWithSecureScreen(c, () async {}); // a QR over 节点详情
        expect(calls, [true]);
      });
      expect(calls, [true, false]);
      await expectLater(museWithSecureScreen(c, () async => throw StateError('x')), throwsStateError);
      expect(calls, [true, false, true, false]);
    });

    test('turned off in 外观: nothing is called', () async {
      final c = await container(on: false);
      await museWithSecureScreen(c, () async {});
      expect(calls, isEmpty);
    });

    test('the four sensitive places are wrapped; Android sets FLAG_SECURE on the window', () {
      expect(_src('lib/features/muse/nodes/node_details.dart'), contains('museSecureFor(context, () => _showMuseNodeDetails('));
      expect(_src('lib/features/muse/widget/qr_view.dart'), contains('await museSecureFor(context, () => showDialog<void>('));
      expect(_src('lib/features/muse/settings/sync_pages.dart'), contains('museSecureFor(context, () => _museExportConfig(context, ref))'));
      expect(_src('lib/features/profile/details/profile_details_page.dart'), contains('return MuseSecureScope(child: Scaffold('));
      final kt = _src('android/app/src/main/kotlin/com/hiddify/hiddify/ChuanyunHandler.kt');
      expect(kt, contains('"set_secure_screen"'));
      expect(kt, contains('addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)'));
      expect(kt, contains('clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)'));
      expect(_src('lib/features/muse/settings/appearance_page.dart'), contains("ValueKey('appearance_secure_sensitive')"));
    });
  });

  group('R25 小组件常用节点', () {
    OutboundGroup group() => OutboundGroup(
      tag: 'select',
      selected: 'b',
      items: [
        OutboundInfo(tag: 'auto', tagDisplay: '自动选择', isGroup: true),
        OutboundInfo(tag: 'a', tagDisplay: '香港 01'),
        OutboundInfo(tag: 'b', tagDisplay: '日本 02'),
        OutboundInfo(tag: 'c', tagDisplay: '美国 03'),
        OutboundInfo(tag: 'd', tagDisplay: '新加坡 04'),
      ],
    );

    test('first 3 favourites in list order; groups and unknown tags skipped', () {
      final favs = museWidgetFavs(group(), {'d', 'c', 'a', 'b', 'auto', 'gone'});
      expect([for (final f in favs) f.$1], ['a', 'b', 'c']);
      expect(favs.first.$2, contains('香港 01'));
      expect(museWidgetFavs(group(), const {}), isEmpty);
      expect(museWidgetFavs(null, {'a'}), isEmpty);
      expect(museWidgetFavs(group(), {'c'}).single.$1, 'c');
    });

    test('sent only on a change (no timer), favourites included', () {
      final src = _src('lib/features/muse/home/widget_sync.dart');
      expect(src, contains('ref.listen(Preferences.museFavoriteNodes, (_, _) => push());'));
      expect(src, contains('listEquals(favs, lastFavs)'));
      expect(src, isNot(contains('Timer')));
      expect(_src('lib/features/muse/data/chuanyun_platform.dart'), contains("'favTags': [for (final f in favs) f.\$1]"));
    });

    test('Android widget: 3 slots, tap = chuanyun://connect?node=, application context only, no timer', () {
      final kt = _src('android/app/src/main/kotlin/com/hiddify/hiddify/bg/ChuanyunWidget.kt');
      expect(kt, contains('fun favLink(tag: String): String = "chuanyun://connect?node=" + Uri.encode(tag)'));
      expect(kt, contains('intArrayOf(R.id.widget_fav1, R.id.widget_fav2, R.id.widget_fav3)'));
      expect(kt, contains('val context = appContext() ?: return'));
      expect(kt, contains('setContentDescription(id, "切换到节点 \${fav.second}")'));
      final layout = _src('android/app/src/main/res/layout/chuanyun_widget.xml');
      for (final id in ['widget_favs', 'widget_fav1', 'widget_fav2', 'widget_fav3', 'widget_toggle', 'widget_text']) {
        expect(layout, contains('@+id/$id'));
      }
      final info = _src('android/app/src/main/res/xml/chuanyun_widget_info.xml');
      expect(info, contains('android:updatePeriodMillis="0"'));
      final handler = _src('android/app/src/main/kotlin/com/hiddify/hiddify/ChuanyunHandler.kt');
      expect(handler, contains('ChuanyunWidget.zipFavs('));
    });
  });

  group('B7 按天/按应用流量图', () {
    MuseConn conn(String id, String process, int up, int down, {DateTime? end}) => MuseConn(
      id: id,
      host: 'h',
      destination: '1.2.3.4:443',
      network: 'tcp',
      inbound: 'tun',
      chains: const ['n'],
      rule: '',
      process: process,
      upload: up,
      download: down,
      start: DateTime(2026),
      end: end,
    );

    test('sampler: first sight counts from zero, then deltas; gone connections forgotten; no app = skipped', () {
      final s = MuseAppTrafficSampler();
      var d = s.sample([conn('1', 'com.tencent.mm (10123)', 100, 900), conn('2', '', 50, 50), conn('3', 'com.tencent.mm', 10, 0)]);
      expect(d, {'com.tencent.mm': (1010, 'com.tencent.mm')});
      d = s.sample([conn('1', 'com.tencent.mm (10123)', 200, 1000)]);
      expect(d['com.tencent.mm']!.$1, 200);
      expect(s.tracked, 1);
      d = s.sample([conn('4', r'C:\Program Files\App\app.exe', 5, 5)]);
      expect(d.values.single, (10, 'app.exe'));
      s.reset();
      expect(s.tracked, 0);
    });

    test('log: per day per app, 30 days kept, top over a range', () {
      var log = MuseAppTrafficLog.empty;
      final day = DateTime(2026, 11, 8);
      log = log.add(day, {'a': (100, 'A'), 'b': (300, 'B')});
      log = log.add(day, {'a': (250, 'A'), 'zero': (0, 'Z')});
      log = log.add(DateTime(2026, 11, 2), {'c': (1000, 'C')});
      log = log.add(DateTime(2026, 10, 1), {'old': (5, 'O')}); // older than 30 days before 11-08? added later than 11-08 entries
      final again = MuseAppTrafficLog.parse(log.toRaw());
      expect(again.days['2026-11-08'], {'a': (350, 'A'), 'b': (300, 'B')});
      expect([for (final t in again.top(day)) t.$1], ['a', 'b']);
      expect([for (final t in again.top(day, n: 7)) t.$1], ['c', 'a', 'b']);
      // the next write on 11-08 drops days before 10-10
      final pruned = again.add(day, {'a': (1, 'A')});
      expect(pruned.days.containsKey('2026-10-01'), isFalse);
      expect(pruned.days.containsKey('2026-11-02'), isTrue);
      expect(MuseAppTrafficLog.parse('nope').days, isEmpty);
    });

    test('feed: flushes every 30 frames and on close; bars use app names', () async {
      var raw = '';
      final writes = <String>[];
      final feed = MuseAppTrafficFeed(MuseAppTrafficSampler(), () => raw, (v) async {
        raw = v;
        writes.add(v);
      }, flushEvery: 3);
      feed.frame([conn('1', 'com.a', 1, 1)]);
      feed.frame([conn('1', 'com.a', 2, 2)]);
      expect(writes, isEmpty);
      feed.frame([conn('1', 'com.a', 3, 3)]);
      expect(writes, hasLength(1));
      feed.frame([conn('1', 'com.a', 10, 3)]);
      feed.flush();
      expect(writes, hasLength(2));
      feed.flush(); // nothing pending
      expect(writes, hasLength(2));
      final log = MuseAppTrafficLog.parse(raw);
      final bars = museAppBars(log, DateTime.now(), range: 0, labels: const {'com.a': '应用甲'});
      expect(bars.single, ('应用甲', 13));
    });

    test('no background sampling: only the 统计 open read and the 连接 page frames', () {
      final rec = _src('lib/features/muse/data/app_traffic_recorder.dart');
      expect(rec, isNot(contains('Timer')));
      expect(rec, contains('FutureProvider.autoDispose<void>'));
      final api = _src('lib/features/muse/local_api/local_api_providers.dart');
      expect(api, contains('feed.frame(frame.connections);'));
      expect(api, contains('ref.onDispose(feed.flush);'));
      final page = _src('lib/features/muse/settings/stats_page.dart');
      expect(page, contains('ref.watch(museAppTrafficOnOpenProvider);'));
      expect(page, contains("header: '按应用流量'"));
      expect(_src('lib/features/muse/data/sync_service.dart'), isNot(contains('muse_app_traffic')));
    });
  });

  group('版本 1.16.0', () {
    test('pubspec, changelog, CHANGELOG.md', () {
      expect(_src('pubspec.yaml'), contains('version: 1.16.0+205'));
      expect(museChangelog.keys.first, '1.16.0');
      final lines = museChangelog['1.16.0']!.join();
      for (final w in ['按应用流量', '禁止截屏', '纯黑', '一步开始', '读屏', '小组件', '常见国内应用']) {
        expect(lines, contains(w));
      }
      expect(_src('CHANGELOG.md'), contains('### 1.16.0'));
    });
  });
}
