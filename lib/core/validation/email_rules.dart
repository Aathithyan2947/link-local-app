/// The email check for sign-up, Email login and Forgot password, with the message shown under
/// the field. Email login and password reset are email only (BUG-106): the backend rejects a
/// mobile number there with the same message (`accountEmail` in auth.schema.ts).
abstract final class EmailRules {
  static const invalid = 'Enter a valid email address';

  // Never stricter than the server's check (zod's email allows an apostrophe, as in o'brien@),
  // or an account email set in My Email couldn't log in.
  static final _valid = RegExp(r"^[\w.'+-]+@[\w-]+\.[\w.-]+$");

  static bool isValid(String v) => _valid.hasMatch(v.trim());
}
