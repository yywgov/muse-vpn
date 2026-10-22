// 穿云 1.1 - unit tests for the pure Dart logic: node order, region flags, group names,
// clipboard link detection, subscription alerts, keep-alive guide and updater parsing.

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/home/clipboard_import.dart';
import 'package:hiddify/features/muse/home/keep_alive_guide.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/home/subscription_alert.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';

typedef _N = ({String name, bool group, int delay});

void main() {
  group('museSortNodes', () {
    List<String> sort(List<_N> items) => museSortNodes<_N>(
      items,
      isGroup: (e) => e.group,
      delay: (e) => e.delay,
      isValidDelay: (d) => d < 65000,
    ).map((e) => e.name).toList();

    test('groups first, then by latency, untested next, timed out last', () {
      final r = sort([
        (name: 'timeout', group: false, delay: 65535),
        (name: 'slow', group: false, delay: 300),
        (name: 'auto', group: true, delay: 0),
        (name: 'untested', group: false, delay: 0),
        (name: 'fast', group: false, delay: 80),
        (name: 'balance', group: true, delay: 120),
      ]);
      expect(r, ['auto', 'balance', 'fast', 'slow', 'untested', 'timeout']);
    });

    test('stable for equal latency', () {
      final r = sort([
        (name: 'a', group: false, delay: 100),
        (name: 'b', group: false, delay: 100),
        (name: 'c', group: false, delay: 100),
      ]);
      expect(r, ['a', 'b', 'c']);
    });
  });

  group('region flags', () {
    test('Chinese and English names', () {
      expect(museRegionCode('香港 01'), 'HK');
      expect(museRegionCode('Japan Tokyo 2'), 'JP');
      expect(museRegionCode('美国 洛杉矶'), 'US');
      expect(museRegionCode('澳门 IPLC'), 'MO');
      expect(museRegionCode('印尼 雅加达'), 'ID');
      expect(museRegionCode('PPFlight-Direct'), isNull);
    });

    test('existing flag emoji wins and UK maps to GB', () {
      expect(museRegionCode('🇯🇵 香港中转'), 'JP');
      expect(museRegionCode('🇺🇰 London'), 'GB');
    });

    test('emoji output', () {
      expect(museFlagEmoji('香港 01'), '🇭🇰');
      expect(museFlagEmoji('unknown node'), isNull);
    });
  });

  group('group names', () {
    test('known English names become Chinese', () {
      expect(museGroupName('lowest'), '自动最快');
      expect(museGroupName('balance'), '负载均衡');
      expect(museGroupName('select'), '手动选择');
      expect(museGroupName('我的分组'), '我的分组');
    });

    test('balancer kind and subtitle', () {
      expect(museGroupKind(type: 'Balancer', name: 'lowest', selectedDisplay: 'PPFlight-Direct'), '自动最快');
      expect(museGroupKind(type: 'Balancer', name: 'balance', selectedDisplay: 'round-robin'), '负载均衡');
      expect(museGroupSubtitle(type: 'Balancer', name: 'lowest', selectedDisplay: 'PPFlight-Direct'), 'PPFlight-Direct');
      expect(museGroupSubtitle(type: 'Balancer', name: 'balance', selectedDisplay: 'round-robin'), '');
      expect(museGroupSubtitle(type: 'Balancer', name: 'balance', selectedDisplay: 'round-robin', nodeCount: 12), '12 个节点');
      expect(museGroupSubtitle(type: 'Selector', name: 'select', selectedDisplay: '香港 01'), '手动选择 → 香港 01');
    });

    test('current outbound label', () {
      expect(museCurrentOutboundLabel('lowest → PPFlight-Direct'), '自动最快 · PPFlight-Direct');
      expect(museCurrentOutboundLabel('balance→round-robin'), '负载均衡 · 轮询');
      expect(museCurrentOutboundLabel('香港 01'), '香港 01');
    });
  });

  group('clipboard subscription link', () {
    test('subscription urls are detected', () {
      const sub = 'https://example.com/api/v1/client/subscribe?token=abc';
      expect(museSubscriptionLinkFromClipboard('  $sub \n'), sub);
      expect(museSubscriptionLinkFromClipboard('https://a.b/link/xyz?clash=1'), isNotNull);
      expect(museSubscriptionLinkFromClipboard('https://a.b/sub/123'), isNotNull);
    });

    test('import schemes are detected and unwrapped', () {
      const link = 'clash://install-config?url=https%3A%2F%2Fa.b%2Fs%2F1&name=x';
      expect(museSubscriptionLinkFromClipboard(link), link);
      expect(museSubscriptionUrlOf(link), 'https://a.b/s/1');
      expect(museSubscriptionLinkFromClipboard('hiddify://import/https://a.b/sub#n'), isNotNull);
    });

    test('ordinary text and web pages are ignored', () {
      expect(museSubscriptionLinkFromClipboard(null), isNull);
      expect(museSubscriptionLinkFromClipboard(''), isNull);
      expect(museSubscriptionLinkFromClipboard('你好 世界'), isNull);
      expect(museSubscriptionLinkFromClipboard('https://www.baidu.com/'), isNull);
      expect(museSubscriptionLinkFromClipboard('https://news.example.com/2026/10/article.html'), isNull);
      expect(museSubscriptionLinkFromClipboard('vless://uuid@host:443'), isNull);
      expect(museSubscriptionLinkFromClipboard('clash://install-config?url=ftp://x'), isNull);
      expect(museSubscriptionLinkFromClipboard('see https://a.b/sub/1 now'), isNull);
    });
  });

  group('subscription alerts', () {
    const gb = 1024 * 1024 * 1024;
    final now = DateTime(2026, 10, 13, 12);
    List<String> kinds({int used = 0, int total = 100 * gb, DateTime? expire}) => museSubscriptionAlerts(
      profileId: 'p',
      upload: 0,
      download: used,
      total: total,
      expire: expire ?? DateTime(2026, 12, 1),
      now: now,
    ).map((a) => a.key.split(':')[1]).toList();

    // 1.2.8: 80 % used, then used up — each its own threshold
    test('traffic: 80 % used, then used up', () {
      expect(kinds(used: 79 * gb), isEmpty);
      expect(kinds(used: 80 * gb), ['traffic80']);
      expect(kinds(used: 89 * gb), ['traffic80']);
      // 1.4.1: again at 10 % left
      expect(kinds(used: 90 * gb), ['traffic90']);
      expect(kinds(used: 99 * gb), ['traffic90']);
      expect(kinds(used: 100 * gb), ['traffic100']);
      expect(kinds(used: 120 * gb), ['traffic100']);
    });

    test('unlimited traffic never alerts', () {
      expect(kinds(used: 99 * gb, total: 0), isEmpty);
      expect(kinds(used: 99 * gb, total: 20 * 1024 * gb * 1024), isEmpty);
    });

    test('expiry within 3 days alerts, past or far does not', () {
      expect(kinds(expire: now.add(const Duration(days: 3))), ['expire']);
      expect(kinds(expire: now.add(const Duration(days: 4))), isEmpty);
      expect(kinds(expire: now.subtract(const Duration(days: 1))), isEmpty);
      expect(kinds(expire: DateTime.fromMillisecondsSinceEpoch(0)), isEmpty);
    });

    test('key changes with the billing period', () {
      final a = museSubscriptionAlerts(profileId: 'p', upload: 0, download: 95 * gb, total: 100 * gb, expire: DateTime(2026, 11, 1), now: now);
      final b = museSubscriptionAlerts(profileId: 'p', upload: 0, download: 95 * gb, total: 100 * gb, expire: DateTime(2026, 12, 1), now: now);
      expect(a.single.key, isNot(b.single.key));
    });
  });

  group('keep-alive guide', () {
    test('shown once, only on Android, only when something is missing', () {
      expect(museShouldShowKeepAliveGuide(isAndroid: true, alreadyShown: false, batteryIgnored: false, autostartVisited: false), isTrue);
      expect(museShouldShowKeepAliveGuide(isAndroid: true, alreadyShown: true, batteryIgnored: false, autostartVisited: false), isFalse);
      expect(museShouldShowKeepAliveGuide(isAndroid: false, alreadyShown: false, batteryIgnored: false, autostartVisited: false), isFalse);
      expect(museShouldShowKeepAliveGuide(isAndroid: true, alreadyShown: false, batteryIgnored: true, autostartVisited: true), isFalse);
      expect(museShouldShowKeepAliveGuide(isAndroid: true, alreadyShown: false, batteryIgnored: true, autostartVisited: false), isTrue);
    });
  });

  group('updater', () {
    test('picks the re-signed arm64 asset', () {
      final r = museParseRelease({
        'tag_name': 'v1.1.0',
        'prerelease': false,
        'assets': [
          {'name': 'hiddify-arm64-debug.apk', 'browser_download_url': 'https://github.com/yywgov/muse-vpn/releases/download/v1/other', 'size': 1},
          {'name': 'Chuanyun-Android-arm64.apk', 'browser_download_url': 'https://github.com/yywgov/muse-vpn/releases/download/v1/apk', 'size': 42},
        ],
      });
      expect(r?.version, '1.1.0');
      expect(r?.apkUrl, 'https://github.com/yywgov/muse-vpn/releases/download/v1/apk');
      expect(r?.apkSize, 42);
    });

    test('windows picks the zip and keeps the release page', () {
      final json = {
        'tag_name': 'v1.2.0',
        'prerelease': false,
        'html_url': 'https://github.com/yywgov/muse-vpn/releases/tag/v1.2.0',
        'assets': [
          {'name': 'Chuanyun-Android-arm64.apk', 'browser_download_url': 'https://github.com/yywgov/muse-vpn/releases/download/v1/apk', 'size': 42},
          {'name': 'Chuanyun-Windows-x64.zip', 'browser_download_url': 'https://github.com/yywgov/muse-vpn/releases/download/v1/zip', 'size': 7},
        ],
      };
      final r = museParseRelease(json, windows: true);
      expect(r?.apkUrl, 'https://github.com/yywgov/muse-vpn/releases/download/v1/zip');
      expect(museIsWindowsInstaller(r!), isFalse);
      expect(r.pageUrl, 'https://github.com/yywgov/muse-vpn/releases/tag/v1.2.0');
      expect(museParseRelease({...json, 'assets': []}, windows: true), isNull);
    });

    test('windows prefers the Setup.exe installer over the zip', () {
      final json = {
        'tag_name': 'v1.2.0',
        'prerelease': false,
        'assets': [
          {'name': 'Chuanyun-Windows-x64.zip', 'browser_download_url': 'https://github.com/yywgov/muse-vpn/releases/download/v1/zip', 'size': 7},
          {'name': 'Chuanyun-Windows-x64-Setup.exe', 'browser_download_url': 'https://github.com/yywgov/muse-vpn/releases/download/v1/setup.exe', 'size': 9},
        ],
      };
      final r = museParseRelease(json, windows: true);
      expect(r?.apkUrl, 'https://github.com/yywgov/muse-vpn/releases/download/v1/setup.exe');
      expect(r?.apkSize, 9);
      expect(museIsWindowsInstaller(r!), isTrue);
    });

    test('prereleases are skipped and versions compare', () {
      expect(museParseRelease({'tag_name': 'v1.2.0-test.1', 'prerelease': true, 'assets': []}), isNull);
      expect(museIsNewer('1.1.0', '1.0.0'), isTrue);
      expect(museIsNewer('1.0.0', '1.1.0'), isFalse);
      expect(museIsNewer('garbage', '1.0.0'), isFalse);
    });
  });
}
