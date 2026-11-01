// 穿云 - 设置 › 外观 (深浅色、主题色、配色风格、文字缩放、隐私模式). Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 外观

class MuseAppearancePage extends HookConsumerWidget {
  const MuseAppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final themeMode = ref.watch(themePreferencesProvider);
    final shownTheme = themeMode == AppThemeMode.black ? AppThemeMode.dark : themeMode;
    final scaleOn = ref.watch(MusePrefs.textScaleOn);
    final scalePct = museClampTextScalePct(ref.watch(MusePrefs.textScalePct));
    // 1.6.0 C7: the slider moves locally and is saved when released (the whole app rebuilds on save)
    final dragPct = useState<int?>(null);
    final shownPct = dragPct.value ?? scalePct;
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
            ],
          ),
          MuseSection(
            header: '主题色',
            children: [
              const MuseAccentPicker(),
              // 1.6.1 配色风格: how the colour scheme is derived from 主题色
              MuseTile(
                key: const ValueKey('appearance_color_style'),
                leading: const Icon(Icons.palette_outlined),
                title: '配色风格',
                trailing: Text(MuseColorStyle.fromKey(ref.watch(MusePrefs.colorStyle)).title),
                chevron: true,
                onTap: () async {
                  final current = MuseColorStyle.fromKey(ref.read(MusePrefs.colorStyle));
                  final picked = await musePick<MuseColorStyle>(
                    context,
                    '配色风格',
                    [for (final s in MuseColorStyle.offered) (s, s.title)],
                    current,
                  );
                  if (picked == null || picked == current) return;
                  await ref.read(MusePrefs.colorStyle.notifier).update(picked.key);
                },
              ),
            ],
          ),
          MuseSection(
            children: [
              MuseSwitchTile(
                key: const ValueKey('appearance_text_scale'),
                leading: const Icon(Icons.format_size_outlined),
                title: '文字缩放',
                info: '独立于系统字号，只改穿云里的文字大小',
                value: scaleOn,
                onChanged: (v) => ref.read(MusePrefs.textScaleOn.notifier).update(v),
              ),
              if (scaleOn)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16, vertical: MuseSpace.s4),
                  child: Row(
                    children: [
                      Text(museTextScaleLabel(museTextScaleMin), style: MuseType.caption(context)),
                      Expanded(
                        child: Slider(
                          key: const ValueKey('appearance_text_scale_slider'),
                          min: museTextScaleMin.toDouble(),
                          max: museTextScaleMax.toDouble(),
                          divisions: (museTextScaleMax - museTextScaleMin) ~/ museTextScaleStep,
                          value: shownPct.toDouble(),
                          label: museTextScaleLabel(shownPct),
                          semanticFormatterCallback: (v) => '文字缩放 ${museTextScaleLabel(v.round())}',
                          onChanged: (v) => dragPct.value = museClampTextScalePct(v.round()),
                          onChangeEnd: (v) async {
                            await ref.read(MusePrefs.textScalePct.notifier).update(museClampTextScalePct(v.round()));
                            dragPct.value = null;
                          },
                        ),
                      ),
                      Text(
                        museTextScaleLabel(shownPct),
                        key: const ValueKey('appearance_text_scale_value'),
                        style: MuseType.caption(context),
                      ),
                    ],
                  ),
                ),
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
              // 1.6.0 C10
              MuseTile(
                key: const ValueKey('appearance_preview'),
                leading: const Icon(Icons.preview_outlined),
                title: '主题预览',
                chevron: true,
                onTap: () => musePushPage(context, const MuseThemePreviewPage()),
              ),
            ],
          ),
        ],
      ),
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
