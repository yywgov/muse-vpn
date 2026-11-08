// 穿云 1.16.0 B8 - 敏感页禁截屏与后台模糊：节点详情、订阅链接（订阅详情）、二维码、导出配置打开期间
// 给窗口加 Android FLAG_SECURE（不能截屏录屏，最近任务里的缩略图变空白），全部关闭后立即去掉。
// 设置 › 外观 ›「敏感页禁止截屏」可关（默认开）。只在打开 / 关闭这些页面时调用一次，无轮询。
// Part of 穿云 (GPLv3).

import 'package:flutter/widgets.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Several sensitive pages can be open at once (a QR dialog over 节点详情): the flag goes on with the
/// first and off with the last.
class MuseSecureCounter {
  int _open = 0;

  int get open => _open;

  /// true = the flag has to be turned on now
  bool enter() => ++_open == 1;

  /// true = the flag has to be turned off now
  bool leave() {
    if (_open == 0) return false;
    return --_open == 0;
  }
}

final museSecureCounter = MuseSecureCounter();

/// The platform call; tests replace it.
Future<bool> Function(bool on) museSecureSetter = ChuanyunPlatform.setSecureScreen;

/// Runs [body] with the window secured (when 敏感页禁止截屏 is on).
Future<T> museWithSecureScreen<T>(ProviderContainer container, Future<T> Function() body) async {
  final on = container.read(MusePrefs.secureSensitive);
  if (on && museSecureCounter.enter()) await museSecureSetter(true);
  try {
    return await body();
  } finally {
    if (on && museSecureCounter.leave()) await museSecureSetter(false);
  }
}

/// [museWithSecureScreen] from a widget's context.
/// Without a ProviderScope above [context] (never in the app) it just runs [body].
Future<T> museSecureFor<T>(BuildContext context, Future<T> Function() body) {
  ProviderContainer? container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    container = null;
  }
  return container == null ? body() : museWithSecureScreen(container, body);
}

/// Keeps the window secured while [child] is on screen (a page rather than a dialog).
class MuseSecureScope extends ConsumerStatefulWidget {
  const MuseSecureScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MuseSecureScope> createState() => _MuseSecureScopeState();
}

class _MuseSecureScopeState extends ConsumerState<MuseSecureScope> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(MusePrefs.secureSensitive)) {
      _entered = true;
      if (museSecureCounter.enter()) museSecureSetter(true);
    }
  }

  @override
  void dispose() {
    if (_entered && museSecureCounter.leave()) museSecureSetter(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
