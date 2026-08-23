import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/auth/auth_scope.dart';
import 'referral_models.dart';

class ReferralsRepository {
  ReferralsRepository(this._dio);
  final Dio _dio;

  Future<ReferralSummary> mine() async {
    final res = await _dio.get('/referrals/mine');
    return ReferralSummary.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> sendInvite({String? name, String? phone, String? channel}) async {
    await _dio.post('/referrals/invite', data: {'name': ?name, 'phone': ?phone, 'channel': ?channel});
  }
}

final referralsRepositoryProvider = Provider<ReferralsRepository>((ref) => ReferralsRepository(ref.watch(dioProvider)));

final referralsProvider = FutureProvider<ReferralSummary>((ref) {
  ref.bindToAccount();
  return ref.watch(referralsRepositoryProvider).mine();
});
