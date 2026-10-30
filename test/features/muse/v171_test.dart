// 穿云 1.7.1 配色修正: the primary is the picked colour itself, 忠实 is the default style, the
// greyish presets are replaced, and old preferences migrate.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/data/muse_prefs_migration.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _presets = <String, int>{
  'jingtailan': 0xFF2775B6,
  'baolan': 0xFF4B5CC4,
  'zhuqing': 0xFF789262,
  'songhua': 0xFFBCE672,
  'yanzhi': 0xFF9D2933,
  'zaohong': 0xFFC32136,
  'tenghuang': 0xFFFFB61E,
  'qingbi': 0xFF48C0A3,
  'dingxiang': 0xFFCCA4E3,
  'zheshi': 0xFF845A33,
};

void main() {
  tearDown(() => museApplyColorStyle(museDefaultColorStyle));

  group('1.7.1 exact primary', () {
    test('ten presets in order, values as checked against the colour sources', () {
      expect(MuseAccent.values.map((e) => e.key).toList(), _presets.keys.toList());
      for (final a in MuseAccent.values) {
        expect(a.color.toARGB32(), _presets[a.key], reason: a.title);
      }
      expect(museSeedPresets.map((c) => c.toARGB32()).toList(), _presets.values.toList());
      expect(MuseAccent.values.map((e) => e.title).toList(), ['景泰蓝', '宝蓝', '竹青', '松花', '胭脂', '枣红', '藤黄', '青碧', '丁香', '赭石']);
    });

    test('light theme: primary is the picked colour exactly (忠实 / 鲜明 / 着色), custom colours too', () {
      final seeds = [...MuseAccent.values.map((a) => a.color), const Color(0xFF3A5F0B), const Color(0xFFFFEB3B)];
      for (final seed in seeds) {
        for (final style in MuseColorStyle.values.where((s) => s.keepsSeed)) {
          final s = museSeededScheme(seed: seed, brightness: Brightness.light, style: style);
          expect(s.primary.toARGB32(), seed.toARGB32(), reason: '${museHexOf(seed)} ${style.title}');
          expect(s.surfaceTint, s.primary);
        }
      }
    });

    test('dark theme: normal-brightness colours stay exact; too dark ones are lifted, same hue', () {
      for (final a in MuseAccent.values) {
        for (final black in [false, true]) {
          final s = museSeededScheme(seed: a.color, brightness: Brightness.dark, pureBlack: black);
          final page = museSeededScheme(seed: a.color, brightness: Brightness.dark).surface;
          if (museContrast(a.color, page) >= MuseTone.darkPrimaryContrast) {
            expect(s.primary.toARGB32(), a.color.toARGB32(), reason: a.title);
          } else {
            expect(museTone(s.primary), greaterThan(museTone(a.color)), reason: a.title);
            expect(museContrast(s.primary, page), greaterThanOrEqualTo(MuseTone.darkPrimaryContrast), reason: a.title);
            final dh = (Hct.fromInt(s.primary.toARGB32()).hue - Hct.fromInt(a.color.toARGB32()).hue).abs();
            expect(dh < 3 || dh > 357, isTrue, reason: '${a.title} hue');
          }
        }
      }
      // 景泰蓝 / 藤黄 / 青碧 read on the dark page as they are
      for (final a in [MuseAccent.jingtailan, MuseAccent.tenghuang, MuseAccent.qingbi]) {
        expect(museSeededScheme(seed: a.color, brightness: Brightness.dark).primary, a.color, reason: a.title);
      }
    });

    test('onPrimary is black or white by WCAG contrast, always ≥ 4.5:1', () {
      for (final a in MuseAccent.values) {
        for (final style in MuseColorStyle.values.where((s) => s.keepsSeed)) {
          for (final b in Brightness.values) {
            final s = museSeededScheme(seed: a.color, brightness: b, style: style);
            expect(s.onPrimary, anyOf(const Color(0xFFFFFFFF), const Color(0xFF000000)));
            expect(museContrast(s.primary, s.onPrimary), greaterThanOrEqualTo(4.5), reason: '${a.title} ${style.title} $b');
          }
        }
      }
      expect(museOnExact(const Color(0xFFFFB61E)), const Color(0xFF000000)); // 藤黄
      expect(museOnExact(const Color(0xFF2775B6)), const Color(0xFFFFFFFF)); // 景泰蓝
    });

    test('large areas stay generated: container keeps the colour family and readable text', () {
      for (final a in MuseAccent.values) {
        for (final b in Brightness.values) {
          final s = museSeededScheme(seed: a.color, brightness: b);
          expect(s.primaryContainer, isNot(s.primary));
          expect(museContrast(s.primaryContainer, s.onPrimaryContainer), greaterThanOrEqualTo(4.5), reason: a.title);
          expect(museChroma(s.surface), lessThanOrEqualTo(MuseTone.surfaceChroma + 1));
        }
      }
    });

    test('schemes are still computed once per combination', () {
      final before = museSchemeComputations;
      museSeededScheme(seed: const Color(0xFF123456), brightness: Brightness.light);
      museSeededScheme(seed: const Color(0xFF123456), brightness: Brightness.light);
      expect(museSchemeComputations, before + 1);
    });
  });

  group('1.7.1 忠实 default', () {
    test('忠实 is the default and first offered style; unknown keys fall back to it', () {
      expect(museDefaultColorStyle, 'fidelity');
      expect(MuseColorStyle.fromKey(null), MuseColorStyle.fidelity);
      expect(MuseColorStyle.fromKey('bogus'), MuseColorStyle.fidelity);
      expect(MuseColorStyle.offered.first, MuseColorStyle.fidelity);
      expect(MuseColorStyle.fidelity.title, '忠实');
      expect(MusePalette.colorStyle, 'fidelity');
    });

    test('a fresh install reads 忠实', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      await musePrefsMigrateStore(sp);
      expect(sp.getString('muse_color_style'), isNull);
      expect(MusePrefs.colorStyle, isNotNull);
    });
  });

  group('1.7.1 migration', () {
    test('saved 标准 (the old default) → 忠实; other styles untouched', () {
      final p = <String, Object?>{'muse_prefs_version': 2, 'muse_color_style': 'tonalSpot'};
      expect(musePrefsMigrate(p), 3);
      expect(p['muse_color_style'], 'fidelity');
      for (final k in ['vibrant', 'expressive', 'vivid', 'tinted', 'soft', 'monochrome']) {
        final q = <String, Object?>{'muse_prefs_version': 2, 'muse_color_style': k};
        musePrefsMigrate(q);
        expect(q['muse_color_style'], k);
      }
      // already migrated: a 标准 picked later on purpose is kept
      final r = <String, Object?>{'muse_prefs_version': 3, 'muse_color_style': 'tonalSpot'};
      expect(musePrefsMigrate(r), 3);
      expect(r['muse_color_style'], 'tonalSpot');
    });

    test('replaced colours move to the nearest new one; others and custom colours untouched', () {
      const moves = {'pielan': 'baolan', 'yuebai': 'songhua', 'cangyinghui': 'yanzhi', 'zhujin': 'zaohong'};
      moves.forEach((old, now) {
        final p = <String, Object?>{'muse_prefs_version': 2, 'muse_accent': old};
        musePrefsMigrate(p);
        expect(p['muse_accent'], now);
        // a value synced from an older device still reads as the new colour
        expect(MuseAccent.presetOrNull(old)?.key, now);
      });
      for (final keep in ['jingtailan', 'tenghuang', '#3A5F0B', 'blue']) {
        final p = <String, Object?>{'muse_prefs_version': 2, 'muse_accent': keep};
        musePrefsMigrate(p);
        expect(p['muse_accent'], keep);
      }
      expect(MuseAccent.presetOrNull('indigo'), MuseAccent.baolan);
      expect(MuseAccent.presetOrNull('pink'), MuseAccent.zaohong);
    });

    test('the store migration writes back once (1.6.x device → version 3)', () async {
      SharedPreferences.setMockInitialValues({'muse_prefs_version': 2, 'muse_color_style': 'tonalSpot', 'muse_accent': 'yuebai'});
      final sp = await SharedPreferences.getInstance();
      expect(await musePrefsMigrateStore(sp), 3);
      expect(sp.getString('muse_color_style'), 'fidelity');
      expect(sp.getString('muse_accent'), 'songhua');
      expect(sp.getInt('muse_prefs_version'), 3);
    });
  });

  group('1.7.1 release', () {
    test('version 1.7.1+171, 更新说明 and CHANGELOG', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'^version: (\S+)', multiLine: true).firstMatch(pubspec)?.group(1), '1.7.1+171');
      expect(museChangelog.keys.first, '1.7.1');
      expect(museChangelog['1.7.1'], hasLength(3));
      final md = File('CHANGELOG.md').readAsStringSync();
      expect(md.indexOf('### 1.7.1'), lessThan(md.indexOf('### 1.7.0')));
    });

    test('status lights unchanged; sources noted in code', () {
      expect(museStatusGreen, const Color(0xFF0EB83A));
      expect(museStatusYellow, const Color(0xFFFFA631));
      expect(museStatusRed, const Color(0xFFFF461F));
      expect(museStatusGrey, const Color(0xFF758A99));
      final src = File('lib/features/muse/widget/muse_tokens.dart').readAsStringSync();
      expect(src, contains('zhongguose.com'));
      expect(src, contains('qijishow.com'));
    });
  });
}
