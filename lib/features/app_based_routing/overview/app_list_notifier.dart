import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/app_based_routing/data/selected_data_provider.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/overview/auto_selection_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/index.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_list_notifier.g.dart';

/// An app's logo, fetched once per run: the plugin lists every installed app for each lookup. Each logo stays in
/// memory until the app closes, so this is for a few logos, like the routing page's apps row, not for whole lists.
@Riverpod(keepAlive: true)
Future<Uint8List?> appLogo(Ref ref, String packageName) async =>
    (await InstalledApps.getAppInfo(packageName, BuiltWith.flutter))?.icon;

@riverpod
class AppList extends _$AppList with AppLogger {
  @override
  Stream<Map<String, int>> build(AppProxyMode? mode) {
    if (mode == null) return Stream.value({});
    final appsInfo = InstalledApps.getInstalledApps(false);
    return Stream.fromFuture(appsInfo).asyncExpand((appsInfo) {
      final phonePkgs = appsInfo.map((e) => e.packageName).toSet();
      return ref.watch(appProxyDataSourceProvider).watchFilterForDisplay(phonePkgs: phonePkgs, mode: mode).map((
        entryList,
      ) {
        return {for (final entry in entryList) entry.pkgName: entry.flags};
      });
    });
  }

  Future<void> updatePkg(String pkg) async {
    loggy.info('Updationg $pkg status');
    await ref.read(appProxyDataSourceProvider).updatePkg(pkg: pkg, mode: mode!);
  }

  Future<void> clearAll() async {
    loggy.info('Clearing all items');
    await ref.read(appProxyDataSourceProvider).clearAll(mode: mode!);
    await ref.read(Preferences.autoAppsSelectionRegion.notifier).update(null);
    ref.read(autoSelectionIssueProvider.notifier).update(null);
  }
}
