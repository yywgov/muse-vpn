import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingDivider extends ConsumerWidget {
  const SettingDivider({super.key, this.title});

  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (title == null) return const Divider(indent: MuseSpace.s16, endIndent: MuseSpace.s16, height: 1);
    return Row(
      children: [
        const Expanded(child: Divider(indent: MuseSpace.s16, endIndent: MuseSpace.s8, height: 1)),
        const Icon(size: MuseIconSize.tiny, Icons.warning_outlined, color: MusePalette.orange),
        const Gap(2),
        Text(title!, style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface)),
        const Expanded(child: Divider(indent: MuseSpace.s8, endIndent: MuseSpace.s16, height: 1)),
      ],
    );
  }
}
