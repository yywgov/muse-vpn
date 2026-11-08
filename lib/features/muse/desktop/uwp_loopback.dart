// 穿云 1.17.0 R12 - Windows 商店应用回环豁免. Store (UWP / AppContainer) apps such as 邮件 or
// 天气 may not connect to 127.0.0.1, so in 系统代理 mode they can't use 穿云. 设置 › 网络 ›
// 「允许商店应用走代理」 exempts them with the system tool CheckNetIsolation — only when the user
// taps it, after saying that Windows will ask for administrator rights (nothing runs at start-up
// or in the background). 「撤销」 removes exactly the exemptions 穿云 added.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:hiddify/utils/platform_utils.dart';

/// Registry key listing the AppContainer (store app) SIDs of the current user.
const museAppContainerKey =
    r'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Mappings';

final _sid = RegExp(r'S-1-15-2(?:-\d+){5,}', caseSensitive: false);

/// AppContainer SIDs out of `reg query <museAppContainerKey>` (one subkey per app), unique, in order.
List<String> museParseAppContainerSids(String regQueryOutput) {
  final out = <String>[];
  for (final line in regQueryOutput.split(RegExp(r'\r?\n'))) {
    if (!line.toUpperCase().contains(r'\MAPPINGS\')) continue;
    final m = _sid.firstMatch(line.split(r'\').last);
    if (m != null && !out.contains(m.group(0)!.toUpperCase())) out.add(m.group(0)!.toUpperCase());
  }
  return out;
}

/// SIDs already exempt, out of `CheckNetIsolation LoopbackExempt -s`.
Set<String> museParseLoopbackExempt(String output) => {for (final m in _sid.allMatches(output)) m.group(0)!.toUpperCase()};

/// The batch file run elevated: one CheckNetIsolation line per SID (`-a` adds, `-d` removes).
String museLoopbackScript(List<String> sids, {bool remove = false}) => [
  '@echo off',
  for (final s in sids) 'CheckNetIsolation.exe LoopbackExempt ${remove ? '-d' : '-a'} -p=$s >nul 2>&1',
  'exit /b 0',
  '',
].join('\r\n');

/// PowerShell arguments that run [scriptPath] elevated (UAC prompt) and wait. Exit code 1223 =
/// the user declined the prompt.
List<String> museLoopbackElevateArgs(String scriptPath) {
  final p = scriptPath.replaceAll("'", "''");
  return [
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-Command',
    "try { \$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', '\"$p\"' -Verb RunAs -WindowStyle Hidden -Wait -PassThru; exit \$p.ExitCode } catch { exit 1223 }",
  ];
}

/// What the tile says after a run.
sealed class MuseLoopbackResult {
  const MuseLoopbackResult();
}

class MuseLoopbackDone extends MuseLoopbackResult {
  const MuseLoopbackDone(this.count, {this.removed = false});
  final int count;
  final bool removed;
}

class MuseLoopbackDeclined extends MuseLoopbackResult {
  const MuseLoopbackDeclined();
}

class MuseLoopbackFailed extends MuseLoopbackResult {
  const MuseLoopbackFailed(this.detail);
  final String detail;
}

String museLoopbackResultText(MuseLoopbackResult r) => switch (r) {
  MuseLoopbackDone(count: 0, removed: false) => '商店应用都已经可以走代理了，不用再开通',
  MuseLoopbackDone(:final count, removed: false) => '已为 $count 个商店应用开通，重新打开这些应用后生效',
  MuseLoopbackDone(:final count, removed: true) => '已撤销穿云开通的 $count 个商店应用',
  MuseLoopbackDeclined() => '没有获得管理员授权，什么都没改',
  MuseLoopbackFailed() => '没有完成，请稍后再试',
};

/// Explanation shown before anything runs.
const museLoopbackExplain =
    '应用商店里的应用（如邮件、天气、Microsoft Store）默认不允许连接本机代理，所以在「系统代理」模式下用不了穿云。\n\n'
    '点「开通」后，Windows 会弹出一次管理员授权，穿云用系统自带的 CheckNetIsolation 为这些应用开通本机回环。'
    '只在你点的这一次执行，不会自动运行；以后可以在这里撤销。TUN 模式不需要这一步。';

abstract final class MuseUwpLoopback {
  /// Exempts every store app not exempt yet; returns the SIDs added via [onAdded].
  static Future<MuseLoopbackResult> exemptAll({required void Function(List<String> added) onAdded}) async {
    if (!PlatformUtils.isWindows) return const MuseLoopbackFailed('not windows');
    try {
      final reg = await Process.run('reg', ['query', museAppContainerKey]).timeout(const Duration(seconds: 15));
      final all = museParseAppContainerSids('${reg.stdout}');
      final listed = await Process.run('CheckNetIsolation.exe', ['LoopbackExempt', '-s']).timeout(const Duration(seconds: 15));
      final exempt = museParseLoopbackExempt('${listed.stdout}');
      final todo = [for (final s in all) if (!exempt.contains(s)) s];
      if (todo.isEmpty) return const MuseLoopbackDone(0);
      final r = await _runElevated(todo, remove: false);
      if (r is MuseLoopbackDone) onAdded(todo);
      return r;
    } catch (e) {
      return MuseLoopbackFailed('$e');
    }
  }

  /// Removes exactly [added] (what 穿云 exempted before).
  static Future<MuseLoopbackResult> revert(List<String> added) async {
    if (!PlatformUtils.isWindows) return const MuseLoopbackFailed('not windows');
    if (added.isEmpty) return const MuseLoopbackDone(0, removed: true);
    try {
      return await _runElevated(added, remove: true);
    } catch (e) {
      return MuseLoopbackFailed('$e');
    }
  }

  static Future<MuseLoopbackResult> _runElevated(List<String> sids, {required bool remove}) async {
    final dir = await Directory.systemTemp.createTemp('chuanyun-loopback');
    try {
      final script = File('${dir.path}\\loopback.cmd');
      await script.writeAsString(museLoopbackScript(sids, remove: remove));
      final r = await Process.run('powershell.exe', museLoopbackElevateArgs(script.path)).timeout(const Duration(minutes: 5));
      if (r.exitCode == 1223) return const MuseLoopbackDeclined();
      if (r.exitCode != 0) return MuseLoopbackFailed('exit ${r.exitCode}');
      return MuseLoopbackDone(sids.length, removed: remove);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
