import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Who a post, group or event is for (BUG-115: the Figma's "Post in" / "Members from").
/// Relative to the member's own address; the server keeps each one to the people in it.
class AudienceOption {
  const AudienceOption(this.value, this.title, this.place);

  /// society | lane | area | city, as the API takes it.
  final String value;

  /// "My Society", "My Lane"…
  final String title;

  /// The member's own building, lane, area or city by name.
  final String place;
}

/// The default, as the Figma's "Post in: South Delhi" shows: the member's area.
const defaultAudience = 'area';

/// The audiences a member's address allows, narrowest first. "My Society" needs a building
/// name and "My Lane" a lane, so a missing one drops that option (the server refuses it too).
List<AudienceOption> audienceOptions({String? building, String? lane, String? area, String? city}) => [
      if (building != null) AudienceOption('society', 'My Society', building),
      if (lane != null) AudienceOption('lane', 'My Lane', lane),
      AudienceOption('area', 'My Area', area ?? 'Your area'),
      AudienceOption('city', 'My City', city ?? 'Your city'),
    ];

/// "Post in: South Delhi ▾". Tapping it lists the options.
class AudiencePicker extends StatelessWidget {
  const AudiencePicker({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  /// "Post in" or "Members from".
  final String label;
  final String value;
  final List<AudienceOption> options;
  final ValueChanged<String> onChanged;

  AudienceOption get _current =>
      options.firstWhere((o) => o.value == value, orElse: () => options.firstWhere((o) => o.value == 'city'));

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Only people here will see it in their feeds and lists.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(o.place, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: o.value == _current.value ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.of(sheet).pop(o.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('audience-picker'),
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.ink)),
            Flexible(
              child: Text(_current.place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.primary)),
            ),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}
