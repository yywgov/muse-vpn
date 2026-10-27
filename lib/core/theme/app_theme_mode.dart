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

  // 穿云 1.3.0: the dark theme is night blue; 1.6.0 C7: 纯黑 is back as a switch under 深色
  // (stored as this value; 深浅色 shows it as 深色)
  bool get trueBlack => this == black;

  /// The choices offered in 设置.
  static const choices = [system, light, dark];
}
