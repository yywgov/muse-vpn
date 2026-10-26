// 穿云 1.6.0 C1: colour scheme, surface levels, superellipse shapes, type ladder, components.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/widget/muse_card.dart';
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';

Widget _app(Widget child, {Brightness b = Brightness.light, double scale = 1, Size size = const Size(390, 800)}) => MediaQuery(
  data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
  child: MaterialApp(
    theme: ThemeData(colorScheme: museSeededScheme(brightness: b)),
    home: Scaffold(body: child),
  ),
);

void main() {
  group('museSeededScheme', () {
    for (final style in MuseColorStyle.values) {
      for (final b in Brightness.values) {
        test('${style.name} ${b.name}: near-neutral surfaces, readable accent', () {
          final s = museSeededScheme(brightness: b, style: style);
          final dark = b == Brightness.dark;
          // 着色 tints the surfaces on purpose (chroma up to 10)
          final cap = style == MuseColorStyle.tinted ? MuseTone.maxTintChroma : MuseTone.surfaceChroma;
          for (final c in [s.surface, s.surfaceContainer, s.surfaceContainerHigh, s.surfaceContainerHighest]) {
            expect(museChroma(c), lessThanOrEqualTo(cap + 0.6));
          }
          if (dark) {
            expect(museTone(s.surface), closeTo(MuseTone.darkPage, 1));
            expect(museTone(s.surfaceContainer), closeTo(MuseTone.darkCard, 1));
            expect(museTone(s.surfaceContainerHigh), closeTo(MuseTone.darkBlock, 1));
            expect(museTone(s.surfaceContainerHighest), closeTo(MuseTone.darkInset, 1));
          } else if (style == MuseColorStyle.vivid || style == MuseColorStyle.soft) {
            expect(museChroma(s.surface), lessThanOrEqualTo(MuseTone.paperChroma + 0.6));
          }
          if (style == MuseColorStyle.vivid || style == MuseColorStyle.tinted) {
            final t = museTone(s.primary);
            if (dark) {
              expect(t, inInclusiveRange(MuseTone.minDarkAccent - 1, MuseTone.maxDarkAccent + 1));
            } else {
              expect(t, inInclusiveRange(MuseTone.minAccent - 1, MuseTone.maxAccent + 1));
            }
          }
        });
      }
    }

    test('vivid light keeps the brand blue itself', () {
      expect(museSeededScheme(brightness: Brightness.light).primary.toARGB32(), museBrandSeed.toARGB32());
    });

    test('status colours never follow the seed', () {
      final a = museSeededScheme(brightness: Brightness.light);
      final b = museSeededScheme(seed: museSeedPresets[4], brightness: Brightness.light);
      expect(a.success, b.success);
      expect(a.warning, b.warning);
      expect(a.destructive, b.destructive);
      expect(a.secondSeries.a, closeTo(0.45, 0.01));
    });

    test('pure black lowers dark surfaces only', () {
      final d = museSeededScheme(brightness: Brightness.dark, pureBlack: true);
      expect(d.surface.toARGB32(), 0xFF000000);
      expect(museTone(d.surfaceContainer), lessThan(MuseTone.darkCard));
      final l = museSeededScheme(brightness: Brightness.light, pureBlack: true);
      expect(l.surface, museSeededScheme(brightness: Brightness.light).surface);
    });

    test('delay colours', () {
      final s = museSeededScheme(brightness: Brightness.light);
      expect(s.delayColor(null), isNull);
      expect(s.delayColor(0), s.error);
      expect(s.delayColor(120), s.success);
      expect(s.delayColor(900), s.warning);
    });

    test('style keys round-trip', () {
      for (final s in MuseColorStyle.values) {
        expect(MuseColorStyle.fromKey(s.key), s);
      }
      expect(MuseColorStyle.fromKey('nope'), MuseColorStyle.vivid);
    });
  });

  test('surface levels step up and stop at inset', () {
    expect(MuseSurface.page.above, MuseSurface.card);
    expect(MuseSurface.block.above, MuseSurface.inset);
    expect(MuseSurface.inset.above, MuseSurface.inset);
    final d = museSeededScheme(brightness: Brightness.dark);
    final tones = MuseSurface.values.map((l) => museTone(l.color(d))).toList();
    for (var i = 1; i < tones.length; i++) {
      expect(tones[i], greaterThan(tones[i - 1]));
    }
  });

  test('shape fit picks a step at most a third of the shortest side', () {
    expect(MuseShape.fit(const Size(200, 90)), MuseRadiusScale.xxl);
    expect(MuseShape.fit(const Size(200, 50)), MuseRadiusScale.md);
    expect(MuseShape.fit(const Size(10, 10)), 0);
    expect(MuseShape.card, isA<RoundedSuperellipseBorder>());
  });

  test('type ladder line heights', () {
    expect(MuseTextLevel.values.length, 13);
    expect(MuseTextLevel.body.size, 17);
    expect(MuseTextLevel.caption2.lineHeight, 13);
  });

  testWidgets('MuseCard nests one level up and shows selection by outline', (t) async {
    await t.pumpWidget(_app(const MuseCard(selected: true, child: MuseCard(child: Text('inner')))));
    final ctx = t.element(find.text('inner'));
    expect(MuseSurfaceScope.of(ctx), MuseSurface.block);
    final mats = t.widgetList<Material>(find.descendant(of: find.byType(MuseCard), matching: find.byType(Material))).toList();
    expect((mats.first.shape! as RoundedSuperellipseBorder).side.width, greaterThan(0));
  });

  testWidgets('selection badge kinds', (t) async {
    await t.pumpWidget(_app(const Row(children: [MuseSelectionBadge(), MuseSelectionBadge(kind: MuseBadgeKind.preferred)])));
    expect(find.byKey(const ValueKey('muse_badge_check')), findsOneWidget);
    expect(find.byKey(const ValueKey('muse_badge_preferred')), findsOneWidget);
  });

  testWidgets('snap sheet opens at the lower detent, expands, closes on back', (t) async {
    await t.pumpWidget(_app(Builder(
      builder: (c) => TextButton(
        onPressed: () => showMuseSnapSheet<void>(c, title: '标题', builder: (_, ctl) => ListView(controller: ctl, children: [for (var i = 0; i < 40; i++) ListTile(title: Text('r$i'))])),
        child: const Text('open'),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('muse_snap_sheet')), findsOneWidget);
    final h0 = t.getSize(find.byKey(const ValueKey('muse_snap_sheet'))).height;
    expect(h0, closeTo(600 * 9 / 16, 30));
    await t.drag(find.text('r1'), const Offset(0, -300));
    await t.pumpAndSettle();
    final h1 = t.getSize(find.byKey(const ValueKey('muse_snap_sheet'))).height;
    expect(h1, greaterThan(h0));
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    nav.maybePop();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('muse_snap_sheet')), findsNothing);
  });

  testWidgets('anchor menu opens and runs an item', (t) async {
    var hit = 0;
    await t.pumpWidget(_app(Center(
      child: MuseAnchorMenu(
        items: [MuseMenuItem(label: '更新', onTap: () => hit++), const MuseMenuItem(label: '删除', destructive: true, checked: true)],
        builder: (c, toggle) => TextButton(onPressed: toggle, child: const Text('menu')),
      ),
    )));
    await t.tap(find.text('menu'));
    await t.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
    await t.tap(find.text('更新'));
    await t.pumpAndSettle();
    expect(hit, 1);
  });

  testWidgets('section group at 2x text on a narrow screen does not overflow', (t) async {
    await t.pumpWidget(_app(
      const SingleChildScrollView(
        child: MuseSectionGroup(
          title: '外观',
          summary: '跟随系统 · 品牌蓝 · 鲜明',
          children: [MuseSwitchRow(title: '纯黑模式（深色时生效）', subtitle: '深色下页面背景改为纯黑', value: true, onChanged: null)],
        ),
      ),
      scale: 2,
      size: const Size(320, 640),
    ));
    expect(t.takeException(), isNull);
  });
}
