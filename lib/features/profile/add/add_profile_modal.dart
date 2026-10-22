import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/muse/home/clipboard_import.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hiddify/features/profile/add/widgets/widgets.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AddProfileModal extends HookConsumerWidget {
  const AddProfileModal({super.key, this.url});
  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(addProfileNotifierProvider).isLoading;
    final currentWidget = ref.watch(addProfilePageNotifierProvider);
    ref.listen(addProfileNotifierProvider, (previous, next) {
      if (next case AsyncData(value: final _?)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && context.canPop()) context.pop();
        });
      }
    });

    useMemoized(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (url != null && context.mounted) {
        if (isLoading) return;
        ref.read(addProfileNotifierProvider.notifier).addClipboard(url!);
      }
    });
    return SafeArea(
      child: isLoading
          ? const ProfileLoading()
          : switch (currentWidget) {
              AddProfilePages.options => const AddProfileOptions(),
              AddProfilePages.manual => const AddProfileManual(),
            },
    );
  }
}

/// 穿云 1.3.0: the one 「添加」 sheet — a detected clipboard link first, then 粘贴链接 / 扫描二维码 /
/// 从文件导入 / 手动输入.
class AddProfileOptions extends HookConsumerWidget {
  const AddProfileOptions({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mt = MuseTheme.of(context);
    Widget option(Key key, IconData icon, String title, VoidCallback onTap) => ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
      minLeadingWidth: MuseIconSize.regular,
      horizontalTitleGap: MuseSpace.s16,
      leading: Icon(icon, size: MuseIconSize.regular, color: mt.text2),
      title: Text(title, style: MuseType.body(context)),
      trailing: Icon(Icons.chevron_right_rounded, size: MuseIconSize.small, color: mt.text3),
      onTap: onTap,
    );
    final options = <Widget>[
      option(const ValueKey('add_from_clipboard_button'), Icons.content_paste_rounded, '粘贴链接', () async {
        final cr = await Clipboard.getData(Clipboard.kTextPlain).then((value) => value?.text ?? '');
        ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
      }),
      if (!PlatformUtils.isDesktop)
        option(const ValueKey('add_by_qr_code_button'), Icons.qr_code_scanner_rounded, '扫描二维码', () async {
          final cr = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
          if (cr == null) return;
          ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
        }),
      option(const ValueKey('add_from_file_button'), Icons.insert_drive_file_rounded, '从文件导入', () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['txt', 'json', 'yaml', 'yml', 'conf', 'ovpn'],
        );
        if (result == null) return;
        final picked = result.files.single;
        var bytes = picked.bytes;
        if (bytes == null) {
          final path = picked.path;
          if (path == null) return;
          final file = File(path);
          if (!await file.exists()) return;
          bytes = await file.readAsBytes();
        }
        ref.read(addProfileNotifierProvider.notifier).addClipboard(decodeTextBytes(bytes));
      }),
      option(const ValueKey('add_manually_button'), Icons.edit_rounded, '手动输入链接', () {
        ref.read(addProfilePageNotifierProvider.notifier).goManual();
      }),
    ];
    final items = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      items.add(options[i]);
      if (i != options.length - 1) items.add(Divider(height: 0.5, thickness: 0.5, indent: 56, color: mt.hairline));
    }
    return Column(
      key: const ValueKey('add_profile_options'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MuseSpace.s24, MuseSpace.s24, MuseSpace.s24, MuseSpace.s16),
          child: Text('添加订阅', style: MuseType.title(context)),
        ),
        const MuseClipboardOfferTile(),
        Padding(
          padding: const EdgeInsets.fromLTRB(MuseSpace.s16, 0, MuseSpace.s16, MuseSpace.s24),
          child: Material(
            color: mt.inner,
            shape: const RoundedRectangleBorder(borderRadius: MuseRadius.cardAll),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: items),
          ),
        ),
      ],
    );
  }
}

class AddProfileManual extends HookConsumerWidget {
  const AddProfileManual({super.key});

  String _genSliderText(Translations t, int sliderValue) {
    if (sliderValue == 0) {
      return t.common.auto;
    } else if (sliderValue < 24) {
      return t.common.interval.hour(n: sliderValue);
    }
    final day = t.common.interval.day(n: sliderValue ~/ 24);
    final hour = t.common.interval.hour(n: sliderValue % 24);
    return '$day $hour';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final nameTextController = useTextEditingController();
    final urlTextController = useTextEditingController();
    final isAutoUpdateDisable = useState<bool>(false);
    final updateInterval = useState(.0);
    final sliderFocusNode = useFocusNode(
      onKeyEvent: (node, event) {
        if (KeyboardConst.verticalArrows.contains(event.logicalKey) && event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            node.previousFocus();
          } else {
            node.nextFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 12),
            child: Row(
              children: [
                Expanded(child: Text(t.common.manually, style: theme.textTheme.headlineMedium)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(addProfilePageNotifierProvider.notifier).goOptions(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CustomTextFormField(
              maxLines: 1,
              controller: nameTextController,
              validator: (value) => (value?.isEmpty ?? true) ? t.pages.profileDetails.form.emptyName : null,
              label: t.common.name,
              hint: t.pages.profileDetails.form.nameHint,
            ),
          ),
          const Gap(16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CustomTextFormField(
              maxLines: 1,
              controller: urlTextController,
              validator: (value) => (value != null && !isUrl(value)) ? t.pages.profileDetails.form.invalidUrl : null,
              label: t.common.url,
              hint: t.pages.profileDetails.form.urlHint,
            ),
          ),
          const Gap(12),
          SwitchListTile.adaptive(
            title: Text(
              t.pages.profileDetails.form.disableAutoUpdate,
              style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
            ),
            value: isAutoUpdateDisable.value,
            onChanged: (value) => isAutoUpdateDisable.value = value,
          ),
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: !isAutoUpdateDisable.value
                ? Column(
                    children: [
                      const Divider(indent: 16, endIndent: 16),
                      const Gap(12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.pages.profileDetails.form.autoUpdateInterval,
                                style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
                              ),
                            ),
                            Text(
                              _genSliderText(t, updateInterval.value.round()),
                              style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Gap(4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Slider(
                          focusNode: sliderFocusNode,
                          value: updateInterval.value,
                          max: 96,
                          divisions: 96,
                          label: updateInterval.value.round().toString(),
                          onChanged: (double value) => updateInterval.value = value,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    child: Text(t.common.add),
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        final i = updateInterval.value.toInt();
                        final interval = i > 0 ? i : null;
                        await ref
                            .read(addProfileNotifierProvider.notifier)
                            .addManual(
                              url: urlTextController.text.trim(),
                              userOverride: UserOverride(
                                name: nameTextController.text.trim(),
                                isAutoUpdateDisable: isAutoUpdateDisable.value,
                                updateInterval: interval,
                              ),
                            );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          // const Gap(16),
        ],
      ),
    );
  }
}
