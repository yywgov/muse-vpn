import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Full-height message for a sliver list that failed to load (icon + text, centred).
class SliverErrorBodyPlaceholder extends HookConsumerWidget {
  const SliverErrorBodyPlaceholder(this.msg, {super.key, this.icon = Icons.error_outline});

  final String msg;
  final IconData? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon), const Gap(16)],
          Text(msg),
        ],
      ),
    );
  }
}
