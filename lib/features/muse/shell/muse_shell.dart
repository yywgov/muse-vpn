// 穿云 1.6.0 C2 - the adaptive shell: a floating / docked bottom bar up to 600 dp, a collapsed
// icon rail up to 840 dp, an expandable sidebar (remembered) above that; tab switches fade or
// slide (none with reduced motion). Wide windows also get 连接 (and 日志 while 日志记录 is on).
// Layout rules adapted from GPL-3.0 code, Copyright (C) chen08209 (see THIRD_PARTY_NOTICES.md).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/changelog_dialog.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 穿云 desktop: widest the page column gets on a wide or maximized window.
const desktopContentMaxWidth = 760.0;

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

const museShellConnections = MuseShellExtra('connections', Icons.swap_vert_outlined, '连接', '/settings/connections');
const museShellLogs = MuseShellExtra('logs', Icons.article_outlined, '日志', '/settings/logs');

/// Which navigation a window of [width] gets.
enum MuseNavForm { dock, rail, sidebar }

MuseNavForm museNavForm(double width) {
  if (width <= MuseBreak.mobile) return MuseNavForm.dock;
  if (width <= MuseBreak.laptop) return MuseNavForm.rail;
  return MuseNavForm.sidebar;
}

/// The sidebar extras for the current settings ([logCapture] adds 日志 once it has a page).
List<MuseShellExtra> museShellExtras({required bool logCapture, bool logsAvailable = false}) => [
  museShellConnections,
  if (logCapture && logsAvailable) museShellLogs,
];

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
    final changelogDot = ref.watch(museChangelogDotProvider);
    final scheme = Theme.of(context).colorScheme;
    Widget icon(int i, Color color) {
      final ic = Icon(museShellActions[i].icon, color: color);
      if (i == 3) return MuseDot(show: changelogDot, child: ic);
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
        position: _curve.drive(Tween(begin: Offset(0.06 * _dir, 0), end: Offset.zero)),
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
  static const headerHeight = MuseSize.rowMin;
  static const itemHeight = MuseSize.button + MuseSpace.s4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row({required bool selected, required Widget leading, required String label, required VoidCallback onTap, Key? key}) {
      final color = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
      return SizedBox(
        key: key,
        height: itemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s4),
          child: Semantics(
            selected: selected,
            button: true,
            label: label,
            child: Material(
              color: selected ? scheme.secondaryContainer : MusePalette.transparent,
              shape: MuseShape.full,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Tooltip(
                  message: expanded ? '' : label,
                  child: Row(
                    mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                    children: [
                      if (expanded) const SizedBox(width: MuseSpace.s12),
                      leading,
                      if (expanded) ...[
                        const SizedBox(width: MuseSpace.s12),
                        Expanded(
                          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: MuseTextLevel.callout.style(context, color: color, weight: selected ? FontWeight.w600 : FontWeight.w500)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      key: ValueKey(expanded ? 'muse_sidebar_expanded' : 'muse_sidebar_collapsed'),
      duration: museMotion(context),
      curve: MuseMotion.curve,
      width: expanded ? MuseSize.navSidebarExpanded : MuseSize.navRailCollapsed,
      color: MuseSurface.page.color(scheme),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: headerHeight,
            child: canExpand
                ? Align(
                    alignment: expanded ? AlignmentDirectional.centerStart : Alignment.center,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(start: expanded ? MuseSpace.s12 : 0),
                      child: IconButton(
                        key: const ValueKey('muse_sidebar_toggle'),
                        tooltip: expanded ? '收起侧栏' : '展开侧栏',
                        icon: Icon(expanded ? Icons.menu_open_outlined : Icons.menu_outlined),
                        onPressed: onToggle,
                      ),
                    ),
                  )
                : null,
          ),
          for (var i = 0; i < museShellActions.length; i++)
            row(
              key: ValueKey('muse_nav_$i'),
              selected: i == index,
              leading: icon(i, i == index ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
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
              leading: Icon(e.icon, color: e == selectedExtra ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
              label: e.title,
              onTap: () => onExtra(e),
            ),
        ],
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
