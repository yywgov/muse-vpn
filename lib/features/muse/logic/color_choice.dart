// 穿云 1.20.3 外观 › 配色：跟随系统 / 浅色 / 深色 / 纯黑 / 终端绿 / 暖纸 一组六选一，取代原来重复的
// 「深浅色 + 纯黑开关」与「主题」两行。存储沿用原来的键（theme_mode、muse_theme_style、
// muse_pure_black_follow），这里只做双向映射（纯逻辑，测试 v1203_appearance_test）。
// Part of 穿云 (GPLv3).

import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_theme.dart';

enum MuseColorChoice {
  system('system', '跟随系统'),
  light('light', '浅色'),
  dark('dark', '深色'),
  black('black', '纯黑'),
  terminal('terminal', '终端绿'),
  paper('paper', '暖纸');

  const MuseColorChoice(this.key, this.title);

  final String key;
  final String title;

  /// 自带色板（主题色不生效，外观页隐藏主题色）
  bool get ownPalette => this == terminal || this == paper;

  /// 旧设置读进来：主题优先（终端绿 / 暖纸 / 纯黑 / 浅色），主题为「默认」时看深浅色
  /// （纯黑 = 深色 + 纯黑开关）。跟随系统 + 「系统深色时纯黑」读作跟随系统，开关值原样保留、照旧生效。
  static MuseColorChoice read({required AppThemeMode mode, required MuseThemeStyle style}) => switch (style) {
    MuseThemeStyle.terminal => terminal,
    MuseThemeStyle.paper => paper,
    MuseThemeStyle.black => black,
    MuseThemeStyle.light => light,
    MuseThemeStyle.auto => switch (mode) {
      AppThemeMode.system => system,
      AppThemeMode.light => light,
      AppThemeMode.dark => dark,
      AppThemeMode.black => black,
    },
  };

  /// 选中后要写的值：主题键，和深浅色（终端绿 / 暖纸不动深浅色，null）。
  /// 浅色 / 深色 / 纯黑 / 跟随系统一律写成 主题=默认 + 对应深浅色，与 1.20.2 里同名组合的显示完全一样。
  (MuseThemeStyle style, AppThemeMode? mode) get target => switch (this) {
    system => (MuseThemeStyle.auto, AppThemeMode.system),
    light => (MuseThemeStyle.auto, AppThemeMode.light),
    dark => (MuseThemeStyle.auto, AppThemeMode.dark),
    black => (MuseThemeStyle.auto, AppThemeMode.black),
    terminal => (MuseThemeStyle.terminal, null),
    paper => (MuseThemeStyle.paper, null),
  };
}
