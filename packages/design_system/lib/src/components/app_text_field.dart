import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppTextFieldVariant { standard, borderless, code }

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.variant = AppTextFieldVariant.standard,
    this.dense = false,
    this.hint,
    this.helperText,
    this.errorText,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffix,
    this.inputFormatters,
    this.autofillHints,
    this.enableSuggestions = true,
    this.autocorrect = true,
  });

  final String? label;
  final AppTextFieldVariant variant;
  final bool dense;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool enableSuggestions;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: variant == AppTextFieldVariant.code
        ? const TextStyle(fontFamily: 'monospace')
        : null,
    focusNode: focusNode,
    enabled: enabled,
    readOnly: readOnly,
    obscureText: obscureText,
    autofocus: autofocus,
    minLines: minLines,
    maxLines: maxLines,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    onChanged: onChanged,
    inputFormatters: inputFormatters,
    autofillHints: autofillHints,
    enableSuggestions: obscureText ? false : enableSuggestions,
    autocorrect: obscureText ? false : autocorrect,
    decoration: _decoration(
      label: label,
      variant: variant,
      dense: dense,
      hint: hint,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: prefixIcon,
      suffix: suffix,
    ),
    onSubmitted: onSubmitted,
  );
}

class AppTextFormField extends StatelessWidget {
  const AppTextFormField({
    super.key,
    this.label,
    this.variant = AppTextFieldVariant.standard,
    this.dense = false,
    this.hint,
    this.helperText,
    this.errorText,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffix,
    this.inputFormatters,
    this.autofillHints,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.initialValue,
    this.validator,
    this.onSaved,
    this.autovalidateMode,
  }) : assert(controller == null || initialValue == null);

  final String? label;
  final AppTextFieldVariant variant;
  final bool dense;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool enableSuggestions;
  final bool autocorrect;
  final String? initialValue;
  final FormFieldValidator<String>? validator;
  final FormFieldSetter<String>? onSaved;
  final AutovalidateMode? autovalidateMode;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    style: variant == AppTextFieldVariant.code
        ? const TextStyle(fontFamily: 'monospace')
        : null,
    focusNode: focusNode,
    enabled: enabled,
    readOnly: readOnly,
    obscureText: obscureText,
    autofocus: autofocus,
    minLines: minLines,
    maxLines: maxLines,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    onChanged: onChanged,
    inputFormatters: inputFormatters,
    autofillHints: autofillHints,
    enableSuggestions: obscureText ? false : enableSuggestions,
    autocorrect: obscureText ? false : autocorrect,
    decoration: _decoration(
      label: label,
      variant: variant,
      dense: dense,
      hint: hint,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: prefixIcon,
      suffix: suffix,
    ),
    onFieldSubmitted: onSubmitted,
    initialValue: initialValue,
    validator: validator,
    onSaved: onSaved,
    autovalidateMode: autovalidateMode,
  );
}

InputDecoration _decoration({
  required String? label,
  required AppTextFieldVariant variant,
  required bool dense,
  required String? hint,
  required String? helperText,
  required String? errorText,
  required IconData? prefixIcon,
  required Widget? suffix,
}) => InputDecoration(
  labelText: label,
  isDense: dense,
  filled: variant == AppTextFieldVariant.borderless ? false : null,
  border: variant == AppTextFieldVariant.borderless ? InputBorder.none : null,
  enabledBorder: variant == AppTextFieldVariant.borderless
      ? InputBorder.none
      : null,
  focusedBorder: variant == AppTextFieldVariant.borderless
      ? InputBorder.none
      : null,
  hintText: hint,
  helperText: helperText,
  errorText: errorText,
  prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
  suffixIcon: suffix,
);
