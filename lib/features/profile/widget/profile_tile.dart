import 'package:flutter/material.dart';
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

    final card = Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: profile.active ? BorderSide(color: theme.colorScheme.outline) : BorderSide.none,
        borderRadius: ProfileTileConst.cardBorderRadius,
      ),
      elevation: profile.active ? 0 : 1,
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
              if (profile.active) VerticalDivider(width: 1, color: theme.colorScheme.outline) else const Gap(1),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(t, theme),
              if (subInfo != null) ...[
                const Gap(4),
                RemainingTrafficIndicator(subInfo.ratio),
                const Gap(4),
                ProfileSubscriptionInfo(subInfo),
                const Gap(4),
              ],
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
            success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: success ? Colors.green : Theme.of(context).colorScheme.error,
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
              child: const Icon(Icons.sync_rounded),
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
      child: Icon(Icons.sync_rounded, color: Theme.of(context).colorScheme.onSurface),
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
          leadingIcon: const Icon(Icons.sync_rounded),
          onTap: () {
            if (ref.read(updateProfileNotifierProvider(profile.id)).isLoading) {
              return;
            }
            ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile as RemoteProfileEntity);
          },
        ),
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.edit_rounded),
        title: '编辑',
        // MenuAnchor closes itself; popping here would pop the 配置 tab root and swallow the tap.
        onTap: () => context.pushNamed('profileDetails', pathParameters: {'id': profile.id}),
      ),
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.delete_outline_rounded),
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
    return LinearProgressIndicator(value: ratio, borderRadius: BorderRadius.circular(16), minHeight: 6);
  }
}
