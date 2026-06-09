/// Authenticated user (shape returned by /auth/me and /auth/login).
class AppUser {
  const AppUser({
    required this.id,
    required this.userType,
    this.email,
    this.mobile,
    this.name,
    this.photoUrl,
    this.referralCode,
    this.isVerified = false,
    this.hasAddress = false,
    this.city,
  });

  final int id;
  final String userType; // resident | service_provider | business_listing
  final String? email;
  final String? mobile;
  final String? name;
  final String? photoUrl;
  final String? referralCode;
  final bool isVerified;
  final bool hasAddress;
  final String? city;

  bool get isServiceProvider => userType == 'service_provider';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    final address = profile?['address'] as Map<String, dynamic>?;
    final area = address?['area'] as Map<String, dynamic>?;
    final city = area?['city'] as Map<String, dynamic>?;
    return AppUser(
      id: json['id'] as int,
      userType: json['userType'] as String? ?? 'resident',
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      name: profile?['name'] as String?,
      photoUrl: profile?['photoUrl'] as String?,
      referralCode: json['referralCode'] as String?,
      isVerified: json['isVerified'] as bool? ?? false,
      hasAddress: address != null,
      city: city?['name'] as String?,
    );
  }
}

class AuthResult {
  AuthResult({required this.user, required this.accessToken, required this.refreshToken});
  final AppUser user;
  final String accessToken;
  final String refreshToken;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }
}
