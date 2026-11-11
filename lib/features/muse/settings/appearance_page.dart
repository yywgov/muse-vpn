// 穿云 - 设置 › 外观. 1.20.3 整理：首页风格（四张预览，含经典）→ 配色（六张预览，取代「深浅色 + 纯黑开关」
// 与「主题」两行，映射见 logic/color_choice.dart）→ 主题色（自带配色的终端绿 / 暖纸时隐藏）→ 动效；
// 去掉所有 ⓘ；隐私模式、敏感页禁止截屏、导入后清空剪贴板搬到 设置 › 隐私（privacy_settings_page.dart，键不变）。
// 1.11.0: 配色风格 (fixed to 忠实) and 文字缩放 (follows the system font size) are gone; 1.10.0: Android 通知与图标,
// Windows 窗口. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 外观

/// 1.20.3: 外观页（以及隐私页）列表末尾的留白：底栏高度 + 系统导航条 inset + 32。底栏外的页面（电脑、
/// 平板）只多系统 inset。页面原本已在底栏上沿结束时多出的只是一段空白，宁多勿少，最后一行永远不被压住。
EdgeInsets museSettingsPagePadding(BuildContext context) {
  final view = View.maybeOf(context);
  final system = view == null ? 0.0 : view.viewPadding.bottom / view.devicePixelRatio;
  // museScrollPadding already adds what MediaQuery still reports; only add the part the shell removed
  final inset = (system - MediaQuery.paddingOf(context).bottom).clamp(0.0, system);
  final dock = MediaQuery.sizeOf(context).width <= MuseBreak.mobile ? MuseSize.dockHeight : 0.0;
  return EdgeInsets.only(top: MuseSpace.s4, bottom: MuseSpace.s32 + dock + inset);
}

class MuseAppearancePage extends HookConsumerWidget {
  const MuseAppearancePage({super.key, this.android, this.windows, this.windowAdvancedOpen = false});

  /// 1.11.0: Windows 窗口 › 高级 unfolded (a search result inside it)
  final bool windowAdvancedOpen;

  /// Platform overrides for tests; null = the running platform.
  final bool? android;
  final bool? windows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(museColorChoiceProvider);
    return MuseScaffold(
      title: '外观',
      body: MuseGroupedBody(
        padding: museSettingsPagePadding(context),
        children: [
          // 1.20.1 首页风格; 1.20.3: + 经典（原「首页样式」一行），无说明句、无勾
          const MuseSection(header: '首页风格', children: [MuseHomeLookPicker()]),
          // 1.20.3 配色：跟随系统 / 浅色 / 深色 / 纯黑 / 终端绿 / 暖纸
          const MuseSection(header: '配色', children: [MuseColorChoicePicker()]),
          // 主题色紧跟配色；终端绿、暖纸用自带配色，主题色不生效，整块不显示
          if (!colors.ownPalette) const MuseSection(key: ValueKey('appearance_accent'), header: '主题色', children: [MuseAccentPicker()]),
          // 1.18.0 P6: 动效三档；跟随系统 = 移除动画 → 关闭，省电模式 → 精简
          const MuseSection(children: [MuseMotionTile()]),
          // 1.10.0: the platform rows that used to be groups on the 设置 home page
          if (android ?? PlatformUtils.isAndroid) const MuseAndroidAppearanceSection(),
          if (windows ?? PlatformUtils.isWindows) MuseWindowsWindowSection(advancedOpen: windowAdvancedOpen),
        ],
      ),
    );
  }
}

/// 1.18.0 P6 外观 › 动效：跟随系统 / 标准 / 精简 / 关闭。
class MuseMotionTile extends ConsumerWidget {
  const MuseMotionTile({super.key});

  static String describe(MuseMotionLevel level) => switch (level) {
    MuseMotionLevel.standard => '完整动效',
    MuseMotionLevel.reduced => '缩短动画，去掉扫光等效果',
    MuseMotionLevel.off => '不播放动画，直接显示结果',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(museMotionChoiceProvider);
    final level = museMotionLevel(context);
    final why = choice != MuseMotionChoice.auto
        ? ''
        : (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? '（系统已移除动画）'
        : level == MuseMotionLevel.reduced
        ? '（省电模式中）'
        : '';
    return MuseTile(
      key: const ValueKey('appearance_motion'),
      leading: const Icon(Icons.animation_outlined),
      title: '动效',
      subtitle: '${describe(level)}$why',
      trailing: Text(choice.title),
      chevron: true,
      onTap: () async {
        final picked = await musePick<MuseMotionChoice>(context, '动效', [for (final c in MuseMotionChoice.values) (c, c.title)], choice);
        if (picked == null || picked == choice) return;
        await ref.read(MusePrefs.motionLevel.notifier).update(picked.key);
      },
    );
  }
}

/// 1.6.0 C7 主题色: the presets, the saved custom colours (long-press to remove) and 自定义.
class MuseAccentPicker extends ConsumerWidget {
  const MuseAccentPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(MusePrefs.accent);
    final customs = museParseCustomAccents(ref.watch(MusePrefs.customAccents));
    final currentPreset = MuseAccent.presetOrNull(current);
    final currentHex = currentPreset == null ? museParseHexColor(current) : null;
    final selectedHex = currentHex == null ? null : museHexOf(currentHex);

    Future<void> addCustom() async {
      final v = await museAskText(context, '自定义主题色', initial: selectedHex ?? '', hint: '十六进制颜色，如 #2775B6');
      if (v == null) return;
      final c = museParseHexColor(v);
      if (c == null) {
        _toast(ref, '不是有效的颜色，请输入如 #2775B6 的十六进制值', error: true);
        return;
      }
      final hex = museHexOf(c);
      await ref.read(MusePrefs.customAccents.notifier).update(museAddCustomAccent(ref.read(MusePrefs.customAccents), hex));
      await ref.read(MusePrefs.accent.notifier).update(hex);
    }

    Future<void> removeCustom(String hex) async {
      await ref.read(MusePrefs.customAccents.notifier).update(museRemoveCustomAccent(ref.read(MusePrefs.customAccents), hex));
      if (selectedHex == hex) await ref.read(MusePrefs.accent.notifier).update(MuseAccent.fallback.key);
    }

    Widget swatch({required Key key, required Color color, required bool selected, required String label, VoidCallback? onLongPress, required VoidCallback onTap}) =>
        Semantics(
          button: true,
          selected: selected,
          label: '主题色 $label',
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: InkWell(
            key: key,
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              width: MuseSpace.s32,
              height: MuseSpace.s32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                // 1.6.2: a hairline keeps 月白 visible on a light page
                border: selected
                    ? Border.all(color: MuseTheme.of(context).text1, width: 2)
                    : Border.all(color: MuseTheme.of(context).hairline),
              ),
              // 1.6.2: dark tick on light colours (月白 / 藤黄 / 丁香)
              child: selected ? Icon(Icons.check_outlined, size: MuseIconSize.small, color: museOnColor(color)) : null,
            ),
          ),
          ),
        );

    // 1.20.3: full width (the group used to be narrower than the others)
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MuseSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: MuseSpace.s12,
            runSpacing: MuseSpace.s12,
            children: [
              for (final a in MuseAccent.values)
                swatch(
                  key: ValueKey('accent_${a.key}'),
                  color: a.color,
                  label: a.title,
                  selected: a == currentPreset,
                  onTap: () => ref.read(MusePrefs.accent.notifier).update(a.key),
                ),
              for (final hex in customs)
                swatch(
                  key: ValueKey('accent_custom_$hex'),
                  color: museAccentColors(hex).seed,
                  label: hex,
                  selected: hex == selectedHex,
                  onTap: () => ref.read(MusePrefs.accent.notifier).update(hex),
                  onLongPress: () => removeCustom(hex),
                ),
              Semantics(
                button: true,
                label: '自定义主题色',
                child: InkWell(
                  key: const ValueKey('accent_add_custom'),
                  customBorder: const CircleBorder(),
                  onTap: addCustom,
                  child: Container(
                    width: MuseSpace.s32,
                    height: MuseSpace.s32,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MuseTheme.of(context).hairline, width: 2)),
                    child: Icon(Icons.add_outlined, size: MuseIconSize.small, color: MuseTheme.of(context).text2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MuseSpace.s8),
          Text(
            currentPreset != null
                ? '当前：${currentPreset.title}'
                : '当前：自定义 ${selectedHex ?? ''}${customs.isNotEmpty ? '（长按自定义颜色可删除）' : ''}',
            key: const ValueKey('accent_current'),
            style: MuseType.caption(context),
          ),
        ],
      ),
    );
  }
}
