// 穿云 1.20.2 - 订阅并入节点页：节点页标题就是当前订阅（「VPS主力 ▾」），点开是订阅弹层
// （手机底部弹层 / 电脑挂在标题下的 440 宽浮层）：订阅列表（名称、余量、到期、更新时间），每个订阅的
// 「⋮」放原有全部操作 + 订阅覆写，顶部放全部更新 / 更多（排序、自动更新、导入导出配置）/ 添加。
// 没有订阅时节点页直接给「添加订阅」与导入方式。首页顶部订阅名、流量 / 到期卡、设置搜索「订阅」、旧地址
// /config（快捷方式、托盘、深链、冒烟脚本）都打开同一个弹层。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/muse/config/muse_config_page.dart' show showMuseProfileOrder;
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/home/clipboard_import.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/profile_tools.dart';
import 'package:hiddify/features/muse/logic/subscription_bar.dart';
import 'package:hiddify/features/muse/settings/more_settings.dart' show musePick, museExportConfig, museImportConfig, museExportConfigTitle, museImportConfigTitle;
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_home.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart' show museAddFromClipboard, museAddByQr, museAddFromFile;
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart' show ProfileActionsMenu;
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 旧订阅地址（/config）要求打开弹层：节点页标题读到后清掉再开。用布尔而不是计数，同一次导航里重定向
/// 被求值几次、或弹层已经开着，都只开一次。
final museSubsSheetPendingProvider = StateProvider<bool>((ref) => false);

var _museSubsRequestQueued = false;

/// 订阅弹层是否开着（再次要求打开时不叠第二个）。
var museSubsSheetOpen = false;

/// 由路由重定向调用：下一帧置「待打开」（重定向可能在构建期间求值，不能当场改 provider）。同一帧内多次调用
/// 只排一次。
void museRequestSubsSheet(StateController<bool> pending) {
  if (_museSubsRequestQueued) return;
  _museSubsRequestQueued = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _museSubsRequestQueued = false;
    if (!museSubsSheetOpen) pending.state = true;
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

ModalRoute<dynamic>? _museSubsRoute;

/// 换到别的页面（底栏以外的跳转：托盘、快捷方式、深链、冒烟脚本）时关掉还开着的订阅弹层，免得它留在
/// 别的页面上面。由外壳在地址变化后的下一帧调用。
void museCloseSubsSheet() {
  final r = _museSubsRoute;
  _museSubsRoute = null;
  if (r != null && r.isActive) r.navigator?.removeRoute(r);
  museSubsSheetOpen = false;
}

/// 「订阅」现在在哪里打开：就地打开订阅弹层（首页流量 / 到期卡、设置搜索「订阅」）。
Future<void> museOpenSubscriptions(BuildContext context, WidgetRef ref) => museShowSubsSheet(context);

/// The sheet (phone) or the panel under the title (wide window).
Future<void> museShowSubsSheet(BuildContext context, {GlobalKey? anchor}) async {
  if (museSubsSheetOpen) return;
  museSubsSheetOpen = true;
  try {
    await _showSubsSheet(context, anchor: anchor);
  } finally {
    museSubsSheetOpen = false;
  }
}

Future<void> _showSubsSheet(BuildContext context, {GlobalKey? anchor}) {
  final desk = museDeskWide(context);
  if (!desk) {
    final h = MediaQuery.sizeOf(context).height;
    // 根导航：盖住底栏；从弹层打开的编辑 / 覆写页也在根导航上，返回回到弹层
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MuseTheme.of(context).bgBottom,
      constraints: BoxConstraints(maxHeight: h * 0.85),
      builder: (c) {
        _museSubsRoute = ModalRoute.of(c);
        return const MuseSubsPanel();
      },
    );
  }
  // wide window: a panel hanging under the title it came from (no full-width sheet on a desk)
  var at = const Offset(MuseSpace.s24, MuseSpace.s32 * 2);
  final box = anchor?.currentContext?.findRenderObject();
  if (box is RenderBox && box.hasSize) at = box.localToGlobal(Offset(0, box.size.height + MuseSpace.s4));
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    builder: (c) {
      _museSubsRoute = ModalRoute.of(c);
      return Dialog(
      alignment: Alignment.topLeft,
      insetPadding: EdgeInsets.only(left: at.dx, top: at.dy, right: MuseSpace.s24, bottom: MuseSpace.s24),
      backgroundColor: MuseTheme.of(c).bgBottom,
      shape: MuseShape.of(MuseHomeA.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: MuseSubsPanel.deskWidth, maxHeight: 560),
        child: const Padding(padding: EdgeInsets.only(top: MuseSpace.s8), child: MuseSubsPanel()),
      ),
    );
    },
  );
}

/// The 节点 page's title: the subscription in use with a ▾ (opens [museShowSubsSheet]).
class MuseSubSwitcher extends HookConsumerWidget {
  const MuseSubSwitcher({super.key, this.style});

  /// 标题字样（默认：手机 22/600，电脑 24/600）
  final TextStyle? style;

  /// 默认标题字样
  static TextStyle defaultStyle(BuildContext context) =>
      museDeskWide(context) ? MuseScaffold.deskTitle(context) : MuseTextLevel.title2.style(context, weight: FontWeight.w600);

  /// 名称后 ▾ 与左右内边距占的宽度
  static const chromeWidth = MuseSpace.s4 * 3 + MuseIconSize.regular;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = useMemoized(GlobalKey.new);
    final mt = MuseTheme.of(context);
    final name = ref.watch(museActiveProfileNameProvider)?.trim() ?? '';
    final shown = name.isEmpty ? '订阅' : name;
    final style = this.style ?? defaultStyle(context);
    final count = ref.watch(profilesNotifierProvider).valueOrNull?.length ?? 0;
    // 旧订阅地址要求打开弹层（挂上时已在等也算）：清掉标记再开，只开一次
    final pending = ref.watch(museSubsSheetPendingProvider);
    useEffect(() {
      if (!pending) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !ref.read(museSubsSheetPendingProvider)) return;
        ref.read(museSubsSheetPendingProvider.notifier).state = false;
        museShowSubsSheet(context, anchor: anchor);
      });
      return null;
    }, [pending]);
    return Semantics(
      button: true,
      label: '切换订阅，当前 $shown${count > 1 ? '，共 $count 个' : ''}',
      excludeSemantics: true,
      child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('nodes_sub_switcher'),
            borderRadius: MuseRadius.smallAll,
            onTap: () => museShowSubsSheet(context, anchor: anchor),
            child: ConstrainedBox(
              key: anchor,
              constraints: const BoxConstraints(minHeight: MuseSize.button),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: MuseSpace.s4, end: MuseSpace.s4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(shown, key: const ValueKey('muse_page_title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                    ),
                    const SizedBox(width: MuseSpace.s4),
                    Icon(Icons.expand_more_outlined, size: MuseIconSize.regular, color: mt.text2),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

/// The sheet's content: header (订阅 · 全部更新 · ⋯ · 添加) and one row per subscription.
class MuseSubsPanel extends ConsumerWidget {
  const MuseSubsPanel({super.key});

  static const deskWidth = 440.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final profiles = ref.watch(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
    final byId = {for (final p in profiles) p.id: p};
    final ordered = [for (final id in museOrderIds(profiles.map((e) => e.id).toList(), ref.watch(MusePrefs.profileOrder))) ?byId[id]];
    final remotes = profiles.whereType<RemoteProfileEntity>().length;

    Future<void> onMore(String v) async {
      switch (v) {
        case 'order':
          await showMuseProfileOrder(context, ref, profiles);
        case 'auto_update':
          final hours = ref.read(Preferences.museAutoUpdateHours);
          final picked = await musePick<int>(context, '订阅自动更新', [for (final h in museAutoUpdateChoices) (h, museAutoUpdateLabel(h))], hours);
          if (picked != null) await ref.read(Preferences.museAutoUpdateHours.notifier).update(picked);
        case 'test_new_nodes':
          await ref.read(MusePrefs.testNewNodes.notifier).update(!ref.read(MusePrefs.testNewNodes));
        case 'export':
          await museExportConfig(context, ref);
        case 'import':
          await museImportConfig(context, ref);
      }
    }

    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(MuseSpace.s24, 0, MuseSpace.s16, MuseSpace.s8),
      child: Row(
        children: [
          Expanded(child: Text('订阅', style: MuseType.title(context))),
          if (remotes > 0)
            IconButton(
              key: const ValueKey('subs_update_all'),
              tooltip: '更新全部订阅',
              // each row shows its own 「正在更新…」 while it runs
              onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
              icon: const Icon(Icons.sync_outlined),
            ),
          PopupMenuButton<String>(
            key: const ValueKey('subs_more'),
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz_outlined),
            onSelected: onMore,
            itemBuilder: (_) => [
              if (profiles.length > 1) const PopupMenuItem(key: ValueKey('subs_more_order'), value: 'order', child: Text('排序')),
              PopupMenuItem(
                key: const ValueKey('auto_update_hours'),
                value: 'auto_update',
                child: Text('订阅自动更新：${museAutoUpdateLabel(ref.read(Preferences.museAutoUpdateHours))}'),
              ),
              CheckedPopupMenuItem(
                key: const ValueKey('test_new_nodes'),
                value: 'test_new_nodes',
                checked: ref.read(MusePrefs.testNewNodes),
                child: const Text('更新后测速新增节点'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(key: ValueKey('subs_more_import'), value: 'import', child: Text(museImportConfigTitle)),
              const PopupMenuItem(key: ValueKey('subs_more_export'), value: 'export', child: Text(museExportConfigTitle)),
            ],
          ),
          const SizedBox(width: MuseSpace.s4),
          FilledButton.tonalIcon(
            key: const ValueKey('subs_add'),
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
            },
            icon: const Icon(Icons.add_outlined, size: MuseIconSize.small),
            label: const Text('添加'),
          ),
        ],
      ),
    );

    final rows = <Widget>[
      for (var i = 0; i < ordered.length; i++) ...[
        if (i > 0) Divider(height: MuseSize.hairline, thickness: MuseSize.hairline, indent: MuseSpace.s16 + MuseSize.button, color: mt.hairline),
        _SubRow(key: ValueKey('subs_row_${ordered[i].id}'), profile: ordered[i]),
      ],
    ];
    return Column(
      key: const ValueKey('subs_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const MuseClipboardOfferTile(),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s16 + MediaQuery.paddingOf(context).bottom),
            child: Material(
              color: mt.card,
              shape: MuseShape.of(MuseHomeA.radiusCard),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: rows),
            ),
          ),
        ),
      ],
    );
  }
}

/// One subscription: ◉ name / bar + what is left / 到期 · 更新时间 / ⋮.
class _SubRow extends ConsumerWidget {
  const _SubRow({super.key, required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final active = profile.active;
    final remote = profile is RemoteProfileEntity ? profile as RemoteProfileEntity : null;
    final info = remote?.subInfo;
    final updating = ref.watch(updateProfileNotifierProvider(profile.id)).isLoading;
    final now = DateTime.now();
    final bars = info == null ? const <MuseSubBar>[] : museSubscriptionBars(info, now: now);
    final traffic = bars.where((b) => b.kind == 'traffic').firstOrNull;
    final expiry = bars.where((b) => b.kind == 'expiry').firstOrNull;
    final bar = traffic ?? expiry;
    // 「剩 87 GB / 120 GB」 next to the bar; 「29 天后到期 · 3 小时前更新」 below
    final left = info == null ? '' : museBytes((info.total - info.upload - info.download).clamp(0, info.total));
    final barText = traffic != null && info != null ? '剩 $left / ${museBytes(info.total)}' : (bar?.trailing ?? '');
    final meta = [
      if (expiry != null && traffic != null) expiry.trailing == '已到期' ? '已到期' : '${expiry.trailing.replaceFirst('剩 ', '')}后到期',
      if (remote != null) updating ? '正在更新…' : museUpdatedAgo(remote.lastUpdate, now: now),
      if (remote == null) '本地配置',
    ].join(' · ');

    Future<void> pick() async {
      final nav = Navigator.of(context);
      if (!active) {
        try {
          await ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id);
        } catch (_) {
          try {
            ref.read(inAppNotificationControllerProvider).showErrorToast('切换订阅失败');
          } catch (_) {}
          return;
        }
      }
      if (nav.mounted && nav.canPop()) nav.pop();
    }

    final body = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(MuseSpace.s16, MuseSpace.s12, 0, MuseSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ◉ = in use (the same radio idea as a choice list; the row itself is the target)
          Icon(
            active ? Icons.radio_button_checked_outlined : Icons.radio_button_unchecked_outlined,
            size: MuseIconSize.regular,
            color: active ? museBrandOf(context) : mt.text3,
          ),
          const SizedBox(width: MuseSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MuseTextLevel.callout.style(context, weight: active ? FontWeight.w600 : FontWeight.w400),
                ),
                if (bar != null) ...[
                  const SizedBox(height: MuseSpace.s8),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          key: ValueKey('subs_bar_${bar.kind}'),
                          value: bar.remaining,
                          minHeight: MuseSpace.s4,
                          borderRadius: MuseRadius.smallAll,
                          color: bar.warn ? scheme.error : museBrandOf(context),
                          backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      const SizedBox(width: MuseSpace.s8),
                      Text(barText, style: MuseType.caption(context).copyWith(color: bar.warn ? scheme.error : mt.text2)),
                    ],
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: MuseSpace.s4),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MuseType.caption(context).copyWith(
                      color: updating ? museBrandOf(context) : (expiry != null && expiry.warn && traffic != null ? scheme.error : mt.text2),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ⋮: every action the old 订阅 card had, plus 订阅覆写
          ProfileActionsMenu(
            profile,
            (context, toggle, _) => IconButton(
              key: ValueKey('subs_row_menu_${profile.id}'),
              tooltip: '${profile.name} 的操作',
              onPressed: toggle,
              icon: const Icon(Icons.more_vert_outlined),
            ),
          ),
          const SizedBox(width: MuseSpace.s4),
        ],
      ),
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: active,
      child: Material(
        color: active ? scheme.primary.withValues(alpha: 0.06) : MusePalette.transparent,
        child: InkWell(onTap: pick, child: body),
      ),
    );
  }
}

/// 节点 page with no subscription: one clear first step and the other ways in.
class MuseNodesEmpty extends HookConsumerWidget {
  const MuseNodesEmpty({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    // 没有订阅时这一页本身就是订阅入口：旧地址要求的弹层不再补开
    final pending = ref.watch(museSubsSheetPendingProvider);
    useEffect(() {
      if (!pending) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(museSubsSheetPendingProvider.notifier).state = false;
      });
      return null;
    }, [pending]);
    Widget way(String key, IconData icon, String label, VoidCallback onTap) => OutlinedButton.icon(
      key: ValueKey('nodes_empty_$key'),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, MuseSize.button),
        foregroundColor: mt.text1,
        side: BorderSide(color: mt.hairline),
      ),
      icon: Icon(icon, size: MuseIconSize.small, color: mt.text2),
      label: Text(label),
    );
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: MuseSpace.page(context), vertical: MuseSpace.s24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - MuseSpace.s24 * 2),
          child: Align(
            // a little above the middle: the eye lands on it first, the thumb still reaches 添加订阅
            alignment: const Alignment(0, -0.3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                key: const ValueKey('nodes_empty'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.link_outlined, size: MuseIconSize.large, color: mt.text3),
                  const SizedBox(height: MuseSpace.s16),
                  Text('还没有订阅', textAlign: TextAlign.center, style: MuseTextLevel.title3.style(context)),
                  const SizedBox(height: MuseSpace.s8),
                  Text(
                    '添加订阅链接后，节点会列在这里，可以测速和切换。',
                    textAlign: TextAlign.center,
                    style: MuseTextLevel.subheadline.style(context, color: mt.text2),
                  ),
                  const SizedBox(height: MuseSpace.s24),
                  const MuseClipboardOfferTile(),
                  FilledButton.icon(
                    key: const ValueKey('nodes_empty_add'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(MuseHomeA.button)),
                    onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                    icon: const Icon(Icons.add_outlined),
                    label: const Text('添加订阅'),
                  ),
                  const SizedBox(height: MuseSpace.s24),
                  Text('或直接', textAlign: TextAlign.center, style: MuseType.caption(context)),
                  const SizedBox(height: MuseSpace.s8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: MuseSpace.s8,
                    runSpacing: MuseSpace.s8,
                    children: [
                      way('paste', Icons.content_paste_outlined, '粘贴链接', () => museAddFromClipboard(context, ref)),
                      if (!PlatformUtils.isDesktop) way('qr', Icons.qr_code_scanner_outlined, '扫描二维码', () => museAddByQr(ref)),
                      way('file', Icons.insert_drive_file_outlined, '从文件导入', () => museAddFromFile(ref)),
                      way('restore', Icons.settings_backup_restore_outlined, '从备份恢复', () => museImportConfig(context, ref)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
