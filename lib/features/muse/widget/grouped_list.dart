// Muse VPN - Shadowrocket-style presentation widgets.
// Part of Muse VPN, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';

/// iOS "inset grouped" colours, adapted for light and dark Material themes.
abstract final class MuseColors {
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.black : const Color(0xFFF2F2F7);

  static Color card(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C1C1E) : Colors.white;

  static Color secondaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8E8E93) : const Color(0xFF6D6D72);

  static Color separator(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);

  static Color delay(BuildContext context, int delay) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (delay <= 0) return secondaryText(context);
    if (delay < 200) return dark ? Colors.lightGreen : Colors.green.shade700;
    if (delay < 500) return dark ? Colors.orange : Colors.deepOrange;
    return dark ? Colors.redAccent : Colors.red;
  }
}

/// A grey page body for the grouped list look.
class MuseGroupedBody extends StatelessWidget {
  const MuseGroupedBody({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MuseColors.background(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: padding ?? const EdgeInsets.only(top: 8, bottom: 32), children: children),
        ),
      ),
    );
  }
}

/// One inset rounded card with an optional small header above and footer below.
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
        items.add(Divider(height: 0.5, thickness: 0.5, indent: 16, color: MuseColors.separator(context)));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null || headerTrailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      header ?? '',
                      style: theme.textTheme.labelMedium?.copyWith(color: secondary, letterSpacing: 0.3),
                    ),
                  ),
                  ?headerTrailing,
                ],
              ),
            ),
          Material(
            color: MuseColors.card(context),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: items),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(footer!, style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
            ),
        ],
      ),
    );
  }
}

/// A row with a title, a one-line grey explanation and an optional trailing widget.
class MuseTile extends StatelessWidget {
  const MuseTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.subtitleMaxLines = 2,
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
