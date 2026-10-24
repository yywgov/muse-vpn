// 穿云 1.5.0 (batch 1, chunk 5): 设置 search, orange tray icon, feedback issue link, LAN sync hints.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/home/reachability.dart';
import 'package:hiddify/features/muse/logic/diagnosis.dart';
import 'package:hiddify/features/muse/logic/lan_sync.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/settings/settings_search.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';

void main() {
  group('#101 settings search', () {
    test('finds by title, keyword and page; title hits first', () {
      final dns = museSearchSettings('dns', android: true, windows: false);
      expect(dns.first.title, '远程 DNS');
      final ad = museSearchSettings('广告', android: true, windows: false);
      expect(ad.map((e) => e.title), contains('去广告'));
      final backup = museSearchSettings('备份', android: false, windows: true);
      expect(backup.first.page, MuseSettingPage.sync);
      // every word must match
      expect(museSearchSettings('分流 hosts', android: true, windows: false).single.title, '自定义 hosts');
      expect(museSearchSettings('   ', android: true, windows: true), isEmpty);
      expect(museSearchSettings('不存在的东西', android: true, windows: true), isEmpty);
    });
    test('platform-only settings stay on their platform', () {
      expect(museSearchSettings('分应用', android: false, windows: true), isEmpty);
      expect(museSearchSettings('分应用', android: true, windows: false), isNotEmpty);
      expect(museSearchSettings('开机自启', android: true, windows: false), isEmpty);
      expect(museSearchSettings('开机自启', android: false, windows: true), isNotEmpty);
    });
    test('every page is reachable and titles are unique', () {
      final titles = museSettingEntries.map((e) => e.title).toList();
      expect(titles.toSet().length, titles.length);
      expect({for (final e in museSettingEntries) e.page}.length, greaterThanOrEqualTo(MuseSettingPage.values.length - 1));
    });
  });

  testWidgets('#101 search sheet returns the tapped setting', (tester) async {
    MuseSettingEntry? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showMuseSettingsSearch(context, android: true, windows: false),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('settings_search_field')), 'quic');
    await tester.pump();
    expect(find.text('屏蔽 QUIC'), findsOneWidget);
    expect(find.text('设置 › 高级'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_hit_0')));
    await tester.pumpAndSettle();
    expect(picked?.title, '屏蔽 QUIC');
    expect(picked?.page, MuseSettingPage.advanced);
  });

  testWidgets('#101 no result says so', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MuseSettingsSearch(android: true, windows: false))));
    await tester.enterText(find.byKey(const ValueKey('settings_search_field')), 'zzzz');
    await tester.pump();
    expect(find.text('没有找到相关设置'), findsOneWidget);
  });

  group('#144 tray icon', () {
    test('orange only while connected and the internet check failed', () {
      expect(museTrayWarning(const Connected(), MuseReach.failed), isTrue);
      expect(museTrayWarning(const Connected(), MuseReach.ok), isFalse);
      expect(museTrayWarning(const Connected(), MuseReach.checking), isFalse);
      expect(museTrayWarning(const Disconnected(), MuseReach.failed), isFalse);
      expect(museTrayWarning(const Connecting(), MuseReach.failed), isFalse);
      expect(museTrayWarningIco, endsWith('.ico'));
    });
  });

  group('#233 feedback', () {
    test('issue link carries version and system, not the log', () {
      final uri = museFeedbackIssueUri(version: '1.5.0 (150)', system: 'android 14');
      expect(uri.toString(), startsWith('https://github.com/yywgov/muse-vpn/issues/new?'));
      expect(uri.queryParameters['body'], contains('版本：1.5.0 (150)'));
      expect(uri.queryParameters['body'], contains('系统：android 14'));
      expect(uri.toString().length, lessThan(2000));
    });
  });

  group('#195 LAN sync hints', () {
    test('name the usual causes', () {
      expect(museLanUnreachableHint, contains('同一个 Wi‑Fi'));
      expect(museLanUnreachableHint, contains('AP 隔离'));
      expect(museLanUnreachableHint, contains('防火墙'));
      expect(museLanNoAnswerHint, startsWith('对方没有回应'));
    });
  });
}
