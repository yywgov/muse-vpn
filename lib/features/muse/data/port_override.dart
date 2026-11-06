// 穿云 1.12.0 - Windows：本地代理端口被别的程序占用时，本次连接自动换一个空闲端口并提示一次
// （「端口 7890 被占用，本次改用 7891」）。设置里的端口不改；下次连接时原端口空出来就用回原端口。
// 系统代理、复制终端代理命令、出口检测等都用这里给出的实际端口。
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:hiddify/features/muse/settings/service_mode_switch.dart' show MuseRead;
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The port this connection uses instead of the saved one (null = the saved one).
final museMixedPortOverrideProvider = StateProvider<int?>((ref) => null);

/// The local proxy port in use right now.
int museEffectiveMixedPort(MuseRead read) => read(museMixedPortOverrideProvider) ?? read(ConfigOptions.mixedPort);

/// Whether nothing listens on 127.0.0.1:[port] (we can bind it).
Future<bool> musePortFree(int port) async {
  try {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await s.close();
    return true;
  } catch (_) {
    return false;
  }
}

/// The first free port after [from] (at most [tries] tried, never [avoid]); null = none found.
Future<int?> museFindFreePort(int from, {int tries = 50, Set<int> avoid = const {}, Future<bool> Function(int)? isFree}) async {
  final free = isFree ?? musePortFree;
  for (var p = from + 1, n = 0; n < tries && p <= 65535; p++, n++) {
    if (avoid.contains(p)) continue;
    if (await free(p)) return p;
  }
  return null;
}

/// The one-time notice.
String musePortMovedText(int from, int to) => '端口 $from 被占用，本次改用 $to';

/// Before a new connection: the saved port when it is free, else a free one ([avoid] = other
/// ports of ours, such as the control port). Returns (port, moved).
Future<(int, bool)> musePickMixedPort(int saved, {Set<int> avoid = const {}, Future<bool> Function(int)? isFree}) async {
  final free = isFree ?? musePortFree;
  if (await free(saved)) return (saved, false);
  final other = await museFindFreePort(saved, avoid: avoid, isFree: free);
  if (other == null) return (saved, false); // nothing better: the core reports the clash as before
  return (other, true);
}
