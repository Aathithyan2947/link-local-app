int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

/// One service on the All Services page, with how many providers in scope offer it.
class CatalogService {
  const CatalogService({required this.id, required this.name, required this.count});
  final int id;
  final String name;
  final int count;

  factory CatalogService.fromJson(Map<String, dynamic> j) =>
      CatalogService(id: _asInt(j['id']), name: j['name'] as String? ?? '', count: _asInt(j['count']));
}

/// A category of services on the All Services page (BUG-087).
class ServiceCatalogCategory {
  const ServiceCatalogCategory({required this.id, required this.name, required this.services});
  final int id;
  final String name;
  final List<CatalogService> services;

  factory ServiceCatalogCategory.fromJson(Map<String, dynamic> j) => ServiceCatalogCategory(
        id: _asInt(j['id']),
        name: j['name'] as String? ?? '',
        services: ((j['services'] as List?) ?? [])
            .map((e) => CatalogService.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
