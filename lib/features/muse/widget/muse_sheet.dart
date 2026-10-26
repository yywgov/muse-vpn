// 穿云 1.6.0 C1 - snapping bottom sheet (two detents, 9/16 and 0.9, springy settle) and an
// anchored pop-up menu.
// Design rules adapted from GPL-3.0 code, Copyright (C) chen08209 (see THIRD_PARTY_NOTICES.md).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';

/// Shows a sheet that snaps to [MuseMotion.sheetDetents]; dragging below the lower detent, back,
/// Esc or tapping the scrim closes it. The [builder] gets the scroll controller to put on its list
/// so a drag on the list moves the sheet first.
Future<T?> showMuseSnapSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController controller) builder,
  String? title,
  bool startExpanded = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  final detents = MuseMotion.sheetDetents;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: MusePalette.transparent,
    barrierColor: scheme.modalScrim,
    sheetAnimationStyle: museReduceMotion(context) ? AnimationStyle.noAnimation : null,
    builder: (ctx) => Padding(
      // keyboard avoidance
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: MuseSnapSheet(title: title, startExpanded: startExpanded, detents: detents, builder: builder),
    ),
  );
}

class MuseSnapSheet extends StatelessWidget {
  const MuseSnapSheet({super.key, required this.builder, this.title, this.startExpanded = false, this.detents = MuseMotion.sheetDetents});

  final Widget Function(BuildContext context, ScrollController controller) builder;
  final String? title;
  final bool startExpanded;
  final List<double> detents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      snap: true,
      snapAnimationDuration: museReduceMotion(context) ? Duration.zero : MuseMotion.common,
      initialChildSize: startExpanded ? detents.last : detents.first,
      minChildSize: 0,
      maxChildSize: detents.last,
      snapSizes: detents,
      shouldCloseOnMinExtent: true,
      builder: (ctx, controller) => MuseSurfaceScope(
        level: MuseSurface.card,
        child: Material(
          key: const ValueKey('muse_snap_sheet'),
          color: MuseSurface.card.color(scheme),
          shape: MuseShape.sheet,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const _Handle(),
              if (title != null)
                SizedBox(
                  height: MuseSize.sheetToolbar,
                  child: Center(child: Text(title!, style: MuseTextLevel.headline.style(context))),
                ),
              Expanded(child: builder(ctx, controller)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: MuseSpace.s8),
    child: Container(
      width: MuseSize.sheetHandle,
      height: MuseSize.sheetHandleThickness,
      decoration: ShapeDecoration(color: Theme.of(context).colorScheme.outlineVariant, shape: MuseShape.full),
    ),
  );
}

/// One entry of a [MuseAnchorMenu].
class MuseMenuItem {
  const MuseMenuItem({required this.label, this.icon, this.onTap, this.destructive = false, this.checked});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool destructive;

  /// non-null: shows a check when true
  final bool? checked;
}

/// A pop-up menu anchored to its button (opens below it, flips above near the bottom edge).
class MuseAnchorMenu extends StatelessWidget {
  const MuseAnchorMenu({super.key, required this.items, required this.builder});

  final List<MuseMenuItem> items;
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(MuseSurface.block.color(scheme)),
        shape: WidgetStatePropertyAll(MuseShape.md),
        elevation: const WidgetStatePropertyAll(MuseSpace.s8),
        minimumSize: const WidgetStatePropertyAll(Size(MuseSize.menuWidth, 0)),
      ),
      menuChildren: [
        for (final i in items)
          MenuItemButton(
            onPressed: i.onTap,
            leadingIcon: i.icon == null ? null : Icon(i.icon, size: MuseIconSize.small, color: i.destructive ? scheme.destructive : null),
            trailingIcon: i.checked == true ? Icon(Icons.check_outlined, size: MuseIconSize.small, color: scheme.primary) : null,
            child: Text(i.label, style: i.destructive ? TextStyle(color: scheme.destructive) : null),
          ),
      ],
      builder: (ctx, controller, _) => builder(ctx, () => controller.isOpen ? controller.close() : controller.open()),
    );
  }
}
