import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Green "Link Local" header band used across the auth/onboarding screens.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: EdgeInsets.only(top: topPad + 20, bottom: 22),
      child: const Center(
        child: Text(
          'Link Local',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Centered "Discover meaningful Local connections" heading (Local in green).
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, this.title = 'Discover meaningful Local connections', this.highlight = 'Local', this.subtitle});
  final String title;
  final String highlight;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final parts = title.split(highlight);
    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            children: [
              TextSpan(text: parts.first),
              TextSpan(text: highlight, style: const TextStyle(color: AppColors.primary)),
              if (parts.length > 1) TextSpan(text: parts[1]),
            ],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 14),
          Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.ink)),
        ],
      ],
    );
  }
}

/// Mobile no. / Email segmented toggle matching the Figma.
class AuthSegmentedTabs extends StatelessWidget {
  const AuthSegmentedTabs({super.key, required this.value, required this.onChanged, required this.tabs});
  final int value;
  final ValueChanged<int> onChanged;
  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = i == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primarySurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: selected ? Border.all(color: AppColors.primaryTint) : null,
                ),
                child: Text(
                  tabs[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Pill input with a leading icon (matches the rounded Figma fields).
class PillField extends StatelessWidget {
  const PillField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.maxLength,
    this.inputFormatters,
  });
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      buildCounter: maxLength == null
          ? null
          : (_, {required currentLength, required isFocused, maxLength}) => null,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.textSecondary) : null,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
    );
  }
}
