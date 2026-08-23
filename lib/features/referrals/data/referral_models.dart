int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

/// One person the current user has referred.
class ReferredPerson {
  const ReferredPerson({required this.name, required this.status, this.createdAt, this.registeredAt});
  final String name;
  final String status; // sent | opened | partial_registration | complete_registration
  final DateTime? createdAt;
  final DateTime? registeredAt;

  bool get isRegistered => status == 'complete_registration';

  factory ReferredPerson.fromJson(Map<String, dynamic> j) => ReferredPerson(
        name: j['name'] as String? ?? 'Someone',
        status: j['status'] as String? ?? 'sent',
        createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
        registeredAt: j['registeredAt'] != null ? DateTime.tryParse(j['registeredAt'] as String) : null,
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
