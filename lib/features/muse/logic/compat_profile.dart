// 穿云 1.7.0 M3-4 - subscriptions in 兼容内核 mode (订阅兼容模式).
//
// 兼容内核 reads a subscription as it came: a YAML subscription keeps its own proxy groups and
// rules, share links stay links. So in that mode an added or updated subscription is saved exactly
// as downloaded (Windows: by 兼容内核's own check; Android: here, because 兼容内核 lives in its own
// process and only runs while connected). 标准内核 needs its own JSON, so when the user goes back
// to it the saved body is converted by 标准内核 at the next connect, and the original body is kept
// next to the profile (`<profile>.compat`). Switching back to 兼容内核 puts the original back, so
// going back and forth never loses the subscription's groups and rules. Every save of the profile
// (add, update, edit) drops that copy, so it can never be older than the profile.
//
// Nothing is deleted from a subscription on the way: nodes 兼容内核 cannot run stay in the saved
// body and are listed greyed out with the reason; subscriptions are never removed by any of this.
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';

/// The copy of the original subscription body kept while the profile holds 标准内核's conversion.
String museCompatOriginalPath(String profilePath) => '$profilePath.compat';

/// Whether [content] is in the form 标准内核 saves profiles in (JSON). Cheap on purpose: it runs
/// before every 标准内核 connect, and only a body 兼容内核 kept (YAML, links) needs converting.
bool museIsStandardProfile(String content) {
  final s = content.trimLeft();
  return s.startsWith('{') || s.startsWith('[');
}

/// Formats 兼容内核 reads natively and keeps as they came. Others (SIP008, a WireGuard .conf) are
/// converted by 标准内核 first, which 兼容内核 then reads as well.
bool museCompatReadsNatively(String body) {
  if (museIsWireGuardConf(body)) return false;
  return switch (museDetectSubFormat(body)) {
    MuseSubFormat.clash || MuseSubFormat.links || MuseSubFormat.base64 || MuseSubFormat.singBox => true,
    _ => false,
  };
}

/// What the profile file needs before [kind] runs it.
enum MuseProfilePrep {
  /// already in a form this core reads
  none,

  /// 标准内核, the profile holds a subscription body: convert it (keeping the original)
  convertForStandard,

  /// 兼容内核, the profile holds 标准内核's conversion and the original is kept: put it back
  restoreOriginal,
}

MuseProfilePrep museProfilePrep({required MuseCoreKind kind, required bool isStandardProfile, required bool hasOriginal}) =>
    switch (kind) {
      MuseCoreKind.standard => isStandardProfile ? MuseProfilePrep.none : MuseProfilePrep.convertForStandard,
      MuseCoreKind.compat => hasOriginal ? MuseProfilePrep.restoreOriginal : MuseProfilePrep.none,
    };

/// The core the next connection (and a subscription saved now) runs on: Windows the core the app
/// started with (its library is loaded once; a missing 兼容内核 library falls back to 标准内核 and
/// resets this), Android the choice saved now (each connect picks its service).
MuseCoreKind museEffectiveCoreKind({required bool desktop, required Object? savedKey}) =>
    desktop ? MuseCoreSelection.startup : MuseCoreKind.fromKey(savedKey);

/// File side of the above (unit-tested with a temp directory).
class MuseCompatProfileStore {
  const MuseCompatProfileStore();

  /// Saves [body] as the profile exactly as it came (written next to it and renamed, so a failed
  /// write never leaves half a profile), after the light check below. Returns the problem, or
  /// null when saved.
  Future<String?> saveAsIs(File profile, String body) async {
    final problem = museCompatBodyProblem(body);
    if (problem != null) return problem;
    await profile.parent.create(recursive: true);
    final tmp = File('${profile.path}.saving');
    await tmp.writeAsString(body, flush: true);
    if (await profile.exists()) await profile.delete();
    await tmp.rename(profile.path);
    await dropOriginal(profile);
    return null;
  }

  /// The profile was saved (any core): a kept original is now older than it.
  Future<void> dropOriginal(File profile) async {
    final original = File(museCompatOriginalPath(profile.path));
    if (await original.exists()) await original.delete();
  }

  /// Gets the profile ready for [kind]. [convert] has 标准内核 read the body at its argument path
  /// and save its conversion over the profile; it answers an error message, or null when done.
  /// A failed conversion leaves the profile exactly as it was.
  Future<String?> prepare(File profile, MuseCoreKind kind, Future<String?> Function(String bodyPath) convert) async {
    if (!await profile.exists()) return null; // the core reports a missing profile itself
    final original = File(museCompatOriginalPath(profile.path));
    // 兼容内核 reads every form: the profile is only read for 标准内核
    final content = kind == MuseCoreKind.standard ? await profile.readAsString() : '';
    switch (museProfilePrep(
      kind: kind,
      isStandardProfile: kind == MuseCoreKind.compat || museIsStandardProfile(content),
      hasOriginal: await original.exists(),
    )) {
      case MuseProfilePrep.none:
        return null;
      case MuseProfilePrep.restoreOriginal:
        if (await profile.exists()) await profile.delete();
        await original.rename(profile.path);
        return null;
      case MuseProfilePrep.convertForStandard:
        await original.writeAsString(content, flush: true);
        final error = await convert(original.path);
        if (error == null) return null;
        // put the body back unchanged
        await profile.writeAsString(content, flush: true);
        await original.delete();
        return error;
    }
  }
}

/// Light check before a body is saved as it came (兼容内核 checks it fully when it starts):
/// null when it is a subscription this core reads, otherwise why not.
String? museCompatBodyProblem(String body) {
  if (body.trim().isEmpty) return '订阅内容为空';
  if (!museCompatReadsNatively(body)) return '无法识别的订阅格式';
  if (museDetectSubFormat(body) == MuseSubFormat.clash &&
      !RegExp(r'^(proxies|proxy-providers)\s*:', multiLine: true).hasMatch(body)) {
    return '订阅里没有节点';
  }
  return null;
}

/// Node names of a saved profile in any form it can be in: 标准内核's JSON, a YAML
/// subscription (top-level `proxies:` entries), or share links (base64 or plain). Used for the
/// 「新增 / 移除」 summary after an update, whichever core saved it.
List<String> museProfileNodeNames(String raw) {
  switch (museDetectSubFormat(raw)) {
    case MuseSubFormat.singBox:
      return museConfigNodeNames(raw);
    case MuseSubFormat.clash:
      return _yamlProxyNames(raw);
    case MuseSubFormat.links || MuseSubFormat.base64:
      return [
        for (final line in const LineSplitter().convert(museSubPlainText(raw)))
          if (line.contains('://') && _linkName(line.trim()) != null) _linkName(line.trim())!,
      ];
    default:
      return const [];
  }
}

String? _linkName(String line) {
  final hash = line.lastIndexOf('#');
  if (hash < 0 || hash == line.length - 1) return null;
  final frag = line.substring(hash + 1);
  try {
    return Uri.decodeComponent(frag).trim();
  } catch (_) {
    return frag.trim();
  }
}

/// `name:` of each entry of the top-level `proxies:` list (block or flow style); no YAML library
/// needed for this summary.
List<String> _yamlProxyNames(String raw) {
  final names = <String>[];
  var inProxies = false;
  final nameRe = RegExp(r'''(?:^|[{,\s-])name\s*:\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^']|'')*)'|([^,}\n#]+))''');
  for (final line in const LineSplitter().convert(raw)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final topLevel = !line.startsWith(' ') && !line.startsWith('\t') && !line.startsWith('-');
    if (topLevel) {
      inProxies = RegExp(r'^proxies\s*:').hasMatch(line);
      continue;
    }
    if (!inProxies) continue;
    final t = line.trimLeft();
    // a new list entry, or the entry's own name line in block style
    if (!t.startsWith('-') && !RegExp(r'^name\s*:').hasMatch(t)) continue;
    final m = nameRe.firstMatch(t.startsWith('-') ? t.substring(1) : t);
    if (m == null) continue;
    final name = (m.group(1) ?? m.group(2)?.replaceAll("''", "'") ?? m.group(3) ?? '').trim();
    if (name.isNotEmpty) names.add(name);
  }
  return names;
}
