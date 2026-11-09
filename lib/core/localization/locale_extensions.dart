import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart' show MuseFont;
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/gen/translations.g.dart';

extension AppLocaleX on AppLocale {
  /// 1.19.2: the bundled Chinese face (思源黑体 subset, MuseHei) on every platform — Android and
  /// Windows read the same; Windows keeps the bundled Emoji face as the fallback for flags (it was
  /// the primary family before, Chinese falling back to the system font).
  String get preferredFontFamily => MuseFont.cjk;

  List<String>? get preferredFontFallback => kIsWeb || !Platform.isWindows ? null : const [FontFamily.emoji];

  String get localeName => "简体中文";
}
