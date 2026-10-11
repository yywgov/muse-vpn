import 'package:hiddify/gen/translations.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'locale_preferences.g.dart';

/// 穿云: the app ships Simplified Chinese only, so the locale is fixed.
@Riverpod(keepAlive: true)
class LocalePreferences extends _$LocalePreferences {
  @override
  AppLocale build() => AppLocale.zhCn;
}
