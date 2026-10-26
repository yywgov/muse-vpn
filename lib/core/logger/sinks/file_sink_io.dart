import 'dart:io';

String? _path;

bool get isLogFileOpen => _path != null;

/// Opens by creating the file and proving it is writable, so a bad path is
/// known now rather than silently swallowed at the first error worth recording.
void openLogFile(String path) {
  try {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('', mode: FileMode.append);
    _path = path;
  } catch (_) {
    _path = null;
  }
}

/// Written straight through, no batching.
///
/// Only errors reach this file, and they are rare, so a syscall each is cheap
/// and nothing can be sitting in memory when the crash that follows takes the
/// app down.
void writeLogLine(String line) {
  final path = _path;
  if (path == null) return;

  try {
    // 穿云 1.6.0 (#175): every 64 lines check the size; over 5 MB the file rotates (3 kept)
    if (++_writes % 64 == 0) museRotateLogFile(path);
    File(path).writeAsStringSync('$line\n', mode: FileMode.append);
  } catch (_) {
    // A log file that cannot be written must never take the app down.
  }
}

var _writes = 0;

/// 穿云 1.6.0 (#175): the size a log file may reach before it rotates, and how many files are kept
/// (the current one plus `.1`, `.2`).
const museLogMaxBytes = 5 * 1024 * 1024;
const museLogKeep = 3;

/// Rotates [path] when it is larger than [maxBytes]: path → path.1 → path.2 …, the oldest beyond
/// [keep] is deleted. Returns true when it rotated. Never throws.
bool museRotateLogFile(String path, {int maxBytes = museLogMaxBytes, int keep = museLogKeep}) {
  try {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() <= maxBytes) return false;
    final oldest = File('$path.${keep - 1}');
    if (oldest.existsSync()) oldest.deleteSync();
    for (var i = keep - 2; i >= 1; i--) {
      final from = File('$path.$i');
      if (from.existsSync()) from.renameSync('$path.${i + 1}');
    }
    f.renameSync('$path.1');
    File(path).writeAsStringSync('');
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> closeLogFile() async {
  _path = null;
}

/// Writes [lines] to [path] in one go, replacing whatever was there. Used by
/// the logs page to export the in-memory history, which is a different file.
Future<void> writeLinesToFile(String path, Iterable<String> lines) async {
  await File(path).writeAsString(lines.join('\n'));
}
