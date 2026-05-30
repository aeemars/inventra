import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import '../extensions/theme_ext.dart';

/// Styled text field matching Figma input design
class AppTextField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool readOnly;
  final int maxLines;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final void Function(String)? onChanged;
  final void Function()? onTap;
  final String? initialValue;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final bool enabled;

  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onTap,
    this.initialValue,
    this.focusNode,
    this.textInputAction,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
        ],
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          obscureText: obscureText,
          readOnly: readOnly,
          maxLines: maxLines,
          onChanged: onChanged,
          onTap: onTap,
          initialValue: initialValue,
          focusNode: focusNode,
          textInputAction: textInputAction,
          enabled: enabled,
          style: TextStyle(
            fontSize: 14,
            color: context.appTextPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: enabled ? context.appInputFill : context.appInputFill.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
