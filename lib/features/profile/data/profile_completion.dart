int _asInt(dynamic v) => v is int ? v : (v is num ? v.round() : int.tryParse('$v') ?? 0);

/// One step of "Complete your profile" (GET /profiles/me/completion). [key] is one of
/// photo, address, addressProof, about, education, profession, services, businessDetails,
/// menuItems, charges; [label] is the server's name for it, used for any key this build
/// doesn't know yet.
class CompletionStep {
  const CompletionStep({required this.key, required this.label, required this.done});
  final String key;
  final String label;
  final bool done;

  factory CompletionStep.fromJson(Map<String, dynamic> j) => CompletionStep(
        key: j['key'] as String? ?? '',
        label: j['label'] as String? ?? '',
        done: j['done'] as bool? ?? false,
      );
}

/// The member's profile completion: residents have 6 equal steps, providers 9. Worked out by
/// the server from their live data each time it's read (lib/profileCompletion.ts).
class ProfileCompletion {
  const ProfileCompletion({required this.percent, required this.steps, this.profileId});
  final int percent;
  final List<CompletionStep> steps;

  /// The member's own profile, for steps filled in on My Profile.
  final int? profileId;

  bool get isComplete => steps.isNotEmpty && steps.every((s) => s.done);

  /// The first step still to do, in checklist order; null when complete.
  CompletionStep? get next {
    for (final s in steps) {
      if (!s.done) return s;
    }
    return null;
  }

  factory ProfileCompletion.fromJson(Map<String, dynamic> j) => ProfileCompletion(
        percent: _asInt(j['percent']).clamp(0, 100),
        steps: ((j['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CompletionStep.fromJson)
            .toList(),
        profileId: j['profileId'] == null ? null : _asInt(j['profileId']),
      );
}
