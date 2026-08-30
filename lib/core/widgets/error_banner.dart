import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Distinguishes "this failed" from "this worked, but check it" — a coarse GPS
/// fix is worth flagging without dressing it up as an error.
enum BannerTone { error, warning }

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.tone = BannerTone.error});
  final String message;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final isWarning = tone == BannerTone.warning;
    final color = isWarning ? AppColors.warning : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(isWarning ? Icons.warning_amber_rounded : Icons.error_outline, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
