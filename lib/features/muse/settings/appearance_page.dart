// 穿云 - 设置 › 外观 (深浅色、主题色、隐私模式; 1.11.0: 配色风格 (fixed to 忠实) and 文字缩放 (follows the
// system font size) are gone; 1.10.0: 导入后清空剪贴板, Android 通知与图标,
// Windows 窗口). Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 外观

class MuseAppearancePage extends HookConsumerWidget {
  const MuseAppearancePage({super.key, this.android, this.windows, this.windowAdvancedOpen = false});

  /// 1.11.0: Windows 窗口 › 高级 unfolded (a search result inside it)
  final bool windowAdvancedOpen;

  /// Platform overrides for tests; null = the running platform.
  final bool? android;
  final bool? windows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final themeMode = ref.watch(themePreferencesProvider);
    final shownTheme = themeMode == AppThemeMode.black ? AppThemeMode.dark : themeMode;
    return MuseScaffold(
      title: '外观',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('appearance_theme'),
                leading: const Icon(Icons.dark_mode_outlined),
                title: '深浅色',
                trailing: Text(shownTheme.present(t)),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<AppThemeMode>(
                    context,
                    '深浅色',
                    [for (final m in AppThemeMode.choices) (m, m.present(t))],
                    shownTheme,
                  );
                  if (picked == null || picked == shownTheme) return; // 深色 again keeps 纯黑
                  await ref.read(themePreferencesProvider.notifier).changeThemeMode(picked);
                },
              ),
              // 1.6.0 C7: 纯黑 only under 深色 (stored as the theme mode, so it never applies to 浅色)
              if (shownTheme == AppThemeMode.dark)
                MuseSwitchTile(
                  key: const ValueKey('appearance_pure_black'),
                  leading: const Icon(Icons.contrast_outlined),
                  title: '纯黑',
                  info: '深色背景改为纯黑，OLED 屏幕更省电',
                  value: themeMode == AppThemeMode.black,
                  onChanged: (v) => ref
                      .read(themePreferencesProvider.notifier)
                      .changeThemeMode(v ? AppThemeMode.black : AppThemeMode.dark),
                ),
              // 1.16.0 B9: 跟随系统也能选纯黑（系统切到深色时才生效，浅色不变）
              if (shownTheme == AppThemeMode.system)
                MuseSwitchTile(
                  key: const ValueKey('appearance_pure_black_follow'),
                  leading: const Icon(Icons.contrast_outlined),
                  title: '纯黑',
                  info: '系统切到深色时背景用纯黑，有机发光屏幕更省电；浅色不变',
                  value: ref.watch(MusePrefs.pureBlackFollowSystem),
                  onChanged: (v) => ref.read(MusePrefs.pureBlackFollowSystem.notifier).update(v),
                ),
              // 1.18.0 P6: 动效三档；跟随系统 = 移除动画 → 关闭，省电模式 → 精简
              const MuseMotionTile(),
              // 1.19.0: 首页样式（新首页 / 经典首页）
              const MuseHomeStyleTile(),
            ],
          ),
          MuseSection(
            header: '主题色',
            children: [
              const MuseAccentPicker(),
            ],
          ),
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('appearance_privacy'),
                leading: const Icon(Icons.blur_on_outlined),
                title: '隐私模式',
                info: '首页的流量、IP 等数字打码',
                value: ref.watch(MusePrefs.privacyMask),
                onChanged: (v) => ref.read(MusePrefs.privacyMask.notifier).update(v),
              ),
              // 1.16.0 B8: 敏感页禁截屏 (Android only: the window flag)
              if (android ?? PlatformUtils.isAndroid)
                MuseSwitchTile(
                  key: const ValueKey('appearance_secure_sensitive'),
                  leading: const Icon(Icons.screenshot_monitor_outlined),
                  title: '敏感页禁止截屏',
                  info: '节点详情、订阅详情、二维码、导出配置打开时禁止截屏和录屏，在最近任务里也只显示空白',
                  value: ref.watch(MusePrefs.secureSensitive),
                  onChanged: (v) => ref.read(MusePrefs.secureSensitive.notifier).update(v),
                ),
              // 1.10.0: from the removed 帮助与隐私 page (same preference)
              MuseSwitchTile(
                key: const ValueKey('clear_clipboard_switch'),
                leading: const Icon(Icons.content_paste_off_outlined),
                title: '导入后清空剪贴板',
                info: '从剪贴板导入订阅链接后，立即清空剪贴板（链接里带有密钥）',
                value: ref.watch(MusePrefs.clearClipboardAfterImport),
                onChanged: (v) => ref.read(MusePrefs.clearClipboardAfterImport.notifier).update(v),
              ),
              // 1.9.0 #9: 主题预览 moved to 开发者选项 (debug builds only)
            ],
          ),
          // 1.10.0: the platform rows that used to be groups on the 设置 home page
          if (android ?? PlatformUtils.isAndroid) const MuseAndroidAppearanceSection(),
          if (windows ?? PlatformUtils.isWindows) MuseWindowsWindowSection(advancedOpen: windowAdvancedOpen),
        ],
      ),
    );
  }
}

/// 1.19.0 外观 › 首页样式：新首页（路由弧线图在顶部）/ 经典首页（1.18 的首页）。
class MuseHomeStyleTile extends ConsumerWidget {
  const MuseHomeStyleTile({super.key});

  static const choices = [('new', '新首页'), ('classic', '经典首页')];

  static String titleOf(String key) => key == 'classic' ? '经典首页' : '新首页';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(MusePrefs.homeStyle) == 'classic' ? 'classic' : 'new';
    return MuseTile(
      key: const ValueKey('appearance_home_style'),
      leading: const Icon(Icons.public_outlined),
      title: '首页样式',
      subtitle: style == 'classic' ? '1.18 及以前的首页' : '顶部显示本机到出口的路由图',
      info: '新首页在顶部显示从本机到出口城市的路由图；经典首页保持原来的样子。两种首页的连接、节点、网速等功能相同',
      trailing: Text(titleOf(style)),
      chevron: true,
      onTap: () async {
        final picked = await musePick<String>(context, '首页样式', choices, style);
        if (picked == null || picked == style) return;
        await ref.read(MusePrefs.homeStyle.notifier).update(picked);
      },
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
      info: '跟随系统：系统「移除动画」时关闭，安卓省电模式时精简；也可以手动选择。所有动画只播放一次，不会常驻耗电',
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

    return Padding(
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
