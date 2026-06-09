import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// "Link Local" wordmark with a location-pin glyph.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.location_on_rounded, color: Colors.white, size: size * 0.7),
        ),
        const SizedBox(width: 8),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            children: [
              TextSpan(text: 'Link', style: TextStyle(color: c)),
              const TextSpan(text: 'Local', style: TextStyle(color: AppColors.ink)),
            ],
          ),
        ),
      ],
    );
  }
}
