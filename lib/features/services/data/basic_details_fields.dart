import '../../auth/data/auth_models.dart';
import '../../profile/data/profile_models.dart';

/// Field-name patterns for the well-known `basic_details` fields.
///
/// Admin-configured fields carry no stable key — only a display name — so both the SP
/// profile view (which suppresses/absorbs the well-known ones) and the onboarding form
/// (which prefills them from the account) have to recognise them by name. Keeping the
/// patterns here means those two sides can't drift apart.
final kBasicNamePattern = RegExp('name', caseSensitive: false);
final kBasicPhonePattern = RegExp('phone|mobile', caseSensitive: false);
final kBasicEmailPattern = RegExp('email', caseSensitive: false);
final kBasicAboutPattern = RegExp('about', caseSensitive: false);
final kBasicEducationPattern = RegExp('^education', caseSensitive: false);
final kBasicProfessionPattern = RegExp('^profession', caseSensitive: false);
final kBasicExperiencePattern = RegExp('experience', caseSensitive: false);

/// The value to seed a `basic_details` field with when the SP hasn't answered it yet.
///
/// Everything here is data the SP already gave us at registration or on their profile,
/// so re-typing it is pure friction. Returns null when there's nothing to offer — a
/// mobile-registered SP has no email, for instance.
///
/// Order matters: the patterns are deliberately loose (an admin can name a field
/// anything), so the more specific ones are tested first.
String? prefillForBasicDetailsField(
  String fieldName, {
  AppUser? user,
  ProfileDetail? profile,
}) {
  String? clean(String? v) => (v != null && v.trim().isNotEmpty) ? v.trim() : null;

  if (kBasicPhonePattern.hasMatch(fieldName)) return clean(user?.mobile);
  if (kBasicEmailPattern.hasMatch(fieldName)) return clean(user?.email);
  if (kBasicNamePattern.hasMatch(fieldName)) return clean(user?.name) ?? clean(profile?.name);
  if (kBasicAboutPattern.hasMatch(fieldName)) return clean(profile?.aboutMe);
  if (kBasicEducationPattern.hasMatch(fieldName)) {
    final educations = profile?.educations ?? const [];
    return educations.isEmpty ? null : clean(educations.first.label);
  }
  if (kBasicProfessionPattern.hasMatch(fieldName)) {
    final professions = profile?.professions ?? const [];
    return professions.isEmpty ? null : clean(professions.first.label);
  }
  if (kBasicExperiencePattern.hasMatch(fieldName)) return profile?.yearsOfExperience?.toString();
  return null;
}

/// The profile columns implied by a saved `basic_details` answer set.
///
/// "Service Phone No." / "Service Email" are collected during onboarding but the profile shows
/// `servicePhone` / `serviceEmail`, so a save here writes through to those columns — one value,
/// two entry points, no divergence. Never touches the sign-in credentials.
Map<String, dynamic> serviceContactUpdates(Map<String, String> answersByFieldName) {
  final out = <String, dynamic>{};
  for (final entry in answersByFieldName.entries) {
    final value = entry.value.trim();
    if (value.isEmpty) continue;
    if (kBasicPhonePattern.hasMatch(entry.key)) {
      out['servicePhone'] ??= value;
    } else if (kBasicEmailPattern.hasMatch(entry.key)) {
      out['serviceEmail'] ??= value;
    }
  }
  return out;
}
