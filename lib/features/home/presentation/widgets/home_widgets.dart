import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';

String _abs(String url) => url.startsWith('http') ? url : '${AppConfig.apiBaseUrl.replaceAll('/api/v1', '')}$url';

/// Circular avatar that falls back to initials.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.photoUrl, required this.name, this.radius = 22});
  final String? photoUrl;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0]).join().toUpperCase();
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primarySurface,
        backgroundImage: CachedNetworkImageProvider(_abs(photoUrl!)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primarySurface,
      child: Text(initials,
          style: TextStyle(
              color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: radius * 0.7)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.highlight, this.onMore});
  final String title;
  final String? highlight;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
                children: [
                  TextSpan(text: '$title '),
                  if (highlight != null)
                    TextSpan(text: highlight, style: const TextStyle(color: AppColors.primary)),
                ],
              ),
            ),
          ),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              child: const Text('Explore More...',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
