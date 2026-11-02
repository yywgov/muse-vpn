// 穿云 1.10.0 - the GitHub release body for a tag: that version's lines of the in-app changelog as a
// list (the app's 「发现新版本」 dialog shows them, see museReleaseNotes).
// usage: dart run tool/ci/release_notes.dart <tag or version> [out file]
import 'dart:io';

import 'package:hiddify/features/muse/data/changelog.dart';

String museReleaseBody(String tag, Map<String, List<String>> changelog) {
  final version = tag.replaceFirst(RegExp('^v'), '').split('+').first;
  final lines = changelog[version] ?? const <String>[];
  if (lines.isEmpty) return '';
  return [for (final l in lines) '- $l'].join('\n');
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: release_notes.dart <tag> [out]');
    exit(2);
  }
  final body = museReleaseBody(args.first, museChangelog);
  if (body.isEmpty) {
    stderr.writeln('no changelog entry for ${args.first}');
    exit(1);
  }
  if (args.length > 1) {
    File(args[1]).writeAsStringSync('$body\n');
  } else {
    stdout.writeln(body);
  }
}
