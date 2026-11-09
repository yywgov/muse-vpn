// 穿云 1.6.0 C2 - the adaptive shell: a floating / docked bottom bar up to 600 dp, a collapsed
// icon rail up to 840 dp, an expandable sidebar (remembered) above that; tab switches fade or
// slide (none with reduced motion). Wide windows also get 连接 (and 日志 while 日志记录 is on).
// Layout rules adapted from GPL-3.0 code, Copyright (C) chen08209 (see THIRD_PARTY_NOTICES.md).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 穿云 desktop: widest the page column gets on a wide or maximized window.
/// 1.19.1 A9: 760 → 840（[MuseDesk.contentMax]；标题与卡片同一列）
const desktopContentMaxWidth = MuseDesk.contentMax;

/// 穿云 1.3.0: 首页 gets more room.
const desktopHomeMaxWidth = 1280.0;

/// 首页 / 节点 / 订阅 / 设置 (icon + label).
final museShellActions = [
  ShellRouteAction(Icons.home_outlined, '首页'),
  ShellRouteAction(Icons.language_outlined, '节点'),
  ShellRouteAction(Icons.link_outlined, '订阅'),
  ShellRouteAction(Icons.settings_outlined, '设置'),
];

/// Extra sidebar entries on a wide window (pages under 设置, opened by route name).
class MuseShellExtra {
  const MuseShellExtra(this.route, this.icon, this.title, this.path);

  final String route;
  final IconData icon;
  final String title;

  /// the location prefix that marks it selected
  final String path;
}

/// 1.8.0: one entry, 活动 (连接 / 日志 / DNS); the old 连接 / 日志 locations redirect into it.
const museShellActivity = MuseShellExtra('activity', Icons.swap_vert_outlined, '活动', '/settings/activity');

/// Which navigation a window of [width] gets.
enum MuseNavForm { dock, rail, sidebar }

MuseNavForm museNavForm(double width) {
  if (width <= MuseBreak.mobile) return MuseNavForm.dock;
  if (width <= MuseBreak.laptop) return MuseNavForm.rail;
  return MuseNavForm.sidebar;
}

/// The sidebar extras. 1.8.0: always 活动 (日志 is its tab, so 日志记录 no longer adds an entry);
/// the parameters stay for callers.
List<MuseShellExtra> museShellExtras({required bool logCapture, bool logsAvailable = false}) => const [museShellActivity];

class MuseShellFrame extends ConsumerWidget {
  const MuseShellFrame({
    super.key,
    required this.isMobile,
    required this.currentIndex,
    required this.onTap,
    required this.child,
    this.navScopeNode,
    this.location = '',
    this.onExtra,
  });

  /// a phone-sized window (the dock); otherwise the width decides rail / sidebar
  final bool isMobile;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Widget child;
  final FocusScopeNode? navScopeNode;

  /// the current location (marks 连接 / 日志 selected)
  final String location;
  final ValueChanged<String>? onExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(museClipboardOfferProvider) != null;
    final scheme = Theme.of(context).colorScheme;
    Widget icon(int i, Color color) {
      final ic = Icon(museShellActions[i].icon, color: color);
      // 1.10.0: no unread dot on 设置 (关于 has no 更新内容 row any more; a feature release still
      // shows its notes once by itself)
      return i == 2 && offer ? Badge(smallSize: MuseSize.dot, backgroundColor: scheme.primary, child: ic) : ic;
    }

    final index = currentIndex < museShellActions.length ? currentIndex : 0;
    final anim = ref.watch(MusePrefs.tabAnimation);
    final body = MuseTabTransition(index: index, slide: anim == 'slide', child: child);
    final width = MediaQuery.sizeOf(context).width;
    final form = isMobile ? MuseNavForm.dock : museNavForm(width == 0 ? MuseBreak.laptop + 1 : width);
    if (form == MuseNavForm.dock) {
      final floating = ref.watch(MusePrefs.dockStyle) != 'docked';
      return Material(
        color: MuseSurface.page.color(scheme),
        child: Scaffold(
          backgroundColor: MuseSurface.page.color(scheme),
          // 1.6.1: the page ends at the bar's top edge in both styles (1.6.0 let pages run under the
          // floating bar, which hid the last ~100 dp of every list). The bar itself pads for the
          // system gesture / button area.
          extendBody: false,
          body: body,
          bottomNavigationBar: FocusScope(
            node: navScopeNode,
            child: MuseDock(floating: floating, index: index, onTap: onTap, icon: icon),
          ),
        ),
      );
    }
    final extras = museShellExtras(logCapture: ref.watch(MusePrefs.logCapture), logsAvailable: true);
    final expanded = form == MuseNavForm.sidebar && ref.watch(MusePrefs.sidebarExpanded);
    final selectedExtra = extras.where((e) => location.startsWith(e.path)).firstOrNull;
    final maxWidth = index == 0 && selectedExtra == null ? desktopHomeMaxWidth : desktopContentMaxWidth;
    return Material(
      color: MuseSurface.page.color(scheme),
      child: Scaffold(
        backgroundColor: MuseSurface.page.color(scheme),
        body: Row(
          children: [
            FocusScope(
              node: navScopeNode,
              child: MuseSidebar(
                expanded: expanded,
                canExpand: form == MuseNavForm.sidebar,
                index: selectedExtra == null ? index : -1,
                extras: extras,
                selectedExtra: selectedExtra,
                onTap: onTap,
                onExtra: (e) => onExtra?.call(e.route),
                onToggle: () => ref.read(MusePrefs.sidebarExpanded.notifier).update(!expanded),
                icon: icon,
              ),
            ),
            Expanded(
              // 1.6.1: no bar here, so the page stops above the system gesture / button area.
              child: MuseEdgeScrollbar(
                child: SafeArea(
                  left: false,
                  top: false,
                  right: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedContainer(
                      duration: museMotion(context),
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: body,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1.6.1: the bottom padding a scroll view's last item needs: [base] plus whatever the screen still
/// covers below this context — the system gesture / button area on a page outside the shell or in
/// a sheet. Inside the shell this is just [base]: the shell already ends every page at the top of
/// the bottom bar (dock) or above the system area (rail / sidebar), so pages never pad for the bar.
double museScrollEndGap(BuildContext context, [double base = MuseSpace.s32]) => base + MediaQuery.paddingOf(context).bottom;

/// [museScrollEndGap] as the bottom of [padding].
EdgeInsets museScrollPadding(BuildContext context, EdgeInsets padding) =>
    padding.copyWith(bottom: museScrollEndGap(context, padding.bottom));

/// Fades (or slides) the new tab in when [index] changes; nothing with reduced motion.
class MuseTabTransition extends StatefulWidget {
  const MuseTabTransition({super.key, required this.index, required this.child, this.slide = false});

  final int index;
  final bool slide;
  final Widget child;

  @override
  State<MuseTabTransition> createState() => _MuseTabTransitionState();
}

class _MuseTabTransitionState extends State<MuseTabTransition> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: MuseMotion.tab, value: 1);
  late final _curve = CurvedAnimation(parent: _c, curve: MuseMotion.tabCurve);
  var _dir = 1.0;

  @override
  void didUpdateWidget(MuseTabTransition old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _dir = widget.index > old.index ? 1 : -1;
      if (museReduceMotion(context)) {
        _c.value = 1;
      } else {
        // 1.18.0 P6: 精简 shortens the switch
        _c.duration = museDuration(context, MuseMotion.tab);
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget out = FadeTransition(key: const ValueKey('muse_tab_fade'), opacity: _curve, child: widget.child);
    if (widget.slide) {
      out = SlideTransition(
        position: _curve.drive(Tween(begin: Offset(MuseMotion.tabShift * _dir, 0), end: Offset.zero)),
        child: out,
      );
    }
    return out;
  }
}

/// The phone bottom bar: floating (default) or docked full-width bar. 1.6.1: Material 3 look —
/// a tonal indicator marks the selected tab (docked: a pill behind the icon; floating: a
/// rounded block behind icon and label), no shadow, the bar on the card surface.
class MuseDock extends StatelessWidget {
  const MuseDock({super.key, required this.floating, required this.index, required this.onTap, required this.icon});

  final bool floating;
  final int index;
  final ValueChanged<int> onTap;
  final Widget Function(int i, Color color) icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    Color iconColor(int i) => i == index ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final items = Row(
      children: [
        for (var i = 0; i < museShellActions.length; i++)
          Expanded(
            child: _DockItem(
              selected: i == index,
              block: floating,
              label: museShellActions[i].title,
              onTap: () => onTap(i),
              icon: icon(i, iconColor(i)),
            ),
          ),
      ],
    );
    if (!floating) {
      return Material(
        key: const ValueKey('muse_dock_docked'),
        color: MuseSurface.card.color(scheme),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SizedBox(height: MuseSize.navBarHeight, child: items),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(MuseSpace.s12, 0, MuseSpace.s12, bottom + MuseSpace.s8),
      child: Material(
        key: const ValueKey('muse_dock_floating'),
        color: MuseSurface.card.color(scheme),
        shape: MuseShape.xxl,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(MuseSpace.s4),
          child: SizedBox(height: MuseSize.dockHeight, child: items),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({required this.selected, required this.block, required this.label, required this.onTap, required this.icon});

  final bool selected;

  /// the indicator covers icon and label (floating bar) instead of a pill behind the icon
  final bool block;
  final String label;
  final VoidCallback onTap;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = selected ? scheme.secondaryContainer : MusePalette.transparent;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.fade,
      style: MuseTextLevel.caption1.style(
        context,
        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        weight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
    final Widget content = block
        ? AnimatedContainer(
            key: const ValueKey('muse_dock_indicator'),
            duration: museMotion(context),
            margin: const EdgeInsets.symmetric(horizontal: MuseSpace.s4),
            decoration: ShapeDecoration(color: fill, shape: MuseShape.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [icon, const SizedBox(height: MuseSpace.s4), text],
            ),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                key: const ValueKey('muse_dock_indicator'),
                duration: museMotion(context),
                width: MuseSize.navIndicatorWidth,
                height: MuseSize.navIndicatorHeight,
                alignment: Alignment.center,
                decoration: ShapeDecoration(color: fill, shape: MuseShape.full),
                child: icon,
              ),
              const SizedBox(height: MuseSpace.s4),
              text,
            ],
          );
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkResponse(onTap: onTap, highlightShape: BoxShape.rectangle, child: content),
    );
  }
}

/// Collapsed rail (icons) or expanded sidebar (icons + labels) with the extras under a divider.
class MuseSidebar extends StatelessWidget {
  const MuseSidebar({
    super.key,
    required this.expanded,
    required this.canExpand,
    required this.index,
    required this.extras,
    required this.selectedExtra,
    required this.onTap,
    required this.onExtra,
    required this.onToggle,
    required this.icon,
  });

  final bool expanded;
  final bool canExpand;

  /// selected tab (-1 while an extra is showing)
  final int index;
  final List<MuseShellExtra> extras;
  final MuseShellExtra? selectedExtra;
  final ValueChanged<int> onTap;
  final ValueChanged<MuseShellExtra> onExtra;
  final VoidCallback onToggle;
  final Widget Function(int i, Color color) icon;

  /// sidebar row geometry (tool/smoke/app_smoke.ps1 clicks by these)
  /// 1.19.1 A7: the header is the 48 high brand row (was a 56 high toggle row)
  static const headerHeight = MuseDesk.sidebarBrand;
  static const itemHeight = MuseSize.button + MuseSpace.s4;

  /// 1.19.1 A7: the sidebar's own fill (a level apart from the page, with a hairline at its edge).
  static Color fill(ColorScheme s) => s.surfaceContainerLow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row({required bool selected, required Widget leading, required String label, required VoidCallback onTap, Key? key}) =>
        MuseNavItem(key: key, selected: selected, expanded: expanded, leading: leading, label: label, onTap: onTap);

    final toggle = IconButton(
      key: const ValueKey('muse_sidebar_toggle'),
      tooltip: expanded ? '收起侧栏' : '展开侧栏',
      icon: Icon(expanded ? Icons.menu_open_outlined : Icons.menu_outlined),
      onPressed: onToggle,
    );
    final logo = Assets.images.logo.svg(width: MuseDesk.brandIcon, height: MuseDesk.brandIcon);
    return AnimatedContainer(
      key: ValueKey(expanded ? 'muse_sidebar_expanded' : 'muse_sidebar_collapsed'),
      duration: museMotion(context),
      curve: MuseMotion.curve,
      width: expanded ? MuseSize.navSidebarExpanded : MuseSize.navRailCollapsed,
      decoration: BoxDecoration(
        color: fill(scheme),
        border: Border(right: BorderSide(color: scheme.outlineVariant, width: MuseSize.hairline)),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 1.19.1 A7: brand row — the app icon + 穿云, the collapse toggle at its end
          SizedBox(
            key: const ValueKey('muse_sidebar_brand'),
            height: headerHeight,
            child: expanded
                ? Padding(
                    padding: const EdgeInsetsDirectional.only(start: MuseSpace.s24, end: MuseSpace.s4),
                    child: Row(
                      children: [
                        ClipRSuperellipse(borderRadius: MuseRadius.smallAll, child: logo),
                        const SizedBox(width: MuseSpace.s8),
                        Expanded(
                          child: Text(
                            Constants.appName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MuseTextLevel.subheadline.style(context, weight: FontWeight.w600),
                          ),
                        ),
                        if (canExpand) toggle,
                      ],
                    ),
                  )
                : Center(child: canExpand ? toggle : ClipRSuperellipse(borderRadius: MuseRadius.smallAll, child: logo)),
          ),
          for (var i = 0; i < museShellActions.length; i++)
            row(
              key: ValueKey('muse_nav_$i'),
              selected: i == index,
              leading: icon(i, i == index ? scheme.primary : scheme.onSurfaceVariant),
              label: museShellActions[i].title,
              onTap: () => onTap(i),
            ),
          if (extras.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s24, vertical: MuseSpace.s8),
              child: Divider(height: MuseSize.hairline, thickness: MuseSize.hairline, color: scheme.outlineVariant),
            ),
          for (final e in extras)
            row(
              key: ValueKey('muse_nav_${e.route}'),
              selected: e == selectedExtra,
              leading: Icon(e.icon, color: e == selectedExtra ? scheme.primary : scheme.onSurfaceVariant),
              label: e.title,
              onTap: () => onExtra(e),
            ),
        ],
      ),
    );
  }
}

/// 1.19.1 A7: one sidebar entry in the Windows 11 manner — a 6 rounded block; selected = the
/// accent at 10 % with a 3×16 accent bar on its left; hover 6 % / pressed 9 % of onSurface;
/// keyboard focus = a 2 px accent ring. Hover / press come from pointer events only (no timer).
class MuseNavItem extends StatefulWidget {
  const MuseNavItem({
    super.key,
    required this.selected,
    required this.expanded,
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final bool expanded;
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  /// the fill for a state (tests compare against it)
  static Color fillFor(ColorScheme s, {required bool selected, bool hover = false, bool pressed = false}) {
    if (selected) return s.primary.withValues(alpha: MuseDesk.selectedAlpha);
    if (pressed) return s.onSurface.withValues(alpha: MuseDesk.pressAlpha);
    if (hover) return s.onSurface.withValues(alpha: MuseDesk.hoverAlpha);
    return MusePalette.transparent;
  }

  @override
  State<MuseNavItem> createState() => _MuseNavItemState();
}

class _MuseNavItemState extends State<MuseNavItem> {
  bool _hover = false;
  bool _pressed = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final expanded = widget.expanded;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    final fill = MuseNavItem.fillFor(scheme, selected: selected, hover: _hover, pressed: _pressed);
    final shape = MuseShape.of(
      MuseDesk.navRadius,
      side: _focus ? BorderSide(color: scheme.primary, width: MuseDesk.focusRing) : BorderSide.none,
    );
    return SizedBox(
      height: MuseSidebar.itemHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s4),
        child: Semantics(
          selected: selected,
          button: true,
          label: widget.label,
          child: Material(
            key: const ValueKey('muse_nav_fill'),
            color: fill,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHover: (v) => setState(() => _hover = v),
              onHighlightChanged: (v) => setState(() => _pressed = v),
              onFocusChange: (v) => setState(() => _focus = v),
              overlayColor: const WidgetStatePropertyAll(MusePalette.transparent),
              splashFactory: NoSplash.splashFactory,
              child: Tooltip(
                message: expanded ? '' : widget.label,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                        children: [
                          if (expanded) const SizedBox(width: MuseSpace.s12),
                          widget.leading,
                          if (expanded) ...[
                            const SizedBox(width: MuseSpace.s12),
                            Expanded(
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MuseTextLevel.callout.style(context, color: color, weight: selected ? FontWeight.w600 : FontWeight.w500),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selected)
                      PositionedDirectional(
                        start: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            key: const ValueKey('muse_nav_indicator'),
                            width: MuseDesk.navIndicatorWidth,
                            height: MuseDesk.navIndicatorHeight,
                            decoration: BoxDecoration(color: scheme.primary, borderRadius: MuseRadius.fullAll),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 穿云 desktop: the scrollbar of whatever page is showing, drawn at the window's right edge.
class MuseEdgeScrollbar extends StatelessWidget {
  const MuseEdgeScrollbar({super.key, required this.child});

  final Widget child;

  static const thickness = MuseSpace.s4;

  static bool _isPageScroll(ScrollNotification n) => n.depth == 0 && n.metrics.axis == Axis.vertical;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
    return RawScrollbar(
      thumbVisibility: false,
      trackVisibility: false,
      interactive: false,
      thickness: thickness,
      radius: const Radius.circular(thickness),
      thumbColor: color,
      crossAxisMargin: MuseSize.barGap,
      mainAxisMargin: MuseSpace.s4,
      fadeDuration: MuseMotion.common,
      timeToFade: MuseMotion.skeletonPulse,
      notificationPredicate: _isPageScroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      ),
    );
  }
}
