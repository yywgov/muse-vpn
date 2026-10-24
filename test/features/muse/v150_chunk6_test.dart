// 穿云 1.5.0 (batch 1, chunk 6): weekly traffic, update download resume.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/stats_tools.dart';
import 'package:hiddify/features/muse/update/muse_updater.dart';

void main() {
  group('#172 weekly traffic', () {
    test('Monday to Sunday, oldest first, missing days count 0', () {
      final log = MuseTrafficLog({
        '2026-10-19': (1, 10), // Monday
        '2026-10-24': (2, 20), // Saturday, same week
        '2026-10-18': (5, 50), // Sunday, week before
      });
      final weeks = log.lastWeeks(DateTime(2026, 10, 24), 3);
      expect(weeks.map((w) => w.$1), ['2026-10-05', '2026-10-12', '2026-10-19']);
      expect(weeks.last.$2, 3);
      expect(weeks.last.$3, 30);
      expect(weeks[1].$2 + weeks[1].$3, 55);
      expect(weeks.first.$2 + weeks.first.$3, 0);
    });
    test('a Monday starts its own week', () {
      final w = MuseTrafficLog(const {}).lastWeeks(DateTime(2026, 10, 19), 1);
      expect(w.single.$1, '2026-10-19');
    });
  });

  group('#207 download resume', () {
    test('a part counts as done only at its exact length', () {
      final dir = Directory.systemTemp.createTempSync('muse_part');
      try {
        final f = File('${dir.path}/a.part0')..writeAsBytesSync(List.filled(100, 1));
        expect(museRangePartDone(f.path, (0, 99)), isTrue);
        expect(museRangePartDone(f.path, (0, 199)), isFalse);
        expect(museRangePartDone('${dir.path}/missing', (0, 99)), isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
