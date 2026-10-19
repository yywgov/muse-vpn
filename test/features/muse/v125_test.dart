// 穿云 1.2.5: node order modes / region sections, byte sizes, subscription summary, current node line.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/home/node_label.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';

typedef N = ({String name, bool group, int delay});

N n(String name, int delay) => (name: name, group: false, delay: delay);
N g(String name) => (name: name, group: true, delay: 0);

List<String> order(List<N> items, MuseNodeSort sort) => museOrderNodes<N>(
  items,
  sort: sort,
  isGroup: (e) => e.group,
  delay: (e) => e.delay,
  isValidDelay: (d) => d > 0 && d < 65535,
  region: (e) => museRegionCode(e.name),
).map((e) => e.name).toList();

void main() {
  final items = [
    n('日本 01', 300),
    g('自动选择'),
    n('香港 01', 200),
    n('其他节点', 50),
    n('日本 02', 100),
    n('香港 02', 65535),
    n('香港 03', 0),
  ];

  group('节点排序', () {
    test('按延迟: groups, fastest, untested, timeouts', () {
      expect(order(items, MuseNodeSort.delay), ['自动选择', '其他节点', '日本 02', '香港 01', '日本 01', '香港 03', '香港 02']);
    });

    test('订阅顺序: groups on top, nodes as listed', () {
      expect(order(items, MuseNodeSort.original), ['自动选择', '日本 01', '香港 01', '其他节点', '日本 02', '香港 02', '香港 03']);
    });

    test('按地区: region by first appearance, fastest inside, unknown last', () {
      expect(order(items, MuseNodeSort.region), ['自动选择', '日本 02', '日本 01', '香港 01', '香港 03', '香港 02', '其他节点']);
    });

    test('preference keys round-trip, unknown falls back to 按延迟', () {
      for (final m in MuseNodeSort.values) {
        expect(MuseNodeSort.fromKey(m.key), m);
      }
      expect(MuseNodeSort.fromKey('???'), MuseNodeSort.delay);
      expect(MuseNodeSort.region.title, '按地区');
    });

    test('region sections skip groups and follow the list', () {
      final ordered = museOrderNodes<N>(
        items,
        sort: MuseNodeSort.region,
        isGroup: (e) => e.group,
        delay: (e) => e.delay,
        isValidDelay: (d) => d > 0 && d < 65535,
        region: (e) => museRegionCode(e.name),
      );
      final sections = museRegionSections<N>(ordered, isGroup: (e) => e.group, region: (e) => museRegionCode(e.name));
      expect(sections.map((s) => s.region).toList(), ['JP', 'HK', null]);
      expect(sections.map((s) => s.items.length).toList(), [2, 3, 1]);
    });
  });

  test('byte sizes', () {
    expect(museBytes(-5), '0 B');
    expect(museBytes(512), '512 B');
    expect(museBytes(12 * 1024), '12 KB');
    expect(museBytes((3.4 * 1024 * 1024).round()), '3.4 MB');
    expect(museBytes(150 * 1024 * 1024), '150 MB');
    expect(museBytes((12.3 * 1024 * 1024 * 1024).round()), '12.3 GB');
    expect(museBytes(120 * 1024 * 1024 * 1024), '120 GB');
  });

  group('订阅摘要', () {
    final now = DateTime(2026, 10, 20, 12);
    const gb = 1024 * 1024 * 1024;

    test('traffic, days left, updated', () {
      expect(
        museSubscriptionSummary(
          upload: 2 * gb,
          download: (10.3 * gb).round(),
          total: 100 * gb,
          expire: now.add(const Duration(days: 23, hours: 2)),
          lastUpdate: now.subtract(const Duration(hours: 3)),
          now: now,
        ),
        '已用 12.3 GB / 100 GB · 剩 23 天 · 3 小时前更新',
      );
    });

    test('used up, expired, today, unlimited, no expiry', () {
      String s({int used = 0, int total = 0, DateTime? expire}) => museSubscriptionSummary(
        upload: 0,
        download: used,
        total: total,
        expire: expire ?? DateTime(1970),
        lastUpdate: now,
        now: now,
      );
      expect(s(used: 100 * gb, total: 100 * gb), '流量已用完 · 刚刚更新');
      expect(s(expire: now.subtract(const Duration(days: 1))), '已到期 · 刚刚更新');
      expect(s(expire: now.add(const Duration(hours: 5))), '今天到期 · 刚刚更新');
      expect(s(total: 20 * 1024 * gb), '刚刚更新'); // 20 TB = unlimited
      expect(s(), '刚刚更新');
    });

    test('updated ago', () {
      expect(museUpdatedAgo(now.subtract(const Duration(seconds: 20)), now: now), '刚刚更新');
      expect(museUpdatedAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 分钟前更新');
      expect(museUpdatedAgo(now.subtract(const Duration(days: 2, hours: 1)), now: now), '2 天前更新');
    });
  });

  test('当前节点 line', () {
    expect(museCurrentNodeText(name: '香港 01'), '🇭🇰 香港 01');
    expect(museCurrentNodeText(name: '🇯🇵 东京 02'), '🇯🇵 东京 02');
    expect(museCurrentNodeText(name: 'Node A'), 'Node A');
    expect(museCurrentNodeText(name: 'auto', groupLabel: '自动最快', groupPick: '东京 02'), '自动最快 → 🇯🇵 东京 02');
    expect(museCurrentNodeText(name: 'balance', groupLabel: '负载均衡'), '负载均衡');
    expect(museCurrentNodeText(name: ''), '');
  });

  testWidgets('sort menu lists the three modes with the current one checked', (tester) async {
    var picked = MuseNodeSort.delay;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PopupMenuButton<MuseNodeSort>(
              key: const ValueKey('sort'),
              onSelected: (m) => setState(() => picked = m),
              itemBuilder: (_) => [
                for (final m in MuseNodeSort.values)
                  CheckedPopupMenuItem(value: m, checked: m == picked, child: Text(m.title)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sort')));
    await tester.pumpAndSettle();
    expect(find.text('按延迟'), findsOneWidget);
    expect(find.text('订阅顺序'), findsOneWidget);
    await tester.tap(find.text('按地区'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked, MuseNodeSort.region);
  });
}
