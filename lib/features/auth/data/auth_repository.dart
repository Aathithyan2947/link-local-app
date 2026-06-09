import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'auth_models.dart';

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<AuthResult> register({
    required String name,
    required String password,
    String? email,
    String? mobile,
    String userType = 'resident',
    String? referralCode,
    int? referralSourceId,
  }) async {
    try {
      final res = await _dio.post('/auth/register', data: {
        'name': name,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
        if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
        'userType': userType,
        if (referralCode != null && referralCode.isNotEmpty) 'referralCode': referralCode,
        'referralSourceId': ?referralSourceId,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AuthResult> login({required String identifier, required String password}) async {
    try {
      final res = await _dio.post('/auth/login', data: {
        'identifier': identifier,
        'password': password,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AppUser> me() async {
    try {
      final res = await _dio.get('/auth/me');
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Requests an OTP. Returns the dev OTP (only in dev) for convenience.
  Future<String?> requestOtp({
    String? mobile,
    String? email,
    required String purpose,
    String? name,
  }) async {
    try {
      final res = await _dio.post('/auth/otp/request', data: {
        if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
        if (email != null && email.isNotEmpty) 'email': email,
        'purpose': purpose,
        if (name != null && name.isNotEmpty) 'name': name,
      });
      return res.data['data']?['devOtp'] as String?;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AuthResult> verifyOtp({
    String? mobile,
    String? email,
    required String otp,
    required String purpose,
    String? name,
  }) async {
    try {
      final res = await _dio.post('/auth/otp/verify', data: {
        if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
        if (email != null && email.isNotEmpty) 'email': email,
        'otp': otp,
        'purpose': purpose,
        if (name != null && name.isNotEmpty) 'name': name,
      });
      return AuthResult.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> setUserType(String userType) async {
    try {
      await _dio.patch('/profiles/me/user-type', data: {'userType': userType});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});
