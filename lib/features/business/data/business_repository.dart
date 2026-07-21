import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'availability_models.dart';
import 'product_models.dart';
import 'rate_models.dart';

/// Service-provider business management: their own product catalogue,
/// availability schedule, blackout dates and delivery settings.
class BusinessRepository {
  BusinessRepository(this._dio);
  final Dio _dio;

  Future<List<SpProduct>> myProducts() async {
    final res = await _dio.get('/profiles/me/products');
    return (res.data['data'] as List)
        .map((e) => SpProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createProduct(Map<String, dynamic> data) async => _dio.post('/profiles/me/products', data: data);
  Future<void> updateProduct(int id, Map<String, dynamic> data) async =>
      _dio.patch('/profiles/me/products/$id', data: data);
  Future<void> deleteProduct(int id) async => _dio.delete('/profiles/me/products/$id');

  Future<String> uploadImage(String filePath) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath)});
    final res = await _dio.post('/media', data: form);
    return res.data['data']['url'] as String;
  }

  // ── Availability (weekly template) + blackout dates ──────────
  Future<AvailabilityData> availability() async {
    final res = await _dio.get('/profiles/me/availability');
    return AvailabilityData.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> setAvailability(Map<String, dynamic> data) async => _dio.put('/profiles/me/availability', data: data);

  Future<void> addBlackout(String date, {String? reason}) async => _dio.post(
        '/profiles/me/availability/blackouts',
        data: {'unavailableDate': date, 'reason': ?reason},
      );

  Future<void> deleteBlackout(int id) async => _dio.delete('/profiles/me/availability/blackouts/$id');

  // ── Delivery + advance-payment settings ──────────────────────
  /// Returns (delivery, paymentTerms) from the current profile.
  Future<(Map<String, dynamic>?, Map<String, dynamic>?)> mySettings() async {
    final res = await _dio.get('/profiles/me');
    final d = res.data['data'] as Map<String, dynamic>;
    return (d['delivery'] as Map<String, dynamic>?, d['paymentTerms'] as Map<String, dynamic>?);
  }

  Future<void> setDelivery(Map<String, dynamic> data) async => _dio.put('/profiles/me/delivery', data: data);
  Future<void> setPaymentTerms(Map<String, dynamic> data) async => _dio.put('/profiles/me/payment-terms', data: data);

  // ── Service charges / rates ──────────────────────────────────
  Future<List<SpRate>> myRates() async {
    final res = await _dio.get('/profiles/me/rates');
    return (res.data['data'] as List).map((e) => SpRate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setRates(List<SpRate> rates) async =>
      _dio.put('/profiles/me/rates', data: {'rates': rates.map((r) => r.toJson()).toList()});

  // ── Basic profile fields (used by the SP setup wizard) ───────
  Future<void> updateProfile(Map<String, dynamic> data) async => _dio.patch('/profiles/me', data: data);

  Future<void> addProfession(String category) async =>
      _dio.post('/profiles/me/professions', data: {'category': category});

  /// The current SP's provider kind (product | service), from GET /profiles/me.
  Future<String> myProviderKind() async {
    final res = await _dio.get('/profiles/me');
    return (res.data['data'] as Map<String, dynamic>)['providerKind'] as String? ?? 'product';
  }
}

final businessRepositoryProvider =
    Provider<BusinessRepository>((ref) => BusinessRepository(ref.watch(dioProvider)));

/// The current SP's own product list.
final myProductsProvider =
    FutureProvider<List<SpProduct>>((ref) => ref.watch(businessRepositoryProvider).myProducts());

/// The current SP's availability template + blackout dates.
final myAvailabilityProvider =
    FutureProvider<AvailabilityData>((ref) => ref.watch(businessRepositoryProvider).availability());

/// The current SP's published service rates.
final myRatesProvider = FutureProvider<List<SpRate>>((ref) => ref.watch(businessRepositoryProvider).myRates());

/// The current SP's provider kind (product | service).
final myProviderKindProvider = FutureProvider<String>((ref) => ref.watch(businessRepositoryProvider).myProviderKind());
