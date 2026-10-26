import 'package:hiddify/features/muse/data/muse_prefs_migration.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('breakpoints and radius scale', () {
    expect(MuseBreak.mobile, 600);
    expect(MuseBreak.laptop, 840);
    expect(MuseRadiusScale.fit(20, 28), 10);
    expect(MuseRadiusScale.fit(100, 28), 28);
  });

  testWidgets('adaptive space shrinks only above 1x text', (t) async {
    late double a, b, c;
    Widget host(double s, void Function(double) f) => MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(s)),
          child: Builder(builder: (ctx) {
            f(museAdaptiveSpace(ctx, 16));
            return const SizedBox();
          }),
        );
    await t.pumpWidget(host(1, (v) => a = v));
    await t.pumpWidget(host(2, (v) => b = v));
    await t.pumpWidget(host(0.8, (v) => c = v));
    expect(a, 16);
    expect(b, 16);
    expect(c, closeTo(14.4, 0.001));
  });

  group('prefs migration', () {
    test('fresh and corrupt versions go to current', () {
      final a = <String, Object?>{};
      expect(musePrefsMigrate(a), musePrefsVersionCurrent);
      final b = <String, Object?>{musePrefsVersionKey: 'x'};
      expect(musePrefsMigrate(b), musePrefsVersionCurrent);
    });
    test('idempotent', () {
      final a = <String, Object?>{'k': 1};
      musePrefsMigrate(a);
      final snap = Map.of(a);
      musePrefsMigrate(a);
      expect(a, snap);
    });
    test('failing step rolls back', () {
      final a = <String, Object?>{'k': 1, musePrefsVersionKey: 1};
      final v = musePrefsMigrate(a, steps: {1: (p) {
        p['k'] = 2;
        throw StateError('x');
      }});
      expect(v, 1);
      expect(a['k'], 1);
    });
  });
}
