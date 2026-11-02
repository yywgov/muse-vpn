// 穿云 1.5.0 - 更新内容: the dialog (shown by itself only for a feature release).
// 1.10.0: 关于 has no 更新内容 row and 设置 no unread dot any more; a new version's notes are shown in
// the 「发现新版本」 dialog of the update check.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The notes for [version] as a dialog; marks them seen.
Future<void> showMuseChangelogDialog(BuildContext context, WidgetRef ref, {required String version, List<String>? notes}) async {
  final lines = notes ?? museChangelog[version] ?? const <String>[];
  await ref.read(MusePrefs.changelogSeen.notifier).update(version);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('changelog_dialog'),
      title: Text('穿云 $version 更新内容'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lines.isEmpty) const Text('这个版本没有更新说明'),
            for (final n in lines)
              Padding(padding: const EdgeInsets.symmetric(vertical: MuseSpace.s4), child: Text('· $n')),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('知道了'))],
    ),
  );
}
