import 'package:flutter/services.dart';

/// Limits for member-created content — posts, groups and events — with the messages shown under
/// each field. The backend enforces the same numbers and wording (CONTENT_LIMITS in
/// contentLimits.ts), so a value the app accepts is never rejected for it (BUG-070–074).
abstract final class ContentLimits {
  static const postText = 2000;
  static const titleMin = 3;
  static const titleMax = 80;
  static const description = 2000;

  /// Same cap as provider charges (ProfileLimits.rateAmount).
  static const price = 1000000;
  static const maxMembersMin = 2;
  static const maxMembersMax = 10000;
  static const maxAttendeesMin = 1;
  static const maxAttendeesMax = 10000;
  static const durationMin = 15;
  static const durationMax = 1440;
  static const location = 200;
  static const onlineLink = 500;
  static const materialItem = 100;
  static const materialItems = 20;

  // No emoji, symbols or # (the user's call, 2026-10-22); the backend's TITLE_CHARS matches.
  static final _titleChar = RegExp(r"[\p{L}\p{M}\p{N} .,'&()/\-!?:+]", unicode: true);
  static final _titleChars = RegExp(r"^[\p{L}\p{M}\p{N} .,'&()/\-!?:+]+$", unicode: true);

  /// Drops anything a group name or event title can't contain (#, emoji, symbols) as it's typed
  /// or pasted, like the sign-up name field.
  static final titleInputFormatter = FilteringTextInputFormatter.allow(_titleChar);
  static final _hasLetter = RegExp(r'\p{L}', unicode: true);
  static final _link = RegExp(r'^https?://\S+$', caseSensitive: false);

  /// A group name or event title ([label] is "Group name" / "Event title").
  static String? titleError(String label, String text) {
    final t = text.trim();
    if (t.isEmpty) return '$label is required';
    if (t.length < titleMin) return '$label must be at least $titleMin characters';
    if (t.length > titleMax) return '$label can be at most $titleMax characters';
    if (!_titleChars.hasMatch(t)) {
      return "$label: only letters, numbers, spaces and . , ' & ( ) / - ! ? : + are allowed";
    }
    if (!_hasLetter.hasMatch(t)) return '$label must include a letter';
    return null;
  }

  static String? descriptionError(String text) =>
      text.trim().length > description ? 'Description can be at most $description characters' : null;

  static String? postTextError(String text) =>
      text.trim().length > postText ? 'Post can be at most $postText characters' : null;

  /// Only for a paid group/event ([what] is "group" / "event"): required, more than 0, at most
  /// ₹10,00,000, at most 2 decimals.
  static String? priceError(String text, {required String what}) {
    final t = text.trim();
    if (t.isEmpty) return 'Enter a price for a paid $what';
    final v = double.tryParse(t);
    if (v == null) return 'Enter a valid price';
    if (v <= 0) return 'Price must be greater than 0';
    if (v > price) return 'Price can be at most ₹10,00,000';
    if ((v * 100 - (v * 100).round()).abs() > 1e-6) return 'Price can have at most 2 decimals';
    return null;
  }

  /// Optional whole number in [min]–[max].
  static String? _optionalRange(String text, int min, int max, String message) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    return v == null || v < min || v > max ? message : null;
  }

  static String? maxMembersError(String text) =>
      _optionalRange(text, maxMembersMin, maxMembersMax, 'Max members must be between $maxMembersMin and 10,000');

  static String? maxAttendeesError(String text) => _optionalRange(
      text, maxAttendeesMin, maxAttendeesMax, 'Max attendees must be between $maxAttendeesMin and 10,000');

  static String? durationError(String text) {
    final msg = 'Duration must be between $durationMin and $durationMax minutes';
    final v = int.tryParse(text.trim());
    return v == null || v < durationMin || v > durationMax ? msg : null;
  }

  /// In-person events need a place.
  static String? locationError(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Enter the event location';
    if (t.length > location) return 'Location can be at most $location characters';
    return null;
  }

  /// Online events need a link.
  static String? onlineLinkError(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Enter the event link';
    if (t.length > onlineLink) return 'Link can be at most $onlineLink characters';
    if (!_link.hasMatch(t)) return 'Enter a valid link starting with http:// or https://';
    return null;
  }

  static String? materialError(String text) =>
      text.trim().length > materialItem ? 'Each item can be at most $materialItem characters' : null;

  /// A stored price for an edit form: whole rupees without decimals, anything else as is. The
  /// old `toStringAsFixed(0)` rounded ₹99.50 up to 100, and saving the form charged that.
  static String priceText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
