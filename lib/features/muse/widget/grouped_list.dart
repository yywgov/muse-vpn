// 穿云 - shared presentation widgets (1.3.0: built on muse_tokens.dart).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/features/muse/logic/latency.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

export 'package:hiddify/features/muse/widget/muse_tokens.dart';

/// Brand colours, adapted for light and dark (1.3.0: thin names over [MuseTheme] / [MusePalette]).
abstract final class MuseColors {
  static Color get brand => MusePalette.brand;
  static Color get brandLight => MusePalette.brandLight;
  static Color get brandDeep => MusePalette.brandDeep;

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
    MuseLatencyLevel.unknown => MuseTheme.of(context).text2,
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
/// 1.5.0: the footer (an explanation) is folded behind an ⓘ on the header row.
/// Rows are separated by hairline dividers inset to the label column.
class MuseSection extends HookWidget {
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
    final open = useState(false);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) {
        items.add(Divider(height: MuseSize.hairline, thickness: MuseSize.hairline, indent: dividerIndent, color: theme.hairline));
      }
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin, vertical: MuseSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null || headerTrailing != null || footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s4, 0, MuseSpace.s8),
              child: Row(
                children: [
                  Expanded(child: Text(header ?? '', style: MuseType.caption(context))),
                  ?headerTrailing,
                  // 1.5.0: the explanation stays folded behind ⓘ
                  if (footer != null) MuseInfoButton(key: const ValueKey('section_info'), open: open.value, onTap: () => open.value = !open.value),
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
            AnimatedSize(
              duration: museMotion(context),
              alignment: Alignment.topCenter,
              child: open.value
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(MuseSpace.s16, MuseSpace.s8, MuseSpace.s16, 0),
                      child: Text(footer!, key: const ValueKey('section_info_text'), style: MuseType.caption(context)),
                    )
                  : const SizedBox(width: double.infinity),
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
    this.info,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final int subtitleMaxLines;

  /// 1.5.0: an explanation, folded behind ⓘ next to the title
  final String? info;

  @override
  Widget build(BuildContext context) {
    final theme = MuseTheme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
      minLeadingWidth: MuseIconSize.small,
      horizontalTitleGap: MuseSpace.s16,
      minVerticalPadding: MuseSpace.s12,
      leading: _leadingOf(leading),
      title: info == null ? Text(title, style: MuseType.body(context)) : MuseInfoTitle(title: title, info: info!),
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
                  if (chevron) Icon(Icons.chevron_right_outlined, size: MuseIconSize.small, color: theme.text3),
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
    this.info,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 1.5.0: an explanation, folded behind ⓘ next to the title
  final String? info;

  @override
  Widget build(BuildContext context) {
    // 1.5.0: the same ListTile geometry as MuseTile, so switch rows line up with the others
    // (SwitchListTile put the title 8 px further right)
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
      minLeadingWidth: MuseIconSize.small,
      horizontalTitleGap: MuseSpace.s16,
      minVerticalPadding: MuseSpace.s12,
      leading: _leadingOf(leading),
      title: info == null ? Text(title, style: MuseType.body(context)) : MuseInfoTitle(title: title, info: info!),
      subtitle: subtitle == null ? null : Text(subtitle!, style: MuseType.caption(context)),
      trailing: Switch.adaptive(activeTrackColor: MusePalette.brand, value: value, onChanged: onChanged),
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
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
    this.info,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? info;

  @override
  Widget build(BuildContext context) {
    return MuseTile(
      title: title,
      subtitle: subtitle,
      info: info,
      onTap: onTap,
      trailing: selected
          ? Icon(Icons.check_outlined, size: MuseIconSize.small, color: MusePalette.brand)
          : const SizedBox(width: MuseIconSize.small),
    );
  }
}

/// 1.5.0: the ⓘ that unfolds an explanation (long hint texts are no longer always on screen).
class MuseInfoButton extends StatelessWidget {
  const MuseInfoButton({super.key, required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: open ? '收起说明' : '说明',
    child: InkResponse(
      onTap: onTap,
      radius: MuseIconSize.small,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s8),
        child: Icon(
          open ? Icons.info_outlined : Icons.info_outlined,
          size: MuseIconSize.tiny,
          color: open ? MusePalette.brand : MuseTheme.of(context).text2,
        ),
      ),
    ),
  );
}

/// A row title with an ⓘ; tapping it unfolds [info] under the title.
class MuseInfoTitle extends HookWidget {
  const MuseInfoTitle({super.key, required this.title, required this.info});

  final String title;
  final String info;

  @override
  Widget build(BuildContext context) {
    final open = useState(false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(child: Text(title, style: MuseType.body(context))),
            MuseInfoButton(key: const ValueKey('row_info'), open: open.value, onTap: () => open.value = !open.value),
          ],
        ),
        if (open.value)
          Padding(
            padding: const EdgeInsets.only(top: MuseSpace.s4),
            child: Text(info, key: const ValueKey('row_info_text'), style: MuseType.caption(context)),
          ),
      ],
    );
  }
}
