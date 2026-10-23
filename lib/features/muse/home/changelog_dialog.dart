// 穿云 1.5.0 - 更新内容: the dialog (shown by itself only for a feature release) and the dot that
// a small update leaves on 设置 › 关于 › 更新内容 instead.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/data/changelog.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether this version's 更新内容 is still unread (the dot on 设置 / 关于 / 更新内容).
final museChangelogDotProvider = Provider<bool>((ref) {
  final version = ref.watch(museAppVersionProvider);
  if (version == null) return false;
  return museChangelogUnread(version: version, seen: ref.watch(MusePrefs.changelogSeen));
});

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

/// A small red dot next to [child] when [show].
class MuseDot extends StatelessWidget {
  const MuseDot({super.key, required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      show ? Badge(key: const ValueKey('muse_dot'), smallSize: MuseSize.dot, backgroundColor: MusePalette.red, child: child) : child;
}
