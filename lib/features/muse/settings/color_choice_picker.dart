// 穿云 1.20.3 外观 › 配色：六张小预览（跟随系统 / 浅色 / 深色 / 纯黑 / 终端绿 / 暖纸），和首页风格同一种卡片。
// 预览按各自配色现画（页面底、一张卡片、两行字、一个主题色按钮），跟随系统左半浅、右半深。
// 点一下即时生效，切换时沿用 1.19.0 的圆形揭开（只播一次，受动效档位控制）。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/color_choice.dart';
import 'package:hiddify/features/muse/settings/home_look_picker.dart';
import 'package:hiddify/features/muse/widget/muse_theme_reveal.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_color.dart';
import 'package:hiddify/features/muse/widget/muse_tokens_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 当前配色（由 theme_mode + muse_theme_style 读出）
final museColorChoiceProvider = Provider<MuseColorChoice>(
  (ref) => MuseColorChoice.read(mode: ref.watch(themePreferencesProvider), style: MuseThemeStyle.fromKey(ref.watch(MusePrefs.themeStyle))),
);

/// 写入一个配色（沿用原来的键）。换到别的配色时「跟随系统时纯黑」一并关掉，免得以后选回跟随系统时意外变黑。
Future<void> museApplyColorChoice(WidgetRef ref, MuseColorChoice choice) async {
  final (style, mode) = choice.target;
  await ref.read(MusePrefs.themeStyle.notifier).update(style.key);
  if (mode != null) await ref.read(themePreferencesProvider.notifier).changeThemeMode(mode);
  if (ref.read(MusePrefs.pureBlackFollowSystem)) await ref.read(MusePrefs.pureBlackFollowSystem.notifier).update(false);
}

class MuseColorChoicePicker extends ConsumerWidget {
  const MuseColorChoicePicker({super.key});

  /// 预览宽 : 高
  static const aspect = 1.25;

  /// 每张最宽
  static const maxWidth = 112.0;

  /// 一行放得下六张（每张至少这么宽）就排一行，否则三张一行
  static const minWidthForOneRow = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(museColorChoiceProvider);
    // 主题色变了预览也要跟着变
    ref.watch(MusePrefs.accent);
    return Container(
      key: const ValueKey('appearance_color_choice'),
      width: double.infinity,
      padding: const EdgeInsets.all(MuseSpace.s16),
      child: MuseChoiceRow(
        maxWidth: maxWidth,
        columns: (w) => (w - MuseSpace.s12 * 5) / 6 >= minWidthForOneRow ? 6 : 3,
        children: [
          for (final c in MuseColorChoice.values)
            MuseChoiceCard(
              tapKey: ValueKey('color_choice_${c.key}'),
              label: c.title,
              semantics: '配色 ${c.title}',
              selected: c == current,
              aspect: aspect,
              onTap: (at) {
                if (c == current) return;
                MuseThemeReveal.run(context, at, () => museApplyColorChoice(ref, c));
              },
              child: MuseColorChoicePreview(choice: c),
            ),
        ],
      ),
    );
  }
}

/// 一个配色的缩略图。
class MuseColorChoicePreview extends StatelessWidget {
  const MuseColorChoicePreview({super.key, required this.choice});

  final MuseColorChoice choice;

  static ColorScheme schemeOf(MuseColorChoice c, Brightness b) {
    final own = museThemeOwnScheme(switch (c) {
      MuseColorChoice.terminal => MuseThemeStyle.terminal,
      MuseColorChoice.paper => MuseThemeStyle.paper,
      _ => MuseThemeStyle.auto,
    });
    if (own != null) return own;
    return museSeededScheme(
      seed: MusePalette.seed,
      brightness: b,
      style: MuseColorStyle.fromKey(MusePalette.colorStyle),
      pureBlack: c == MuseColorChoice.black,
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = schemeOf(choice, switch (choice) {
      MuseColorChoice.dark || MuseColorChoice.black => Brightness.dark,
      _ => Brightness.light,
    });
    final second = choice == MuseColorChoice.system ? schemeOf(choice, Brightness.dark) : null;
    return CustomPaint(painter: MuseColorChoicePainter(first, second));
  }
}

/// 画法：页面底 + 一张卡片（状态点、两行字、一个主题色按钮）。[right] 不为 null 时右半边用它画（跟随系统）。
class MuseColorChoicePainter extends CustomPainter {
  MuseColorChoicePainter(this.left, this.right);

  final ColorScheme left;
  final ColorScheme? right;

  @override
  void paint(Canvas canvas, Size size) {
    if (right == null) {
      _draw(canvas, size, left);
      return;
    }
    final half = size.width / 2;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, half, size.height));
    _draw(canvas, size, left);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(half, 0, size.width - half, size.height));
    _draw(canvas, size, right!);
    canvas.restore();
  }

  void _draw(Canvas canvas, Size size, ColorScheme s) {
    final mt = (
      page: MuseSurface.page.color(s),
      card: MuseSurface.card.color(s),
      block: MuseSurface.block.color(s),
      text1: s.onSurface,
      text2: s.onSurfaceVariant,
      line: s.outlineVariant,
    );
    final u = size.width / 100; // 100 个单位宽
    canvas.drawRect(Offset.zero & size, Paint()..color = mt.page);
    RRect rr(double x, double y, double w, double h, double r) => RRect.fromRectAndRadius(Rect.fromLTWH(x * u, y * u, w * u, h * u), Radius.circular(r * u));
    // 卡片
    canvas.drawRRect(rr(10, 12, 80, 56, 8), Paint()..color = mt.card);
    if (s.brightness == Brightness.light && mt.card.computeLuminance() - mt.page.computeLuminance() < 0.02) {
      canvas.drawRRect(
        rr(10, 12, 80, 56, 8),
        Paint()
          ..color = mt.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    // 状态点 + 标题 + 次要字
    canvas.drawCircle(Offset(20 * u, 25 * u), 3 * u, Paint()..color = s.primary);
    canvas.drawRRect(rr(27, 22, 36, 6, 3), Paint()..color = mt.text1.withValues(alpha: 0.85));
    canvas.drawRRect(rr(18, 35, 28, 5, 2.5), Paint()..color = mt.text2.withValues(alpha: 0.6));
    // 内嵌块 + 主题色按钮
    canvas.drawRRect(rr(18, 48, 30, 12, 4), Paint()..color = mt.block);
    canvas.drawRRect(rr(56, 47, 26, 14, 7), Paint()..color = s.primary);
  }

  @override
  bool shouldRepaint(MuseColorChoicePainter old) => old.left != left || old.right != right;
}
