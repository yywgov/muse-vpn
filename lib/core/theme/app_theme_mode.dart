import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';

enum AppThemeMode {
  system,
  light,
  dark,
  black;

  String present(Translations t) => switch (this) {
    system => t.pages.settings.general.themeModes.system,
    light => t.pages.settings.general.themeModes.light,
    dark => t.pages.settings.general.themeModes.dark,
    black => t.pages.settings.general.themeModes.black,
  };

  ThemeMode get flutterThemeMode => switch (this) {
    system => ThemeMode.system,
    light => ThemeMode.light,
    dark => ThemeMode.dark,
    black => ThemeMode.dark,
  };

  // 穿云 1.3.0: the dark theme is night blue (纯黑 is gone; a saved 纯黑 becomes 深色)
  bool get trueBlack => false;

  /// The choices offered in 设置.
  static const choices = [system, light, dark];
}
