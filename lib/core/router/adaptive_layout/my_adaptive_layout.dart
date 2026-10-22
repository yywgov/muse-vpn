import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 穿云 desktop: widest the page column gets on a wide or maximized window.
const desktopContentMaxWidth = 760.0;

/// 穿云 1.3.0: 首页 gets more room (tile grid + node column).
const desktopHomeMaxWidth = 1280.0;

class MyAdaptiveLayout extends HookConsumerWidget {
  const MyAdaptiveLayout({
    super.key,
    required this.navigationShell,
    required this.isMobileBreakpoint,
    required this.showProfilesAction,
  });
  // managed by go router(Shell Route)
  final StatefulNavigationShell navigationShell;
  final bool isMobileBreakpoint;
  final bool showProfilesAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // focus switch management
    final primaryFocusHash = useState<int?>(null);
    final navScopeNode = useFocusScopeNode();
    useEffect(() {
      bool handler(KeyEvent event) {
        final arrows = isMobileBreakpoint ? KeyboardConst.verticalArrows : KeyboardConst.horizontalArrows;
        if (!arrows.contains(event.logicalKey)) return false;
        if (event is KeyDownEvent) {
          primaryFocusHash.value = FocusManager.instance.primaryFocus.hashCode;
        } else {
          // focus node does not change => true.
          if (primaryFocusHash.value == FocusManager.instance.primaryFocus.hashCode) {
            if (branchesScope.values.any((node) => node.hasFocus)) {
              navScopeNode.requestFocus();
            } else if (navScopeNode.hasFocus) {
              branchesScope[getNameOfBranch(isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex)]
                  ?.requestFocus();
            }
          }
        }
        return true;
      }

      HardwareKeyboard.instance.addHandler(handler);
      return () {
        HardwareKeyboard.instance.removeHandler(handler);
      };
    }, [isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex]);
    // Owns the system back press for the whole shell.
    //
    // It has to sit here, on the visible shell, and nowhere else. A PopScope
    // inside a branch stays mounted after the user leaves that branch, and go
    // router then lets it answer presses meant for another branch, which locks
    // the back button for good (flutter/flutter#193098).
    //
    // canPop is always false so the platform always routes the press to us.
    // Otherwise Android closes the app without calling into Flutter at all, and
    // no callback of ours ever runs. A press that a branch can handle is popped
    // by go router before it reaches here, so this only sees presses at the
    // root of a branch.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final homeIndex = getIndexOfBranch(isMobileBreakpoint, showProfilesAction, 'home');
        if (navigationShell.currentIndex != homeIndex) {
          // on another branch: go home instead of closing the app
          navigationShell.goBranch(homeIndex);
        } else {
          // already home: this is the way out of the app
          SystemNavigator.pop();
        }
      },
      // Keeps the claim above alive on the platform side.
      //
      // Every branch navigator broadcasts whether it can handle a back press,
      // and the last broadcast wins. Popping a page inside a branch leaves it
      // reporting "cannot handle", which reaches Android and makes it close the
      // app on the next press without ever calling Flutter. The PopScope above
      // always handles the press, so that report is wrong: replace it.
      child: NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          if (notification.canHandlePop) return false;
          const NavigationNotification(canHandlePop: true).dispatch(context);
          return true;
        },
        child: MuseShellFrame(
          isMobile: isMobileBreakpoint,
          currentIndex: navigationShell.currentIndex,
          navScopeNode: navScopeNode,
          onTap: (index) => _onTap(context, index),
          child: navigationShell,
        ),
      ),
    );
  }

  // shell route action onTap
  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

}

/// 穿云 1.3.0: 首页 / 节点 / 订阅 / 设置 (icon + label; the selected one only changes colour).
final museShellActions = [
  ShellRouteAction(Icons.home_outlined, '首页'),
  ShellRouteAction(Icons.language_rounded, '节点'),
  ShellRouteAction(Icons.link_rounded, '订阅'),
  ShellRouteAction(Icons.settings_outlined, '设置'),
];

/// The visible shell: bottom navigation on a phone, a rail plus one background and a centred
/// content column on the desktop. Split from [MyAdaptiveLayout] so it can be rendered on its own.
class MuseShellFrame extends ConsumerWidget {
  const MuseShellFrame({
    super.key,
    required this.isMobile,
    required this.currentIndex,
    required this.onTap,
    required this.child,
    this.navScopeNode,
  });

  final bool isMobile;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Widget child;
  final FocusScopeNode? navScopeNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // a subscription link waits on the clipboard: dot on 订阅
    final offer = ref.watch(museClipboardOfferProvider) != null;
    Widget icon(int i) {
      final a = museShellActions[i];
      final ic = Icon(a.icon);
      return i == 2 && offer ? Badge(smallSize: 8, backgroundColor: MusePalette.brand, child: ic) : ic;
    }

    final index = currentIndex < museShellActions.length ? currentIndex : 0;
    if (isMobile) {
      return Material(
        child: Scaffold(
          body: child,
          bottomNavigationBar: FocusScope(
            node: navScopeNode,
            child: NavigationBar(
              selectedIndex: index,
              destinations: [
                for (var i = 0; i < museShellActions.length; i++)
                  NavigationDestination(icon: icon(i), label: museShellActions[i].title),
              ],
              onDestinationSelected: onTap,
            ),
          ),
        ),
      );
    }
    // 首页 uses the width for 3–4 tile columns and the side node list; other pages stay readable
    final maxWidth = index == 0 ? desktopHomeMaxWidth : desktopContentMaxWidth;
    return Material(
      child: MuseBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Row(
            children: [
              FocusScope(
                node: navScopeNode,
                child: NavigationRail(
                  labelType: NavigationRailLabelType.all,
                  minWidth: 80,
                  groupAlignment: -0.9,
                  destinations: [
                    for (var i = 0; i < museShellActions.length; i++)
                      NavigationRailDestination(icon: icon(i), label: Text(museShellActions[i].title)),
                  ],
                  selectedIndex: index,
                  onDestinationSelected: onTap,
                ),
              ),
              Expanded(
                // 穿云 1.2: one thin scrollbar at the window's right edge, shown while scrolling
                child: MuseEdgeScrollbar(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedContainer(
                      duration: MuseMotion.fast,
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 穿云 desktop: the scrollbar of whatever page is showing, drawn at the window's right edge.
/// The pages' own scrollbars (which sat inside the centered column) are switched off; this one
/// follows the page's vertical scroll notifications, is thin, and fades out when idle.
class MuseEdgeScrollbar extends StatelessWidget {
  const MuseEdgeScrollbar({super.key, required this.child});

  final Widget child;

  static const thickness = 4.0;

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
      crossAxisMargin: 2,
      mainAxisMargin: 4,
      fadeDuration: const Duration(milliseconds: 250),
      timeToFade: const Duration(milliseconds: 900),
      notificationPredicate: _isPageScroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      ),
    );
  }
}
