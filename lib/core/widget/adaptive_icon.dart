import 'package:flutter/material.dart';

// 穿云 1.9.0 #12: Material icons (the font is already in the app and tree-shaken) instead of a
// separate icon font package whose unused second font shipped whole (~0.9 MB in the APK).
class AdaptiveIcon {
  AdaptiveIcon(BuildContext context) : platform = Theme.of(context).platform;

  final TargetPlatform platform;

  IconData get more => switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => Icons.more_horiz,
    _ => Icons.more_vert,
  };

  IconData get share => switch (platform) {
    TargetPlatform.android => Icons.share_outlined,
    TargetPlatform.iOS || TargetPlatform.macOS => Icons.ios_share,
    _ => Icons.share_outlined,
  };
}
