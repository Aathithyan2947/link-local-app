import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

/// One row of the Members list — who they are and roughly where, never contact details.
class MemberItem {
  const MemberItem({
    required this.profileId,
    required this.name,
    this.photoUrl,
    required this.isServiceProvider,
    this.roleLabel,
    this.areaName,
  });

  factory MemberItem.fromJson(Map<String, dynamic> j) => MemberItem(
        profileId: (j['profileId'] as num).toInt(),
        name: j['name'] as String? ?? '',
        photoUrl: j['photoUrl'] as String?,
        isServiceProvider: j['isServiceProvider'] as bool? ?? false,
        roleLabel: j['roleLabel'] as String?,
        areaName: j['areaName'] as String?,
      );

  final int profileId;
  final String name;
  final String? photoUrl;
  final bool isServiceProvider;

  /// Their service (providers) or profession (residents), when set.
  final String? roleLabel;
  final String? areaName;

  /// "Hair stylist · Pai Nagar", dropping whichever part is missing.
  String get subtitle => [roleLabel, areaName].where((s) => s != null && s.trim().isNotEmpty).join(' · ');
}

class MembersPage {
  const MembersPage({required this.items, required this.total});
  final List<MemberItem> items;
  final int total;
}

class MembersRepository {
  MembersRepository(this._dio);
  final Dio _dio;

  /// Members visible to the caller in [scope] — the same set Home's Members tile counts.
  Future<MembersPage> list({
    required String scope,
    int? areaId,
    String? q,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final res = await _dio.get('/members', queryParameters: {
        'scope': scope,
        'areaId': ?areaId,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'pageSize': pageSize,
      });
      return MembersPage(
        items: ((res.data['data'] as List?) ?? [])
            .map((e) => MemberItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: ((res.data['meta'] as Map?)?['total'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final membersRepositoryProvider = Provider<MembersRepository>((ref) => MembersRepository(ref.watch(dioProvider)));
