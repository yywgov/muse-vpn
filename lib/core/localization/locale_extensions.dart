import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/gen/translations.g.dart';

extension AppLocaleX on AppLocale {
  String get preferredFontFamily => kIsWeb || !Platform.isWindows ? "" : FontFamily.emoji;

  String get localeName => "简体中文";
}
