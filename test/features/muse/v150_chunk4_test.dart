// 穿云 1.5.0 (batch 1, chunk 4): automatic backups before restore / update, Windows toast sender.
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/notify.dart';
import 'package:hiddify/features/muse/logic/sync_core.dart';

void main() {
  group('#197 / #206 automatic backups', () {
    test('name round-trips', () {
      final at = DateTime(2026, 10, 24, 17, 5, 9);
      final name = museAutoBackupName('restore', at);
      expect(name, 'auto-restore-20261024-170509.json');
      final meta = museParseAutoBackupName(name)!;
      expect(meta.reason, 'restore');
      expect(meta.at, at);
      expect(museAutoBackupReasonTitle('update'), '更新前');
      expect(museShortDateTime(at), '10-24 17:05');
    });
    test('other files are not backups', () {
      expect(museParseAutoBackupName('chuanyun-backup.json'), isNull);
      expect(museParseAutoBackupName('auto-restore-2026.json'), isNull);
    });
    test('only the newest 5 stay; other files untouched', () {
      final names = [
        for (var d = 1; d <= 7; d++) museAutoBackupName(d.isEven ? 'update' : 'restore', DateTime(2026, 10, d)),
        'notes.txt',
      ];
      final prune = museAutoBackupsToPrune(names);
      expect(prune, [museAutoBackupName('restore', DateTime(2026, 10, 1)), museAutoBackupName('update', DateTime(2026, 10, 2))]);
      expect(museAutoBackupsToPrune(names.take(5)), isEmpty);
    });
  });

  group('#140 Windows toast sender', () {
    test('the installed app id when the Start-menu shortcut exists', () {
      final env = {'APPDATA': r'C:\Users\u\AppData\Roaming', 'ProgramData': r'C:\ProgramData'};
      expect(museWindowsToastAppId(env, (p) => p == r'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\穿云.lnk'), museWindowsAppId);
      expect(museWindowsToastAppId(env, (p) => p.startsWith(r'C:\Users')), museWindowsAppId);
    });
    test('PowerShell (portable zip) otherwise', () {
      final id = museWindowsToastAppId(const {}, (_) => true);
      expect(id, contains('powershell.exe'));
      expect(museWindowsToastScript('a', 'b', appId: id), contains(r"'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'"));
      expect(museWindowsToastScript('a', 'b', appId: museWindowsAppId), contains("'Chuanyun.App'"));
    });
  });
}
