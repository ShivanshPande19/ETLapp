import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/token_storage.dart';

class AuthRepository {
  final Dio _dio;
  AuthRepository(this._dio);

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    final data = response.data;
    await TokenStorage.saveToken(data['access_token']);
    await TokenStorage.saveManagerInfo(
      data['manager_name'],
      data['manager_email'],
    );
    await TokenStorage.saveRole(data['role']);
    await TokenStorage.saveZone(data['zone']?.toString());
    await TokenStorage.saveOutletId(data['outlet_id']?.toString());
    return data;
  }

  Future<void> logout() async {
    await TokenStorage.clearAll();
  }

  /// Request a password-reset email. Backend always returns a generic message.
  Future<String> forgotPassword(String email) async {
    final res = await _dio.post(
      '/auth/forgot-password',
      data: {'email': email.trim()},
    );
    final data = res.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return 'If an account exists for that email, a reset link has been sent.';
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});
