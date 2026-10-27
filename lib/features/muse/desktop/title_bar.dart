// 穿云 1.6.0 C8 (G05, moved here from C2) - Windows: 穿云's own title bar in the page colour.
// Drag to move, double-click to maximize / restore, 窗口置顶 pin, 最小化 / 最大化(还原) / 关闭 at the
// system's 46×32 size; 关闭 goes through the normal close (关闭窗口时 decides: tray / quit / ask).
// The native window keeps its title string (smoke tests find the window by it) and its resize
// border; window_manager's standard API hides the system caption (TitleBarStyle.hidden). Can be
// turned off in 设置 › 电脑 (back to the system title bar).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// The window calls the title bar makes (a fake in tests).
abstract class MuseWindowOps {
  Future<void> startDragging();
  Future<void> minimize();
  Future<bool> isMaximized();
  Future<void> maximize();
  Future<void> unmaximize();
  Future<void> close();
  Future<void> setAlwaysOnTop(bool on);
}

class _SystemWindowOps implements MuseWindowOps {
  _SystemWindowOps(this.ref);

  final Ref ref;

  @override
  Future<void> startDragging() => windowManager.startDragging();
  @override
  Future<void> minimize() => windowManager.minimize();
  @override
  Future<bool> isMaximized() => windowManager.isMaximized();
  @override
  Future<void> maximize() => windowManager.maximize();
  @override
  Future<void> unmaximize() => windowManager.unmaximize();
  // the close request goes through WindowWrapper.onWindowClose (setPreventClose)
  @override
  Future<void> close() => windowManager.close();
  @override
  Future<void> setAlwaysOnTop(bool on) => ref.read(windowNotifierProvider.notifier).setAlwaysOnTop(on);
}

final museWindowOpsProvider = Provider<MuseWindowOps>(_SystemWindowOps.new);

/// tests show the bar off Windows
final museTitleBarForceProvider = Provider<bool>((_) => false);

/// Whether the app draws its own title bar right now.
final museCustomTitleBarProvider = Provider<bool>(
  (ref) => (PlatformUtils.isWindows || ref.watch(museTitleBarForceProvider)) && ref.watch(MusePrefs.customTitleBar),
);

/// [child] under the title bar when [museCustomTitleBarProvider] is on.
class MuseTitleBarFrame extends ConsumerWidget {
  const MuseTitleBarFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(museCustomTitleBarProvider)) return child;
    return Column(
      children: [
        const MuseTitleBar(),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}

class MuseTitleBar extends ConsumerStatefulWidget {
  const MuseTitleBar({super.key});

  @override
  ConsumerState<MuseTitleBar> createState() => _MuseTitleBarState();
}

class _MuseTitleBarState extends ConsumerState<MuseTitleBar> with WindowListener {
  bool _maximized = false;

  bool get _listens => PlatformUtils.isDesktop;

  @override
  void initState() {
    super.initState();
    if (_listens) {
      windowManager.addListener(this);
      ref
          .read(museWindowOpsProvider)
          .isMaximized()
          .then((v) {
            if (mounted && v != _maximized) setState(() => _maximized = v);
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    if (_listens) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximize() async {
    final ops = ref.read(museWindowOpsProvider);
    final max = await ops.isMaximized();
    max ? await ops.unmaximize() : await ops.maximize();
    if (mounted) setState(() => _maximized = !max);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MuseTheme.of(context);
    final ops = ref.read(museWindowOpsProvider);
    final pinned = ref.watch(MusePrefs.alwaysOnTop);
    return Material(
      key: const ValueKey('muse_title_bar'),
      color: theme.bgBottom,
      child: SizedBox(
        height: MuseSize.titleBar,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                key: const ValueKey('muse_title_drag'),
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => ops.startDragging(),
                onDoubleTap: _toggleMaximize,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: MuseSpace.s12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(Constants.appName, style: MuseType.caption(context), maxLines: 1),
                  ),
                ),
              ),
            ),
            _CaptionButton(
              key: const ValueKey('muse_title_pin'),
              tooltip: pinned ? '取消置顶' : '窗口置顶',
              icon: Icons.push_pin_outlined,
              active: pinned,
              onPressed: () => ops.setAlwaysOnTop(!pinned),
            ),
            _CaptionButton(
              key: const ValueKey('muse_title_min'),
              tooltip: '最小化',
              icon: Icons.remove_outlined,
              onPressed: ops.minimize,
            ),
            _CaptionButton(
              key: const ValueKey('muse_title_max'),
              tooltip: _maximized ? '还原' : '最大化',
              icon: _maximized ? Icons.filter_none_outlined : Icons.crop_square_outlined,
              onPressed: _toggleMaximize,
            ),
            _CaptionButton(
              key: const ValueKey('muse_title_close'),
              tooltip: '关闭',
              icon: Icons.close_outlined,
              danger: true,
              onPressed: ops.close,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;
  final bool active;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = MuseTheme.of(context);
    final danger = widget.danger && _hover;
    final bg = danger ? MusePalette.red : (_hover ? theme.selected : null);
    final fg = danger ? MusePalette.white : (widget.active ? museBrandOf(context) : theme.text2);
    return Semantics(
      button: true,
      label: widget.tooltip,
      // no Tooltip: the bar sits above the app's Navigator, outside any Overlay
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: MuseSize.captionButton,
            height: MuseSize.titleBar,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: MuseSize.pinIcon, color: fg),
          ),
        ),
      ),
    );
  }
}
