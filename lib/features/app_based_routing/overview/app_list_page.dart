// 穿云 1.6.0 C9: sort (已选优先 / 名称 / 安装时间), 只看联网应用, 全选 / 反选 of what is shown, and
// the list to / from the clipboard (one package name per line). The installed apps are read once
// (with icons) plus a light list of the user's apps that marks system apps, instead of two full
// reads with icons. List logic in muse/logic/per_app_tools.dart.

import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/app_based_routing/data/selected_data_provider.dart';
import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';
import 'package:hiddify/features/app_based_routing/overview/app_list_notifier.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/per_app_tools.dart';
import 'package:hiddify/features/muse/widget/muse_sheet.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/index.dart';

/// The installed apps (icons included), system apps marked. Overridable in tests.
final museInstalledAppsProvider = FutureProvider.autoDispose<List<MuseAppRow>>((ref) async {
  if (!PlatformUtils.isAndroid) return const [];
  final all = await InstalledApps.getInstalledApps(false, true);
  final user = {for (final a in await InstalledApps.getInstalledApps(true, false)) a.packageName};
  return [
    for (final a in all)
      MuseAppRow(
        packageName: a.packageName,
        name: a.name,
        installed: a.installedTimestamp,
        system: !user.contains(a.packageName),
        icon: a.icon,
      ),
  ];
});

/// Apps that asked for network access (null = unknown). Read only when 只看联网应用 is on.
final museInternetAppsProvider = FutureProvider.autoDispose<Set<String>?>((_) => ChuanyunPlatform.internetPackages());

class AppListPage extends HookConsumerWidget with PresLogger {
  const AppListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final localizations = MaterialLocalizations.of(context);

    final mode = ref.watch(Preferences.perAppProxyModeInUse);
    final selectedApps = ref.watch(AppListProvider(mode));

    final hideSystemApps = useState(false);
    final isSearching = useState(false);
    final searchQuery = useState("");
    final sortListener = useState(false);
    final sort = MuseAppSort.fromKey(ref.watch(MusePrefs.appSort));
    final internetOnly = ref.watch(MusePrefs.appInternetOnly);
    final internet = internetOnly ? ref.watch(museInternetAppsProvider).valueOrNull : null;

    final asyncApps = ref.watch(museInstalledAppsProvider);

    // the order is fixed while you tick boxes (only a bulk change, a filter or the sort re-sorts)
    final displayedApps = useMemoized<AsyncValue<List<MuseAppRow>>>(
      () {
        if (!(selectedApps.hasValue && selectedApps is AsyncData && asyncApps.hasValue)) {
          return const AsyncValue.loading();
        }
        return AsyncValue.data(
          museAppView(
            asyncApps.requireValue,
            flags: selectedApps.requireValue,
            sort: sort,
            query: searchQuery.value,
            hideSystem: hideSystemApps.value,
            internetOnly: internetOnly,
            internet: internet,
          ),
        );
      },
      [
        asyncApps.hasValue,
        hideSystemApps.value,
        selectedApps.hasValue,
        searchQuery.value,
        sortListener.value,
        sort,
        internetOnly,
        internet,
      ],
    );

    if (mode != null) {
      ref.listen(AppListProvider(mode), (previous, next) {
        if (previous != null) {
          if ((previous, next) case (AsyncData(value: final prevData), AsyncData(value: final nextData))) {
            if (nextData.isNotEmpty) {
              if ((nextData.length - prevData.length).abs() > 1) sortListener.value = !sortListener.value;
            }
          }
        }
      });
    }

    final scrollController = useScrollController();
    const double scrollThreshold = 300.0;
    final showScrollToTop = useState<bool>(false);
    useEffect(() {
      void listener() {
        showScrollToTop.value = scrollController.offset > scrollThreshold;
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, []);
    useEffect(() {
      showScrollToTop.value = false;
      return null;
    }, [displayedApps]);

    final appBasedRouting = t.pages.settings.routing.appBasedRouting;
    // the auto picks you removed: the chip brings them back, and the toast can take that back
    final removed = [
      for (final entry in (selectedApps.valueOrNull ?? const <String, int>{}).entries)
        if (PkgFlag.autoSelection.check(entry.value) && PkgFlag.forceDeselection.check(entry.value)) entry.key,
    ];
    Future<void> restoreRemoved() async {
      final dataSource = ref.read(appProxyDataSourceProvider);
      final restoredMode = mode!;
      await dataSource.revertForceDeselection(mode: restoredMode);
      ref
          .read(inAppNotificationControllerProvider)
          .showSuccessToast(
            appBasedRouting.autoSelection.restored(n: removed.length),
            action: (
              label: t.common.undo,
              // removes them again, as a tap on each would
              onPressed: () async {
                for (final pkg in removed) {
                  await dataSource.updatePkg(pkg: pkg, mode: restoredMode);
                }
              },
            ),
          );
    }

    void toast(String text) {
      try {
        ref.read(inAppNotificationControllerProvider).showSuccessToast(text);
      } catch (_) {}
    }

    // 全选 / 反选 act on what is shown (search, filters), then the list re-sorts once
    List<MuseAppRow> shown() => displayedApps.valueOrNull ?? const [];
    Map<String, int> flagsNow() => selectedApps.valueOrNull ?? const {};
    Future<void> selectAll() async {
      final targets = museSelectAllTargets(shown(), flagsNow());
      await ref.read(AppListProvider(mode).notifier).setSelected(targets, selected: true);
      sortListener.value = !sortListener.value;
      toast('已选择 ${targets.length} 个');
    }

    Future<void> invert() async {
      final r = museInvertTargets(shown(), flagsNow());
      final n = ref.read(AppListProvider(mode).notifier);
      await n.setSelected(r.select, selected: true);
      await n.setSelected(r.deselect, selected: false);
      sortListener.value = !sortListener.value;
      toast('已反选 ${r.select.length + r.deselect.length} 个');
    }

    Future<void> importClipboard() async {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      final parsed = museParsePackageList(text);
      if (parsed.packages.isEmpty) {
        try {
          ref
              .read(inAppNotificationControllerProvider)
              .showErrorToast(
                parsed.skipped > 0 ? '剪贴板里没有有效的包名（忽略 ${parsed.skipped} 个）' : '剪贴板里没有包名（每行一个，如 com.example.app）',
              );
        } catch (_) {}
        return;
      }
      final flags = flagsNow();
      final fresh = [
        for (final p in parsed.packages)
          if (!museAppActive(flags[p])) p,
      ];
      await ref.read(AppListProvider(mode).notifier).setSelected(fresh, selected: true);
      sortListener.value = !sortListener.value;
      toast(
        museImportSummary(added: fresh.length, already: parsed.packages.length - fresh.length, skipped: parsed.skipped),
      );
    }

    Future<void> exportClipboard() async {
      final text = museExportPackageList(flagsNow());
      await Clipboard.setData(ClipboardData(text: text));
      toast(text.isEmpty ? '列表是空的' : '已复制 ${text.split('\n').length} 个包名');
    }

    final chips = PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: SizedBox(
        height: MuseSize.button,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
          // centered rather than stretched to the row: a chip squeezed or stretched draws its label off center;
          // 6 dp above and below the label makes the 32 dp chip of M3, where Flutter's 8 dp gives about 37
          children: [
            Center(
              child: ChoiceChip(
                padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8, vertical: MuseSpace.s8),
                label: Text(appBasedRouting.hideSysApps),
                selected: hideSystemApps.value,
                onSelected: (value) => hideSystemApps.value = value,
              ),
            ),
            const Gap(8),
            Center(
              child: ChoiceChip(
                key: const ValueKey('app_list_internet_only'),
                padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8, vertical: MuseSpace.s8),
                label: const Text('只看联网应用'),
                selected: internetOnly,
                onSelected: (value) => ref.read(MusePrefs.appInternetOnly.notifier).update(value),
              ),
            ),
            if (removed.isNotEmpty) ...[
              const Gap(8),
              Center(
                child: ActionChip(
                  padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8, vertical: MuseSpace.s8),
                  avatar: const Icon(Icons.undo_outlined),
                  label: Text(appBasedRouting.autoSelection.restore(n: removed.length)),
                  onPressed: restoreRemoved,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: isSearching.value
          ? AppBar(
              title: TextFormField(
                onChanged: (value) => searchQuery.value = value,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "${localizations.searchFieldLabel}...",
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
              leading: IconButton(
                onPressed: () {
                  searchQuery.value = "";
                  isSearching.value = false;
                },
                icon: const Icon(Icons.close_outlined),
                tooltip: localizations.cancelButtonLabel,
              ),
              bottom: chips,
            )
          : AppBar(
              title: Text(mode?.listTitle(t) ?? t.pages.settings.routing.appBasedRouting.title),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () => isSearching.value = true,
                  tooltip: localizations.searchFieldLabel,
                ),
                MuseAnchorMenu(
                  items: [
                    for (final o in MuseAppSort.values)
                      MuseMenuItem(
                        label: '排序：${o.label}',
                        icon: Icons.sort_outlined,
                        checked: o == sort,
                        onTap: () => ref.read(MusePrefs.appSort.notifier).update(o.key),
                      ),
                    MuseMenuItem(label: '全选', icon: Icons.select_all_outlined, onTap: mode == null ? null : selectAll),
                    MuseMenuItem(label: '反选', icon: Icons.flip_outlined, onTap: mode == null ? null : invert),
                    MuseMenuItem(
                      label: '从剪贴板导入',
                      icon: Icons.content_paste_outlined,
                      onTap: mode == null ? null : importClipboard,
                    ),
                    MuseMenuItem(
                      label: '复制到剪贴板',
                      icon: Icons.content_copy_outlined,
                      onTap: mode == null ? null : exportClipboard,
                    ),
                    MuseMenuItem(
                      label: t.pages.settings.routing.appBasedRouting.options.clearAllSelections,
                      icon: Icons.delete_sweep_outlined,
                      destructive: true,
                      onTap: () => ref.read(AppListProvider(mode).notifier).clearAll(),
                    ),
                  ],
                  builder: (context, toggle) => IconButton(
                    key: const ValueKey('app_list_menu'),
                    onPressed: toggle,
                    icon: const Icon(Icons.more_vert_outlined),
                  ),
                ),
              ],
              bottom: chips,
            ),
      floatingActionButton: showScrollToTop.value
          ? FloatingActionButton(
              onPressed: () =>
                  scrollController.animateTo(0.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut),
              child: const Icon(Icons.keyboard_arrow_up_outlined),
            )
          : null,
      body: displayedApps.when(
        data: (packages) => ListView.builder(
          padding: const EdgeInsets.only(bottom: MuseSize.fabClearance),
          controller: scrollController,
          itemBuilder: (context, index) {
            final package = packages[index];
            final flag = selectedApps.requireValue[package.packageName];
            return CheckboxListTile.adaptive(
              key: ValueKey('app_${package.packageName}'),
              title: Row(
                children: [
                  Flexible(child: Text(package.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (flag != null && PkgFlag.autoSelection.check(flag)) ...[
                    const Gap(6),
                    Text(
                      t.pages.settings.routing.appBasedRouting.autoTag,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                package.packageName,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              value: flag == null ? false : PkgFlag.checkboxValue(flag),
              tristate: true,
              onChanged: (_) => ref.read(AppListProvider(mode).notifier).updatePkg(package.packageName),
              secondary: package.icon == null
                  ? null
                  : Image.memory(
                      package.icon!,
                      width: MuseSize.appIconLarge,
                      height: MuseSize.appIconLarge,
                      cacheWidth: 48,
                      cacheHeight: 48,
                    ),
            );
          },
          itemCount: packages.length,
        ),
        error: (error, _) => SliverErrorBodyPlaceholder(error.toString()),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
