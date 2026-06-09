int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

class IdName {
  const IdName(this.id, this.label, {this.subtitle});
  final int id;
  final String label;
  final String? subtitle;
}

class ProfileDetail {
  const ProfileDetail({
    required this.id,
    required this.name,
    required this.userType,
    this.photoUrl,
    this.dateOfBirth,
    this.gender,
    this.aboutMe,
    this.canOfferHelpWith,
    required this.completionPercent,
    required this.educations,
    required this.professions,
    required this.hobbies,
    required this.family,
    required this.pets,
    required this.contacts,
    required this.products,
    required this.serviceTypes,
    required this.hasDelivery,
    required this.hasPaymentMethods,
  });

  final int id;
  final String name;
  final String userType;
  final String? photoUrl;
  final String? dateOfBirth;
  final String? gender;
  final String? aboutMe;
  final String? canOfferHelpWith;
  final int completionPercent;

  final List<IdName> educations;
  final List<IdName> professions;
  final List<IdName> hobbies;
  final List<IdName> family;
  final List<IdName> pets;
  final List<IdName> contacts;
  final List<IdName> products;
  final List<IdName> serviceTypes;
  final bool hasDelivery;
  final bool hasPaymentMethods;

  bool get isServiceProvider => userType == 'service_provider';

  factory ProfileDetail.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) =>
        ((j[k] as List?) ?? []).cast<Map<String, dynamic>>();

    return ProfileDetail(
      id: _asInt(j['id']),
      name: j['name'] as String? ?? '',
      userType: (j['user'] as Map<String, dynamic>?)?['userType'] as String? ?? 'resident',
      photoUrl: j['photoUrl'] as String?,
      dateOfBirth: j['dateOfBirth'] as String?,
      gender: j['gender'] as String?,
      aboutMe: j['aboutMe'] as String?,
      canOfferHelpWith: j['canOfferHelpWith'] as String?,
      completionPercent: _asInt((j['completion'] as Map<String, dynamic>?)?['completionPercent']),
      educations: list('educations').map((e) {
        final m = e['educationMaster'] as Map<String, dynamic>?;
        final label = [m?['degree'], m?['collegeName'], m?['schoolName']]
            .whereType<String>()
            .join(' · ');
        return IdName(_asInt(e['id']), label.isEmpty ? 'Education' : label);
      }).toList(),
      professions: list('professions').map((e) {
        final cat = (e['professionMaster'] as Map<String, dynamic>?)?['category'] as String?;
        return IdName(_asInt(e['id']), cat ?? 'Profession', subtitle: e['companyOrDetail'] as String?);
      }).toList(),
      hobbies: list('hobbies').map((e) {
        final m = (e['hobbyMaster'] as Map<String, dynamic>?)?['name'] as String?;
        return IdName(_asInt(e['id']), m ?? e['customHobby'] as String? ?? 'Hobby');
      }).toList(),
      family: list('family')
          .map((e) => IdName(_asInt(e['id']), (e['relation'] as String? ?? '').replaceAll('_', ' '),
              subtitle: e['name'] as String?))
          .toList(),
      pets: list('pets')
          .map((e) => IdName(_asInt(e['id']), e['name'] as String? ?? 'Pet', subtitle: e['type'] as String?))
          .toList(),
      contacts: list('contactDetails')
          .map((e) => IdName(_asInt(e['id']), e['value'] as String? ?? '', subtitle: e['contactType'] as String?))
          .toList(),
      products: list('products')
          .map((e) => IdName(_asInt(e['id']), e['name'] as String? ?? '',
              subtitle: e['price'] != null ? '₹${e['price']}' : null))
          .toList(),
      serviceTypes: list('serviceTypes').map((e) {
        final sub = (e['subcategory'] as Map<String, dynamic>?)?['name'] as String?;
        return IdName(_asInt(e['id']), sub ?? 'Service');
      }).toList(),
      hasDelivery: j['delivery'] != null,
      hasPaymentMethods: ((j['paymentMethods'] as List?) ?? []).isNotEmpty,
    );
  }
}
