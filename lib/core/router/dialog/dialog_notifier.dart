import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hiddify/core/router/dialog/widgets/action_at_closing_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/confirmation_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/custom_alert_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_checkbox_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_input_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_picker_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_radio_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_text_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/window_closing_dialog.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/common/qr_code_scanner_screen.dart';
import 'package:protobuf/protobuf.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dialog_notifier.g.dart';

@Riverpod(keepAlive: true)
class DialogNotifier extends _$DialogNotifier {
  @override
  void build() {}

  Future<T?> _show<T>(Widget child) async {
    final context = rootNavKey.currentContext;
    if (context == null) return null;
    // ref.read(popupCountNotifierProvider.notifier).increase();
    return await Navigator.of(context).push<T>(DialogRoute(context: context, builder: (context) => child)).then((
      value,
    ) {
      // ref.read(popupCountNotifierProvider.notifier).decrease();
      return value;
    });
  }

  Future<String?> showQrScanner() async {
    return await _show<String?>(const QrCodeScannerDialog());
  }

  Future<bool> showConfirmation({
    required String title,
    required String message,
    IconData? icon,
    String? positiveBtnTxt,
  }) async {
    return await _show<bool>(
          ConfirmationDialog(title: title, message: message, icon: icon, positiveBtnTxt: positiveBtnTxt),
        ) ??
        false;
  }

  Future<ActionsAtClosing?> showActionAtClosing({required ActionsAtClosing selected}) async {
    return await _show<ActionsAtClosing?>(ActionsAtClosingDialog(selected: selected));
  }

  Future<String?> showSettingText({
    required String lable,
    String value = '',
    String? defaultValue,
    FormFieldValidator<String>? validator,
  }) async {
    return await _show<String?>(
      SettingTextDialog(lable: lable, value: value, defaultValue: defaultValue, validator: validator),
    );
  }

  Future<List<ProtobufEnum>?> showSettingCheckbox({
    required String title,
    required List<ProtobufEnum> values,
    required List<ProtobufEnum> selectedValues,
    List<ProtobufEnum>? defaultValue,
    Map<String, String>? t,
  }) async {
    return await _show<List<ProtobufEnum>?>(
      SettingCheckboxDialog(
        title: title,
        values: values,
        selectedValues: selectedValues,
        defaultValue: defaultValue,
        t: t,
      ),
    );
  }

  Future<T?> showSettingRadio<T>({
    required String title,
    required List<T> values,
    required T value,
    T? defaultValue,
    Map<String, String>? t,
  }) async {
    return await _show<T?>(
      SettingRadioDialog(title: title, values: values, value: value, defaultValue: defaultValue, t: t),
    );
  }

  Future<T?> showSettingInput<T>({
    required String title,
    required T initialValue,
    T? Function(String value)? mapTo,
    bool Function(String value)? validator,
    String Function(T value)? valueFormatter,
    List<T>? possibleValues,
    VoidCallback? onReset,
    (String text, VoidCallback)? optionalAction,
    IconData? icon,
    bool digitsOnly = false,
  }) async {
    return await _show<T?>(
      SettingInputDialog(
        title: title,
        initialValue: initialValue,
        mapTo: mapTo,
        validator: validator,
        valueFormatter: valueFormatter,
        possibleValues: possibleValues,
        onReset: onReset,
        optionalAction: optionalAction,
        icon: icon,
        digitsOnly: digitsOnly,
      ),
    );
  }

  Future<T?> showSettingPicker<T>({
    required String title,
    required T selected,
    required List<T> options,
    required String Function(T e) getTitle,
    VoidCallback? onReset,
  }) async {
    return await _show<T?>(
      SettingPickerDialog(
        title: title,
        selected: selected,
        options: options,
        getTitle: getTitle,
        onReset: onReset,
      ),
    );
  }

  Future<void> showWindowClosing() async {
    return await _show<void>(const WindowClosingDialog());
  }

  Future<void> showCustomAlertFromErr(({String type, String? message}) err) async {
    return await _show<void>(CustomAlertDialog.fromErr(err));
  }
}
