// 穿云 1.2 unit tests: failover, watchdog, urltest/loopback config guards, hy2 bandwidth,
// subscription-userinfo parsing + bar, stats stream recovery, tray menu, Clash subscriptions.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/logic/failover_tracker.dart';
import 'package:hiddify/features/muse/logic/subscription_bar.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/muse/settings/advanced_page.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:fixnum/fixnum.dart';

MuseNodeSample _n(String tag, int delay, int t, {bool group = false}) =>
    MuseNodeSample(tag: tag, delay: delay, testedAt: t, isGroup: group);

void main() {
  group('fixed-node failover', () {
    List<MuseNodeSample> items(int aDelay, int t) => [_n('lowest', 80, t, group: true), _n('A', aDelay, t), _n('B', 90, t)];

    test('switches to 自动最快 after two fresh failures, not one', () {
      final f = MuseFailoverTracker();
      expect(f.update(selected: 'A', items: items(65535, 1), autoTag: 'lowest'), isNull);
      // the same result seen again is not a new failure
      expect(f.update(selected: 'A', items: items(65535, 1), autoTag: 'lowest'), isNull);
      expect(f.update(selected: 'A', items: items(65535, 2), autoTag: 'lowest'), 'lowest');
      expect(f.failedFrom, 'A');
    });

    test('a good result in between resets the count', () {
      final f = MuseFailoverTracker();
      f.update(selected: 'A', items: items(65535, 1), autoTag: 'lowest');
      f.update(selected: 'A', items: items(120, 2), autoTag: 'lowest');
      expect(f.update(selected: 'A', items: items(65535, 3), autoTag: 'lowest'), isNull);
    });

    test('switches back after the node passes two fresh tests', () {
      final f = MuseFailoverTracker();
      f.update(selected: 'A', items: items(65535, 1), autoTag: 'lowest');
      f.update(selected: 'A', items: items(65535, 2), autoTag: 'lowest');
      expect(f.update(selected: 'lowest', items: items(65535, 3), autoTag: 'lowest'), isNull);
      expect(f.update(selected: 'lowest', items: items(100, 4), autoTag: 'lowest'), isNull);
      expect(f.update(selected: 'lowest', items: items(110, 5), autoTag: 'lowest'), 'A');
      expect(f.active, isFalse);
    });

    test('groups and a manual change are left alone', () {
      final f = MuseFailoverTracker();
      expect(f.update(selected: 'lowest', items: items(65535, 1), autoTag: 'lowest'), isNull);
      f.update(selected: 'A', items: items(65535, 2), autoTag: 'lowest');
      f.update(selected: 'A', items: items(65535, 3), autoTag: 'lowest');
      expect(f.active, isTrue);
      expect(f.update(selected: 'B', items: items(65535, 4), autoTag: 'lowest'), isNull);
      expect(f.active, isFalse);
    });

    test('no auto group, no switch', () {
      final f = MuseFailoverTracker();
      f.update(selected: 'A', items: items(65535, 1), autoTag: null);
      expect(f.update(selected: 'A', items: items(65535, 2), autoTag: null), isNull);
    });
  });

  group('core watchdog', () {
    test('restarts after three failed pings in a row', () {
      final w = MuseWatchdogCounter();
      expect(w.record(ok: false), isFalse);
      expect(w.record(ok: false), isFalse);
      expect(w.record(ok: true), isFalse);
      expect(w.record(ok: false), isFalse);
      expect(w.record(ok: false), isFalse);
      expect(w.record(ok: false), isTrue);
      expect(w.fails, 0);
    });
  });

  group('config guards (urltest interval, loopback listen)', () {
    final src = File('lib/features/settings/data/config_option_repository.dart').readAsStringSync();
    test('url test every 5 minutes (the core keeps 50 ms tolerance)', () {
      expect(src, contains('urlTestInterval: const Duration(minutes: 5)'));
    });
    test('the proxy port never accepts LAN connections', () {
      expect(src, contains('allowConnectionFromLan: false,'));
      expect(src, isNot(contains('allowConnectionFromLan: ref.watch')));
    });
    test('direct DNS stays 223.5.5.5', () {
      expect(src, contains("directDnsAddress: 'udp://223.5.5.5'"));
    });
  });

  group('hysteria2 bandwidth', () {
    test('blank or invalid = automatic', () {
      expect(museParseBandwidth(''), 0);
      expect(museParseBandwidth('abc'), 0);
      expect(museParseBandwidth('0'), 0);
      expect(museParseBandwidth('999999'), 0);
      expect(museParseBandwidth(' 100 '), 100);
      expect(ConfigOptions.museBandwidth(-5), 0);
    });
    test('label', () {
      expect(museBandwidthLabel(0, 0), '自动');
      expect(museBandwidthLabel(30, 200), '↑30 ↓200');
      expect(museBandwidthLabel(0, 200), '↑自动 ↓200');
    });
  });

  group('subscription-userinfo', () {
    test('parses the header', () {
      final i = ProfileParser.parseSubscriptionInfo('upload=1073741824; download=2147483648; total=10737418240; expire=1893456000')!;
      expect(i.upload, 1073741824);
      expect(i.download, 2147483648);
      expect(i.total, 10737418240);
      expect(i.expire.toUtc().year, 2030);
    });
    test('tolerates noise and missing total/expire', () {
      final i = ProfileParser.parseSubscriptionInfo('upload=0;; download=12.7; total=0; expire=;')!;
      expect(i.download, 12);
      expect(museSubscriptionBar(i), isNull); // unlimited, no expiry: no bar
    });
    test('bar turns red on low traffic or near expiry', () {
      final now = DateTime(2026, 10, 14);
      const gb = 1024 * 1024 * 1024;
      final ok = museSubscriptionBar(SubscriptionInfo(upload: 0, download: 2 * gb, total: 10 * gb, expire: DateTime(2026, 12, 1)), now: now)!;
      expect(ok.remaining, closeTo(0.8, 0.001));
      expect(ok.warn, isFalse);
      final low = museSubscriptionBar(SubscriptionInfo(upload: 0, download: 95 * gb ~/ 10, total: 10 * gb, expire: DateTime(2026, 12, 1)), now: now)!;
      expect(low.warn, isTrue);
      final soon = museSubscriptionBar(SubscriptionInfo(upload: 0, download: 0, total: 10 * gb, expire: DateTime(2026, 10, 16)), now: now)!;
      expect(soon.warn, isTrue);
    });
  });

  group('stats stream', () {
    test('a stream that ends or fails is reopened', () async {
      var opened = 0;
      var active = true;
      Stream<SystemInfo> open() {
        opened++;
        if (opened == 1) return Stream.error(Exception('service not ready'));
        if (opened == 2) return Stream.fromIterable([SystemInfo(uplink: Int64(5), downlink: Int64(7))]);
        return Stream.fromIterable([SystemInfo(uplink: Int64(1), downlink: Int64(2))]);
      }

      final got = <SystemInfo>[];
      final sub = museResilientStats(open, isActive: () => active, retryDelay: Duration.zero).listen(got.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      active = false;
      await sub.cancel();
      expect(opened, greaterThanOrEqualTo(3));
      expect(got.where((e) => e.downlink > 0).length, greaterThanOrEqualTo(2));
    });
  });

  group('tray menu', () {
    test('连接/断开 · 配置/代理/直连 · 显示窗口 · 退出', () {
      final spec = museTrayMenuSpec(const Disconnected(), MuseRouteMode.global);
      expect(spec.where((e) => e.key != '-').map((e) => e.label).toList(), ['连接', '配置', '代理', '直连', '显示窗口', '退出']);
      expect(spec.firstWhere((e) => e.key == 'mode:global').checked, isTrue);
      expect(spec.firstWhere((e) => e.key == 'mode:rule').checked, isFalse);
      expect(museTrayMenuSpec(const Connected(), MuseRouteMode.rule).first.label, '断开');
    });
  });
}
