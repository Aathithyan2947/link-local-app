import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// True when a profile failed to load because its owner's Profile visibility doesn't include
/// this viewer (the server answers 403).
bool isPrivateProfileError(Object error) => error is DioException && error.response?.statusCode == 403;

/// Shown instead of a profile its owner has hidden from this viewer. No Retry: it won't change
/// until they change their setting. Keeps a back button, since the page has no app bar.
class PrivateProfileView extends StatelessWidget {
  const PrivateProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left, size: 28, color: AppColors.ink),
          ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 52, color: AppColors.textMuted),
                    SizedBox(height: 14),
                    Text('This profile is private',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
                    SizedBox(height: 6),
                    Text(
                      "Its owner has limited who can see it, so it isn't visible to you.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
