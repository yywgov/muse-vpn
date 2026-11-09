// 穿云 1.6.0 C8 (G05, moved here from C2) - Windows: 穿云's own title bar in the page colour.
// Drag to move, double-click to maximize / restore, 窗口置顶 pin, 最小化 / 最大化(还原) / 关闭 at the
// system's 46×32 size; 关闭 goes through the normal close (关闭窗口时 decides: tray / quit / ask).
// The native window keeps its title string (smoke tests find the window by it) and its resize
// border; window_manager's standard API hides the system caption (TitleBarStyle.hidden). Can be
// turned off in 设置 › 电脑 (back to the system title bar).
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/shell/muse_shell.dart' show MuseSidebar;
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
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

/// 1.19.1 A8: the caption buttons in the system's own glyph font — Segoe Fluent Icons (Windows 11),
/// else Segoe MDL2 Assets (Windows 10; same code points). Null = neither font is on this machine
/// (or not Windows): the bar keeps its Material icons.
String? museCaptionGlyphFamily() {
  if (!Platform.isWindows) return null;
  final dir = '${Platform.environment['WINDIR'] ?? r'C:\Windows'}\\Fonts';
  try {
    if (File('$dir\\SegoeIcons.ttf').existsSync()) return 'Segoe Fluent Icons';
    if (File('$dir\\segmdl2.ttf').existsSync()) return 'Segoe MDL2 Assets';
  } catch (_) {}
  return null;
}

/// Which glyph font the title bar uses (tests override it).
final museCaptionGlyphFamilyProvider = Provider<String?>((_) => museCaptionGlyphFamily());

/// 1.19.1 A8: code points of the caption glyphs (Segoe Fluent Icons / MDL2 Assets).
abstract final class MuseCaptionGlyph {
  static const minimize = 0xE921;
  static const maximize = 0xE922;
  static const restore = 0xE923;
  static const close = 0xE8BB;
  static const pin = 0xE718;
  static const unpin = 0xE77A;
}

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

  /// 1.19.1 A8: the window has the focus (the bar greys out while it does not)
  bool _active = true;

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

  @override
  void onWindowFocus() {
    if (mounted && !_active) setState(() => _active = true);
  }

  @override
  void onWindowBlur() {
    if (mounted && _active) setState(() => _active = false);
  }

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
    final glyphs = ref.watch(museCaptionGlyphFamilyProvider);
    // 1.19.1 A8: the inactive window's bar is greyed (title and glyphs), the way Windows does it
    final fg = _active ? theme.text1 : theme.text1.withValues(alpha: MuseDesk.inactiveAlpha);
    return Material(
      key: const ValueKey('muse_title_bar'),
      // 1.19.1 A8: the same fill as the sidebar below it
      color: MuseSidebar.fill(theme.scheme),
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
                  child: Row(
                    children: [
                      Opacity(
                        key: const ValueKey('muse_title_icon'),
                        opacity: _active ? 1 : MuseDesk.inactiveAlpha,
                        child: ClipRSuperellipse(
                          borderRadius: MuseRadius.smallAll,
                          child: Assets.images.logo.svg(width: MuseDesk.titleIcon, height: MuseDesk.titleIcon),
                        ),
                      ),
                      const SizedBox(width: MuseSpace.s8),
                      Flexible(
                        child: Text(
                          Constants.appName,
                          key: const ValueKey('muse_title_text'),
                          style: MuseTextLevel.footnote.style(context, color: fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _CaptionButton(
              key: const ValueKey('muse_title_pin'),
              tooltip: pinned ? '取消置顶' : '窗口置顶',
              icon: Icons.push_pin_outlined,
              glyph: pinned ? MuseCaptionGlyph.unpin : MuseCaptionGlyph.pin,
              glyphFamily: glyphs,
              active: pinned,
              windowActive: _active,
              onPressed: () => ops.setAlwaysOnTop(!pinned),
            ),
            _CaptionButton(
              key: const ValueKey('muse_title_min'),
              tooltip: '最小化',
              icon: Icons.remove_outlined,
              glyph: MuseCaptionGlyph.minimize,
              glyphFamily: glyphs,
              windowActive: _active,
              onPressed: ops.minimize,
            ),
            _CaptionButton(
              key: const ValueKey('muse_title_max'),
              tooltip: _maximized ? '还原' : '最大化',
              icon: _maximized ? Icons.filter_none_outlined : Icons.crop_square_outlined,
              glyph: _maximized ? MuseCaptionGlyph.restore : MuseCaptionGlyph.maximize,
              glyphFamily: glyphs,
              windowActive: _active,
              onPressed: _toggleMaximize,
            ),
            _CaptionButton(
              key: const ValueKey('muse_title_close'),
              tooltip: '关闭',
              icon: Icons.close_outlined,
              glyph: MuseCaptionGlyph.close,
              glyphFamily: glyphs,
              danger: true,
              windowActive: _active,
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
    required this.glyph,
    this.glyphFamily,
    this.danger = false,
    this.active = false,
    this.windowActive = true,
  });

  final String tooltip;
  final IconData icon;

  /// 1.19.1 A8: the system glyph, drawn in [glyphFamily] when there is one (else [icon])
  final int glyph;
  final String? glyphFamily;
  final bool windowActive;
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
    final base = danger ? MusePalette.white : (widget.active ? museBrandOf(context) : theme.text1);
    // 1.19.1 A8: greyed while the window is inactive (hover still lights it up)
    final fg = widget.windowActive || _hover ? base : base.withValues(alpha: MuseDesk.inactiveAlpha);
    final family = widget.glyphFamily;
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
            child: family == null
                ? Icon(widget.icon, size: MuseSize.pinIcon, color: fg)
                : Text(
                    String.fromCharCode(widget.glyph),
                    key: const ValueKey('muse_caption_glyph'),
                    style: TextStyle(fontFamily: family, fontSize: MuseDesk.captionGlyph, height: 1, color: fg),
                  ),
          ),
        ),
      ),
    );
  }
}
