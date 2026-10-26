import 'dart:async';
import 'package:hiddify/features/muse/desktop/launch_control.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/custom_transition.dart';
import 'package:hiddify/core/router/go_router/refresh_listenable.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/about/widget/open_source_page.dart';
import 'package:hiddify/features/app_based_routing/overview/app_list_page.dart';
import 'package:hiddify/features/muse/config/muse_config_page.dart';
import 'package:hiddify/features/muse/data/muse_data_page.dart';
import 'package:hiddify/features/muse/home/muse_home_page.dart';
import 'package:hiddify/features/muse/nodes/muse_nodes_page.dart';
import 'package:hiddify/features/muse/settings/per_app_proxy_page.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/overview/generic_list_page.dart';
import 'package:hiddify/features/route_rules/overview/package_names_page.dart';
import 'package:hiddify/features/route_rules/overview/rule_page.dart';
import 'package:hiddify/features/settings/overview/sections/routing_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/tls_tricks_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'routing_config_notifier.g.dart';

// each branch in go router has its own focus scope
final branchesScope = <String, FocusScopeNode>{
  'home': FocusScopeNode(),
  'nodes': FocusScopeNode(),
  'config': FocusScopeNode(),
  'settings': FocusScopeNode(),
};

// when the routing config is not yet initialized, this config is used
final loadingConfig = RoutingConfig(
  routes: <RouteBase>[GoRoute(path: '/home', builder: (context, state) => const Material())],
);

// 穿云 1.3.0: four tabs, 首页 / 节点 / 订阅 / 设置, on every form factor.
const mobileBranches = ['home', 'nodes', 'config', 'settings'];

String getNameOfBranch(bool isMobileBreakpoint, bool showProfilesAction, int index) => mobileBranches[index];

int getIndexOfBranch(bool isMobileBreakpoint, bool showProfilesAction, String name) => mobileBranches.indexOf(name);

GoRoute _slide(String name, String path, Widget Function(GoRouterState state) page, {List<RouteBase> routes = const []}) =>
    GoRoute(
      name: name,
      path: path,
      pageBuilder: (_, state) => customTransition(TransitionType.slide, state.pageKey, page(state)),
      routes: routes,
    );

@Riverpod(keepAlive: true)
class RoutingConfigNotifier extends _$RoutingConfigNotifier {
  @override
  RoutingConfig build() {
    final isMobileBreakpoint = ref.watch(isMobileBreakpointProvider);
    if (isMobileBreakpoint == null) return loadingConfig;
    return RoutingConfig(
      redirect: (context, state) {
        // fix path-parameters for deep link
        String? url;
        if (LinkParser.protocols.contains(state.uri.scheme)) {
          // Android & iOS deep link
          url = state.uri.toString();
        } else if (PlatformUtils.isDesktop && newUrlFromAppLink.isNotEmpty) {
          // Desktops deep link
          url = newUrlFromAppLink;
          newUrlFromAppLink = '';
        } else if (state.uri.queryParameters['url'] != null) {
          url = state.uri.queryParameters['url'];
        }

        // 穿云 1.4.1: chuanyun://connect[?node=] / chuanyun://disconnect
        final control = url == null ? null : museParseDeepLink(url);
        if (control != null && (control.connect || control.disconnect)) {
          unawaited(museApplyLaunchControl(ref, MuseCliArgs(connect: control.connect, disconnect: control.disconnect, node: control.node)));
          return '/home';
        }
        if (url != null && Uri.parse(url).host == 'import') {
          // Auto import profile from url
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: url, triggeredByDeepLink: true),
          );
          return '/home';
        } else if (url != null) {
          final uri = Uri.parse(url);
          final path = uri.path + (uri.hasQuery ? "?${uri.query}" : "");
          return path.isEmpty ? '/home' : path;
        }
        return null;
      },
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (_, state, navigationShell) => MyAdaptiveLayout(
            navigationShell: navigationShell,
            isMobileBreakpoint: isMobileBreakpoint,
            showProfilesAction: false,
            location: state.uri.path,
          ),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'home',
                  path: '/home',
                  builder: (_, _) => FocusScope(node: branchesScope['home'], child: const MuseHomePage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'nodes',
                  path: '/nodes',
                  builder: (_, _) => FocusScope(node: branchesScope['nodes'], child: const MuseNodesPage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'config',
                  path: '/config',
                  builder: (_, _) => FocusScope(node: branchesScope['config'], child: const MuseConfigPage()),
                  routes: <GoRoute>[
                    _slide('profileDetails', 'profile-details/:id', (state) => ProfileDetailsPage(id: state.pathParameters['id']!)),
                    GoRoute(
                      name: 'routingOptions',
                      path: 'routing-options',
                      pageBuilder: (_, state) => customTransition(
                        TransitionType.slide,
                        state.pageKey,
                        RoutingOptionsPage(routeRule: state.uri.queryParameters['routeRule']),
                      ),
                      routes: <GoRoute>[
                        GoRoute(
                          name: 'rule',
                          path: 'rule/:orderId',
                          pageBuilder: (_, state) {
                            final orderIdString = state.pathParameters['orderId']!;
                            return customTransition(
                              TransitionType.slide,
                              state.pageKey,
                              RulePage(ruleListOrder: orderIdString != 'new' ? int.tryParse(orderIdString) : null),
                            );
                          },
                          onExit: (context, state) async {
                            final t = ref.read(translationsProvider).requireValue;
                            final orderId = int.tryParse(state.pathParameters['orderId']!);
                            final isRuleEdited = ref.read(IsRuleEditedProvider(orderId));
                            if (orderId != null && isRuleEdited) {
                              await ref.read(ruleNotifierProvider(orderId).notifier).save();
                              ref
                                  .read(inAppNotificationControllerProvider)
                                  .showSuccessToast(t.common.msg.autoSave.success);
                            }
                            return true;
                          },
                          routes: <GoRoute>[
                            GoRoute(
                              name: 'genericList',
                              path: 'generic-list/:ruleEnum',
                              pageBuilder: (_, state) {
                                final orderId = int.tryParse(state.pathParameters['orderId']!);
                                final ruleEnum = RuleEnum.values.byName(state.pathParameters['ruleEnum']!);
                                return customTransition(
                                  TransitionType.slide,
                                  state.pageKey,
                                  GenericListPage(ruleListOrder: orderId, ruleEnum: ruleEnum),
                                );
                              },
                            ),
                            _slide(
                              'packageNames',
                              'package-names',
                              (state) => PackageNamesPage(ruleListOrder: int.tryParse(state.pathParameters['orderId']!)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'settings',
                  path: '/settings',
                  builder: (_, _) => FocusScope(node: branchesScope['settings'], child: const SettingsPage()),
                  routes: <GoRoute>[
                    _slide(
                      'perAppProxy',
                      'per-app',
                      (_) => const PerAppProxyPage(),
                      routes: [_slide('appList', 'app-list', (_) => const AppListPage())],
                    ),
                    // 1.2.2: 高级 (a page with this one row) is gone; TLS 分片 opens from 设置 directly
                    _slide('tlsTricks', 'tls-tricks', (_) => const TlsTricksPage()),
                    _slide('connections', 'connections', (_) => const MuseDataPage()),
                    _slide(
                      'about',
                      'about',
                      (_) => const AboutPage(),
                      routes: [_slide('openSource', 'open-source', (_) => const OpenSourcePage())],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
