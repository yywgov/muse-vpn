// 穿云 - shared presentation widgets (style B: navy gradient, large rounded cards).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';

/// Brand colours, adapted for light and dark.
abstract final class MuseColors {
  static const brand = Color(0xFF2F6BFF);
  static const brandLight = Color(0xFF3B8BFF);
  static const brandDeep = Color(0xFF1A4FD6);

  static bool _dark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  /// True-black (纯黑 / OLED) mode: the theme paints a pure black scaffold.
  static bool isTrueBlack(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark && theme.scaffoldBackgroundColor == Colors.black;
  }

  /// Flat page colour (the top of the gradient), for app bars and system bars.
  static Color background(BuildContext context) => isTrueBlack(context)
      ? Colors.black
      : _dark(context)
          ? const Color(0xFF0E1A3A)
          : const Color(0xFFF3F6FB);

  static LinearGradient pageGradient(BuildContext context) => isTrueBlack(context)
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.black],
        )
      : _dark(context)
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1A3A), Color(0xFF0A1024)],
        )
      : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF3F6FB), Color(0xFFEAF0FA)],
        );

  static Color card(BuildContext context) => isTrueBlack(context)
      ? const Color(0xFF151515)
      : _dark(context)
          ? const Color(0xFF16213F)
          : Colors.white;

  static Color selectedCard(BuildContext context) => isTrueBlack(context)
      ? const Color(0xFF1A2238)
      : _dark(context)
          ? const Color(0xFF1B2E63)
          : const Color(0xFFEAF1FF);

  /// Subtle filled surface inside a card (chips, inner tiles).
  static Color innerSurface(BuildContext context) => isTrueBlack(context)
      ? const Color(0xFF1F1F1F)
      : _dark(context)
          ? const Color(0xFF1E2A4D)
          : const Color(0xFFEEF2F8);

  static Color secondaryText(BuildContext context) =>
      _dark(context) ? const Color(0xFF8A94B3) : const Color(0xFF6B7280);

  static Color separator(BuildContext context) =>
      _dark(context) ? const Color(0x14FFFFFF) : const Color(0xFFE5E7EB);

  /// Latency colour: green under 100 ms, yellow under 200 ms, red above (grey when unknown).
  static Color delay(BuildContext context, int delay) {
    if (delay <= 0) return secondaryText(context);
    if (delay < 100) return const Color(0xFF22C55E);
    if (delay < 200) return const Color(0xFFEAB308);
    return const Color(0xFFEF4444);
  }
}

/// A page with the brand gradient behind a transparent app bar.
class MuseScaffold extends StatelessWidget {
  const MuseScaffold({super.key, this.title, this.titleWidget, this.actions, required this.body, this.leading});

  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: MuseColors.pageGradient(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          leading: leading,
          title: titleWidget ?? (title == null ? null : Text(title!)),
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
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: padding ?? const EdgeInsets.only(top: 4, bottom: 32),
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: children,
        ),
      ),
    );
  }
}

/// One rounded card with an optional small header above and footer below.
class MuseSection extends StatelessWidget {
  const MuseSection({super.key, this.header, this.headerTrailing, this.footer, required this.children});

  final String? header;
  final Widget? headerTrailing;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = MuseColors.secondaryText(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) {
        items.add(Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: MuseColors.separator(context)));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null || headerTrailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 0, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      header ?? '',
                      style: theme.textTheme.labelLarge?.copyWith(color: secondary, letterSpacing: 0.3),
                    ),
                  ),
                  ?headerTrailing,
                ],
              ),
            ),
          Material(
            color: MuseColors.card(context),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: items),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Text(footer!, style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
            ),
        ],
      ),
    );
  }
}

/// A row with a title, a grey explanation and an optional trailing widget.
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
    final theme = Theme.of(context);
    return ListTile(
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: subtitleMaxLines,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: MuseColors.secondaryText(context)),
            ),
      trailing:
          trailing ?? (chevron ? Icon(Icons.chevron_right_rounded, color: MuseColors.secondaryText(context)) : null),
      onTap: onTap,
    );
  }
}

/// A switch row with a grey explanation.
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
    final theme = Theme.of(context);
    return SwitchListTile.adaptive(
      secondary: leading,
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: MuseColors.secondaryText(context))),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A radio-like row: title + grey explanation, check mark when selected.
class MuseChoiceTile extends StatelessWidget {
  const MuseChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MuseTile(
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: selected
          ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary)
          : const SizedBox(width: 24),
    );
  }
}
