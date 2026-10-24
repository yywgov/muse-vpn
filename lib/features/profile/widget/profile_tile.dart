import 'package:hiddify/features/muse/settings/sub_filter_dialog.dart';
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/muse/widget/qr_view.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/logic/node_order.dart';
import 'package:hiddify/features/muse/logic/subscription_bar.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:flutter/rendering.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfileTile extends HookConsumerWidget {
  const ProfileTile({super.key, required this.profile, this.margin = EdgeInsets.zero});

  final ProfileEntity profile;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final selectActiveMutation = useMutation(
      initialOnFailure: (err) {
        CustomToast.error(t.presentShortError(err)).show(context);
      },
      initialOnSuccess: () {
        if (context.mounted && context.canPop()) context.pop();
      },
    );

    final subInfo = switch (profile) {
      RemoteProfileEntity(:final subInfo) => subInfo,
      _ => null,
    };


    void handleTap() {
      if (selectActiveMutation.state.isInProgress) return;
      selectActiveMutation.setFuture(ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id));
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed('home');
      }
    }

    // 1.3.0: flat inside the 订阅 card; the active one is tinted (brand = selected state only)
    final mt = MuseTheme.of(context);
    final card = Card(
      margin: EdgeInsets.zero,
      color: profile.active ? mt.selected : MusePalette.transparent,
      surfaceTintColor: MusePalette.transparent,
      shadowColor: MusePalette.transparent,
      shape: const RoundedRectangleBorder(borderRadius: ProfileTileConst.cardBorderRadius),
      elevation: 0,
      child: IntrinsicHeight(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 48,
                child: Semantics(sortKey: const OrdinalSortKey(1), child: ProfileActionButton(profile, true)),
              ),
              VerticalDivider(width: 1, thickness: 0.5, color: mt.hairline),
              Expanded(child: _body(context, t, theme, subInfo, handleTap)),
            ],
          ),
        ),
      ),
    );

    return Padding(padding: margin, child: card);
  }

  /// The tappable content: the profile name followed by the subscription info.
  Widget _body(
    BuildContext context,
    Translations t,
    ThemeData theme,
    SubscriptionInfo? subInfo,
    VoidCallback onTap,
  ) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: ProfileTileConst.endBorderRadius(Directionality.of(context)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s12, vertical: MuseSpace.s4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(t, theme),
              // 穿云 1.2: remaining traffic / time as a thin bar, red when low or expiring — no text
              if (subInfo != null)
                if (museSubscriptionBar(subInfo) case final bar?) ...[
                  const Gap(6),
                  LinearProgressIndicator(
                    key: const ValueKey('subscription_bar'),
                    value: bar.remaining,
                    minHeight: 4,
                    borderRadius: MuseRadius.smallAll,
                    color: bar.warn ? theme.colorScheme.error : theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                  const Gap(4),
                ],
              // 穿云 1.2.5: 「已用 12.3 GB / 100 GB · 剩 23 天 · 3 小时前更新」 (Clash Verge Rev's card)
              if (profile is RemoteProfileEntity)
                Text(
                  subInfo != null
                      ? museSubscriptionSummary(
                          upload: subInfo.upload,
                          download: subInfo.download,
                          total: subInfo.total,
                          expire: subInfo.expire,
                          lastUpdate: profile.lastUpdate,
                          now: DateTime.now(),
                        )
                      : museUpdatedAgo(profile.lastUpdate, now: DateTime.now()),
                  key: const ValueKey('subscription_summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (profile is RemoteProfileEntity) const Gap(2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(Translations t, ThemeData theme) {
    return Text(
      profile.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null),
      semanticsLabel: profile.active
          ? t.pages.profiles.activeProfileName(name: profile.name)
          : t.pages.profiles.nonActiveProfileName(name: profile.name),
    );
  }
}

class ProfileActionButton extends HookConsumerWidget {
  const ProfileActionButton(this.profile, this.showAllActions, {super.key, this.squareBottom = false});

  final ProfileEntity profile;
  final bool showAllActions;

  /// Zeroes this button's bottom corner, matching the card when a link chip
  /// is attached flush below it.
  final bool squareBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final update = ref.watch(updateProfileNotifierProvider(profile.id));
    final isUpdating = update.isLoading;
    // Success/failure flash is derived straight from the provider state, which
    // UpdateProfileNotifier holds for 2s then resets. It lives in the provider
    // (not widget state), so it survives the list re-sorting after an update.
    final bool? outcome = isUpdating
        ? null
        : update.hasError
        ? false
        : (update.value != null ? true : null);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.6, curve: Curves.easeOut),
          reverseCurve: Curves.easeIn,
        ),
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn),
          child: child,
        ),
      ),
      // Expand children so the interactive leading keeps its full tap target.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: _leading(context, ref, t, isUpdating, outcome),
    );
  }

  /// The current leading content. Each state carries a distinct key so the
  /// [AnimatedSwitcher] cross-fades between them.
  Widget _leading(BuildContext context, WidgetRef ref, Translations t, bool isUpdating, bool? outcome) {
    if (profile case RemoteProfileEntity()) {
      // While updating, the leading is a spinning indicator; its action is blocked.
      if (isUpdating) {
        return Semantics(
          key: const ValueKey('updating'),
          label: t.pages.profiles.update,
          liveRegion: true,
          child: Tooltip(message: t.pages.profiles.update, child: const _UpdatingIndicator()),
        );
      }

      // Transient success/failure feedback shown for 2s right after the spinner.
      if (outcome case final success?) {
        return Semantics(
          key: ValueKey(success),
          label: success ? t.pages.profiles.msg.update.success : t.pages.profiles.msg.update.failure,
          liveRegion: true,
          child: Icon(
            success ? Icons.check_circle_outlined : Icons.error_outlined,
            color: success ? MusePalette.green : Theme.of(context).colorScheme.error,
          ),
        );
      }

      if (!showAllActions) {
        return Semantics(
          key: const ValueKey('update'),
          button: true,
          child: Tooltip(
            message: t.pages.profiles.update,
            child: InkWell(
              borderRadius: ProfileTileConst.startBorderRadius(Directionality.of(context), squareBottom: squareBottom),
              onTap: () => ref
                  .read(updateProfileNotifierProvider(profile.id).notifier)
                  .updateProfile(profile as RemoteProfileEntity),
              child: const Icon(Icons.sync_outlined),
            ),
          ),
        );
      }
    }
    return ProfileActionsMenu(profile, (context, toggleVisibility, _) {
      return Semantics(
        button: true,
        child: Tooltip(
          message: MaterialLocalizations.of(context).showMenuTooltip,
          child: InkWell(
            borderRadius: ProfileTileConst.startBorderRadius(Directionality.of(context), squareBottom: squareBottom),
            onTap: toggleVisibility,
            child: Icon(AdaptiveIcon(context).more),
          ),
        ),
      );
    }, key: const ValueKey('menu'));
  }
}

/// A minimal, continuously spinning icon shown in the leading slot while a
/// remote profile is being updated.
class _UpdatingIndicator extends StatefulWidget {
  const _UpdatingIndicator();

  @override
  State<_UpdatingIndicator> createState() => _UpdatingIndicatorState();
}

class _UpdatingIndicatorState extends State<_UpdatingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: ReverseAnimation(_controller),
      child: Icon(Icons.sync_outlined, color: Theme.of(context).colorScheme.onSurface),
    );
  }
}

class ProfileActionsMenu extends HookConsumerWidget {
  const ProfileActionsMenu(this.profile, this.builder, {super.key, this.child});

  final ProfileEntity profile;
  final AdaptiveMenuBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final menuItems = [
      if (profile case RemoteProfileEntity())
        AdaptiveMenuItem(
          title: t.common.update,
          leadingIcon: const Icon(Icons.sync_outlined),
          onTap: () {
            if (ref.read(updateProfileNotifierProvider(profile.id)).isLoading) {
              return;
            }
            ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile as RemoteProfileEntity);
          },
        ),
      // 1.4.0: QR code of the subscription (scanned by another phone, opens 穿云 to import)
      if (profile case final RemoteProfileEntity remote)
        AdaptiveMenuItem(
          leadingIcon: const Icon(Icons.qr_code_2_outlined),
          title: '二维码分享',
          onTap: () => showMuseQrDialog(
            context,
            title: remote.name,
            data: museSubscriptionQrPayload(remote.url, name: remote.name),
            copyText: remote.url,
          ),
        ),
      // 1.5.0 #43: 只显示 / 排除 for this subscription alone
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.filter_alt_outlined),
        title: '节点筛选',
        onTap: () => museEditSubFilter(context, ref, profile.id),
      ),
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.edit_outlined),
        title: '编辑',
        // MenuAnchor closes itself; popping here would pop the 配置 tab root and swallow the tap.
        onTap: () => context.pushNamed('profileDetails', pathParameters: {'id': profile.id}),
      ),
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.delete_outlined),
        title: t.common.delete,
        onTap: () async => await ref
            .read(dialogNotifierProvider.notifier)
            .showConfirmation(
              title: t.dialogs.confirmation.profile.delete.title,
              message: t.dialogs.confirmation.profile.delete.msg,
            )
            .then((deleteConfirmed) async {
              if (!deleteConfirmed) return;
              await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
            }),
      ),
    ];

    return AdaptiveMenu(builder: builder, items: menuItems, child: child);
  }
}

class ProfileSubscriptionInfo extends HookConsumerWidget {
  const ProfileSubscriptionInfo(this.subInfo, {super.key});

  final SubscriptionInfo subInfo;

  (String, Color?) remainingText(Translations t, ThemeData theme) {
    if (subInfo.isExpired) {
      return (t.components.subscriptionInfo.expired, theme.colorScheme.error);
    } else if (subInfo.ratio >= 1) {
      return (t.components.subscriptionInfo.noTraffic, theme.colorScheme.error);
    } else if (subInfo.remaining.inDays > 365) {
      return (t.components.subscriptionInfo.remainingUnlimited, null);
    } else {
      return (t.components.subscriptionInfo.remainingDuration(days: subInfo.remaining.inDays), null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final remaining = remainingText(t, theme);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Flexible(
            child: Text(
              subInfo.total >
                      10 *
                          1099511627776 //10TB
                  ? "∞ GiB"
                  : subInfo.consumption.sizeOf(subInfo.total),
              semanticsLabel: t.components.subscriptionInfo.remainingTrafficSemanticLabel(
                consumed: subInfo.consumption.sizeGB(),
                total: subInfo.total.sizeGB(),
              ),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Flexible(
          child: Text(
            remaining.$1,
            style: theme.textTheme.bodySmall?.copyWith(color: remaining.$2),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// TODO change colors
class RemainingTrafficIndicator extends StatelessWidget {
  const RemainingTrafficIndicator(this.ratio, {super.key});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(value: ratio, borderRadius: MuseRadius.cardAll, minHeight: 6);
  }
}
