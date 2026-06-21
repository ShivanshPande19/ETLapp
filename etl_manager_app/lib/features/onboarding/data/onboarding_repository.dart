// lib/features/onboarding/data/onboarding_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart'; // authenticated dioProvider
import '../domain/onboarding_models.dart';

class OnboardingRepository {
  final Dio _dio;
  OnboardingRepository(this._dio);

  Future<ApplicationsData> listApplications({
    int? courtId,
    String? status,
  }) async {
    final res = await _dio.get(
      '/onboarding/applications',
      queryParameters: {
        if (courtId != null) 'court_id': courtId,
        if (status != null) 'status': status,
      },
    );
    final data = res.data as Map<String, dynamic>;
    final list = (data['applications'] as List? ?? [])
        .map((e) => OutletApplication.fromJson(e as Map<String, dynamic>))
        .toList();
    return ApplicationsData(
      applications: list,
      pendingCount: data['pending_count'] ?? 0,
    );
  }

  Future<ApproveResult> approve({
    required int applicationId,
    required String restId,
    String? ppAppKey,
    String? ppAppSecret,
    String? ppAccessToken,
    String? ppCookie,
  }) async {
    final res = await _dio.post(
      '/onboarding/applications/$applicationId/approve',
      data: {
        'rest_id': restId,
        if (ppAppKey != null && ppAppKey.isNotEmpty) 'pp_app_key': ppAppKey,
        if (ppAppSecret != null && ppAppSecret.isNotEmpty)
          'pp_app_secret': ppAppSecret,
        if (ppAccessToken != null && ppAccessToken.isNotEmpty)
          'pp_access_token': ppAccessToken,
        if (ppCookie != null && ppCookie.isNotEmpty) 'pp_cookie': ppCookie,
      },
    );
    return ApproveResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> reject({required int applicationId, String? reason}) async {
    await _dio.post(
      '/onboarding/applications/$applicationId/reject',
      data: {'reason': reason ?? ''},
    );
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.watch(dioProvider));
});

/// Applications for a given court (auto-refreshes on invalidate).
final applicationsProvider = FutureProvider.autoDispose
    .family<ApplicationsData, int>((ref, courtId) async {
      return ref
          .read(onboardingRepositoryProvider)
          .listApplications(courtId: courtId);
    });
