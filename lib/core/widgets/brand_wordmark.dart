import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The "LinkLocal" wordmark. Shared so the two places that show it in-page — the SP profile
/// and the conversations list — can't drift apart on weight or colour.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 20});
  final double fontSize;

  @override
  Widget build(BuildContext context) => Text(
        'LinkLocal',
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: fontSize),
      );
}
