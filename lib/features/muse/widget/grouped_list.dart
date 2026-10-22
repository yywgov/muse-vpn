// 穿云 - shared presentation widgets (1.3.0: built on muse_tokens.dart).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/features/muse/logic/latency.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

export 'package:hiddify/features/muse/widget/muse_tokens.dart';

/// Brand colours, adapted for light and dark (1.3.0: thin names over [MuseTheme] / [MusePalette]).
abstract final class MuseColors {
  static const brand = MusePalette.brand;
  static const brandLight = MusePalette.brandLight;
  static const brandDeep = MusePalette.brandDeep;

  /// Flat page colour (the top of the gradient), for app bars and system bars.
  static Color background(BuildContext context) => MuseTheme.of(context).bgTop;

  static LinearGradient pageGradient(BuildContext context) => MuseTheme.of(context).pageGradient;

  static Color card(BuildContext context) => MuseTheme.of(context).card;

  static Color selectedCard(BuildContext context) => MuseTheme.of(context).selected;

  /// Subtle filled surface inside a card (chips, inner tiles).
  static Color innerSurface(BuildContext context) => MuseTheme.of(context).inner;

  static Color secondaryText(BuildContext context) => MuseTheme.of(context).text2;

  static Color tertiaryText(BuildContext context) => MuseTheme.of(context).text3;

  static Color separator(BuildContext context) => MuseTheme.of(context).hairline;

  /// Latency colour (see museLatencyLevel): green < 300 ms, orange 300–600 ms,
  /// red > 600 ms or timeout, grey while not tested yet.
  static Color delay(BuildContext context, int delay) => switch (museLatencyLevel(delay)) {
    MuseLatencyLevel.good => MusePalette.green,
    MuseLatencyLevel.fair => MusePalette.orange,
    MuseLatencyLevel.bad => MusePalette.red,
    MuseLatencyLevel.unknown => MuseTheme.of(context).text3,
  };
}

/// A page on the cloud background behind a transparent app bar. [large] = a tab's root page:
/// left-aligned large title.
class MuseScaffold extends StatelessWidget {
  const MuseScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    required this.body,
    this.leading,
    this.large = false,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget body;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return MuseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          centerTitle: large ? false : null,
          toolbarHeight: large ? 64 : null,
          titleSpacing: large ? MuseSpace.page(context) : null,
          // 1.2.1: never guess the status bar icons from the transparent background
          systemOverlayStyle: museSystemOverlayStyle(Theme.of(context).brightness),
          leading: leading,
          title: titleWidget ??
              (title == null ? null : Text(title!, style: large ? MuseType.largeTitle(context) : null)),
          actions: actions,
        ),
        body: body,
      ),
    );
  }
}

/// The scrolling body of a grouped page.
class MuseGroupedBody extends StatelessWidget {
  const MuseGroupedBody({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: padding ?? const EdgeInsets.only(top: MuseSpace.s4, bottom: MuseSpace.s32),
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: children,
        ),
      ),
    );
  }
}

/// One rounded card with an optional small header above and footer below (iOS-like group).
/// Rows are separated by hairline dividers inset to the label column.
class MuseSection extends StatelessWidget {
  const MuseSection({
    super.key,
    this.header,
    this.headerTrailing,
    this.footer,
    required this.children,
    this.dividerIndent = 52,
  });

  final String? header;
  final Widget? headerTrailing;
  final String? footer;
  final List<Widget> children;

  /// Where the hairline starts (label column of a row with a leading icon).
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final theme = MuseTheme.of(context);
    final margin = MuseSpace.page(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) {
        items.add(Divider(height: 0.5, thickness: 0.5, indent: dividerIndent, color: theme.hairline));
      }
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin, vertical: MuseSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null || headerTrailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s4, 0, MuseSpace.s8),
              child: Row(
                children: [
                  Expanded(child: Text(header ?? '', style: MuseType.caption(context))),
                  ?headerTrailing,
                ],
              ),
            ),
          DecoratedBox(
            decoration: theme.cardDecoration(),
            child: ClipRRect(
              borderRadius: MuseRadius.cardAll,
              child: Material(
                type: MaterialType.transparency,
                child: Column(mainAxisSize: MainAxisSize.min, children: items),
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s8, MuseSpace.s16, 0),
              child: Text(footer!, style: MuseType.caption(context)),
            ),
        ],
      ),
    );
  }
}

/// Leading icon of a settings row: one size, one colour.
class MuseRowIcon extends StatelessWidget {
  const MuseRowIcon(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: MuseIconSize.small, color: color ?? MuseTheme.of(context).text2);
}

Widget? _leadingOf(Widget? leading) => leading is Icon && leading.size == null && leading.color == null && leading.icon != null
    ? MuseRowIcon(leading.icon!)
    : leading;

/// A row with a title, an optional grey line and an optional trailing widget.
class MuseTile extends StatelessWidget {
  const MuseTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.subtitleMaxLines = 3,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = MuseTheme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
      minLeadingWidth: MuseIconSize.small,
      horizontalTitleGap: MuseSpace.s16,
      minVerticalPadding: MuseSpace.s12,
      leading: _leadingOf(leading),
      title: Text(title, style: MuseType.body(context)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: subtitleMaxLines, overflow: TextOverflow.ellipsis, style: MuseType.caption(context)),
      trailing: trailing == null && !chevron
          ? null
          : DefaultTextStyle.merge(
              style: MuseType.body(context).copyWith(color: theme.text2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?trailing,
                  if (chevron) Icon(Icons.chevron_right_rounded, size: MuseIconSize.small, color: theme.text3),
                ],
              ),
            ),
      onTap: onTap,
    );
  }
}

/// A switch row.
class MuseSwitchTile extends StatelessWidget {
  const MuseSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
      secondary: _leadingOf(leading),
      title: Text(title, style: MuseType.body(context)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: MuseType.caption(context)),
      activeTrackColor: MusePalette.brand,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A radio-like row: title + optional grey line, check mark when selected.
class MuseChoiceTile extends StatelessWidget {
  const MuseChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MuseTile(
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: selected
          ? const Icon(Icons.check_rounded, size: MuseIconSize.small, color: MusePalette.brand)
          : const SizedBox(width: MuseIconSize.small),
    );
  }
}
