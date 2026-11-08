// 穿云 1.17.0 R19 - Windows: while the window is hidden in the tray, the pages are taken out of
// the widget tree (their animations, charts, timers and page-level streams stop and their memory
// is released) and the image cache is emptied. The Flutter engine and the core keep running
// (they share the process), and so do the app-level listeners above the pages (tray, hotkeys,
// connection keeper). Showing the window builds the current page again.
// Part of 穿云 (GPLv3).

import 'package:flutter/widgets.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// true while the window is hidden to the tray (set by WindowNotifier.hide / show / silent start).
final museWindowHiddenProvider = StateProvider<bool>((_) => false);

/// tests run it off Windows
final museHiddenReleaseForceProvider = Provider<bool>((_) => false);

/// Whether the pages are left out right now.
bool museReleasePages({required bool windows, required bool hidden}) => windows && hidden;

/// The hidden state after a window_manager event ('show' / 'focus' / 'restore' bring the pages
/// back, 'hide' releases them; anything else leaves it as it is).
bool museHiddenAfterEvent(String event, bool hidden) => switch (event) {
  'show' || 'focus' || 'restore' => false,
  'hide' => true,
  _ => hidden,
};

/// Frees decoded images (called when the window hides).
void museReleaseImageCache() {
  try {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  } catch (_) {}
}

class MuseHiddenRelease extends ConsumerWidget {
  const MuseHiddenRelease({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = museReleasePages(
      windows: PlatformUtils.isWindows || ref.watch(museHiddenReleaseForceProvider),
      hidden: ref.watch(museWindowHiddenProvider),
    );
    return release ? const SizedBox.shrink(key: ValueKey('muse_pages_released')) : child;
  }
}
