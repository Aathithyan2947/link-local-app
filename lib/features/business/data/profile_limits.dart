/// Limits for the provider's "Set up your profile" fields, with the messages shown under each
/// field. The backend enforces the same numbers and wording (PROFILE_LIMITS in
/// profiles.schema.ts), so a value the app accepts is never rejected for being too long.
abstract final class ProfileLimits {
  static const name = 100;
  static const professionTitle = 80;
  static const aboutMe = 2000;
  static const yearsOfExperience = 80;
  static const rateAmount = 1000000;

  static String? nameError(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Name is required';
    if (t.length > name) return 'Name can be at most $name characters';
    return null;
  }

  static String? titleError(String text) => text.trim().length > professionTitle
      ? 'Professional title can be at most $professionTitle characters'
      : null;

  static String? aboutError(String text) =>
      text.trim().length > aboutMe ? 'About can be at most $aboutMe characters' : null;

  /// Optional; a whole number of years.
  static String? experienceError(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final years = int.tryParse(t);
    if (years == null || years < 0 || years > yearsOfExperience) {
      return 'Years of experience must be between 0 and $yearsOfExperience';
    }
    return null;
  }

  /// Optional (blank hides that charge); otherwise more than 0 and at most ₹10,00,000.
  static String? rateError(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final amount = double.tryParse(t);
    if (amount == null || amount <= 0) return 'Charge must be greater than 0';
    if (amount > rateAmount) return 'Charge can be at most ₹10,00,000';
    return null;
  }
}
