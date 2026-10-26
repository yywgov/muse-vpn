// 穿云 1.6.0 C1 - flat cards, selection badges, switches and section groups on the surface
// levels (structure by fill, colour only for state; list cards never cast a shadow).
// Design rules adapted from GPL-3.0 code, Copyright (C) chen08209 (see THIRD_PARTY_NOTICES.md).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_shape.dart';

/// A flat card one surface level above the one it sits on. Selected cards keep their fill and
/// show a [MuseSelectionBadge] instead of a coloured background.
class MuseCard extends StatelessWidget {
  const MuseCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(MuseSpace.s16),
    this.radius = MuseRadius.card,
    this.level,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// the level this card is drawn at (default: the one above its parent's)
  final MuseSurface? level;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lvl = level ?? MuseSurfaceScope.of(context).above;
    final shape = MuseShape.of(radius, side: selected ? BorderSide(color: scheme.primary, width: MuseSize.spinnerStroke) : BorderSide.none);
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null || onLongPress != null) {
      body = InkWell(customBorder: shape, onTap: onTap, onLongPress: onLongPress, child: body);
    }
    return MuseSurfaceScope(
      level: lvl,
      child: Material(color: lvl.color(scheme), shape: shape, clipBehavior: Clip.antiAlias, child: body),
    );
  }
}

/// The selected mark: a primary check (selected) or a pin (preferred, used from 1.7.0).
enum MuseBadgeKind { check, preferred }

class MuseSelectionBadge extends StatelessWidget {
  const MuseSelectionBadge({super.key, this.kind = MuseBadgeKind.check, this.size = MuseSize.badge});

  final MuseBadgeKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('muse_badge_${kind.name}'),
      width: size,
      height: size,
      decoration: ShapeDecoration(color: scheme.primary, shape: const CircleBorder()),
      alignment: Alignment.center,
      child: Icon(
        kind == MuseBadgeKind.check ? Icons.check_outlined : Icons.push_pin_outlined,
        size: size * 0.7,
        color: scheme.onPrimary,
      ),
    );
  }
}

/// A list section: optional header, then rows on one card with hairline dividers.
class MuseSectionGroup extends StatelessWidget {
  const MuseSectionGroup({super.key, this.title, this.summary, required this.children});

  final String? title;

  /// one-line state summary under the title
  final String? summary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s24, MuseSpace.s16, MuseSpace.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title!, style: MuseTextLevel.footnote.style(context, color: scheme.onSurfaceVariant, weight: FontWeight.w600)),
                if (summary != null) Text(summary!, style: MuseTextLevel.caption1.style(context, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        MuseCard(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: MuseSize.hairline, thickness: MuseSize.hairline, indent: MuseSpace.s16, color: scheme.outlineVariant),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A row with a switch; the whole row toggles.
class MuseSwitchRow extends StatelessWidget {
  const MuseSwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.leading});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: MuseSize.rowMin),
    child: SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      secondary: leading,
      value: value,
      onChanged: onChanged,
    ),
  );
}
