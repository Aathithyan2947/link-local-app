import '../../../core/time/server_time.dart';
import 'invite_rules.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

/// One person the current user has referred.
class ReferredPerson {
  const ReferredPerson({
    required this.name,
    required this.status,
    this.createdAt,
    this.registeredAt,
    this.invitedName,
    this.phone,
    this.profileName,
  });

  /// The server's ready-made label (kept for older builds; prefer [title]).
  final String name;
  final String status; // sent | opened | partial_registration | complete_registration
  final DateTime? createdAt;
  final DateTime? registeredAt;

  /// The name typed when inviting, if any.
  final String? invitedName;

  /// The number typed when inviting. Null for someone who signed up with the code directly —
  /// their own number is never shown.
  final String? phone;

  /// Their name on LinkLocal once they've joined.
  final String? profileName;

  bool get isRegistered => status == 'complete_registration';

  /// The tile's title: the typed name, else the invited number, else their profile name.
  String get title {
    if (invitedName?.trim().isNotEmpty == true) return invitedName!.trim();
    if (phone?.isNotEmpty == true) return formatIndianMobile(phone!);
    if (profileName?.trim().isNotEmpty == true) return profileName!.trim();
    return name;
  }

  /// The number under the title, when the title is a name.
  String? get phoneLine =>
      phone?.isNotEmpty == true && title != formatIndianMobile(phone!) ? formatIndianMobile(phone!) : null;

  factory ReferredPerson.fromJson(Map<String, dynamic> j) => ReferredPerson(
        name: j['name'] as String? ?? 'Someone',
        status: j['status'] as String? ?? 'sent',
        createdAt: parseServerTime(j['createdAt']),
        registeredAt: parseServerTime(j['registeredAt']),
        invitedName: j['invitedName'] as String?,
        phone: j['phone'] as String?,
        profileName: j['profileName'] as String?,
      );
}

/// Everything the Referrals screen needs, in one call.
class ReferralSummary {
  const ReferralSummary({
    required this.inviteCode,
    required this.invitedCount,
    required this.registeredCount,
    required this.pointsBalance,
    required this.dailyLimit,
    required this.dailySent,
    required this.referred,
  });
  final String inviteCode;
  final int invitedCount;
  final int registeredCount;
  final int pointsBalance;
  final int dailyLimit;
  final int dailySent;
  final List<ReferredPerson> referred;

  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
        inviteCode: j['inviteCode'] as String? ?? '',
        invitedCount: _asInt(j['invitedCount']),
        registeredCount: _asInt(j['registeredCount']),
        pointsBalance: _asInt(j['pointsBalance']),
        dailyLimit: _asInt(j['dailyLimit']),
        dailySent: _asInt(j['dailySent']),
        referred: ((j['referred'] as List?) ?? [])
            .map((e) => ReferredPerson.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
