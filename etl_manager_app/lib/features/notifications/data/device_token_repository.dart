import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// Registers / unregisters this device's FCM token with the backend.
///
/// The backend resolves WHO the token belongs to from the bearer JWT — the user
/// is never sent in the body, so a client cannot bind a token to somebody
/// else's account.
class DeviceTokenRepository {
  final Dio _dio;
  DeviceTokenRepository(this._dio);

  /// Bind this device to the signed-in user. Idempotent — safe to call on every
  /// login and on every token refresh.
  ///
  /// Returns true when the backend accepted it. Never throws: push registration
  /// failing must not block sign-in.
  Future<bool> register({
    required String fcmToken,
    String? platform,
    String? appVersion,
  }) async {
    try {
      await _dio.post(
        '/devices/register',
        data: {
          'fcm_token': fcmToken,
          if (platform != null) 'platform': platform,
          if (appVersion != null) 'app_version': appVersion,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stop pushing to this device. Called on logout.
  ///
  /// MUST be awaited BEFORE the auth token is cleared from storage, otherwise
  /// the Dio interceptor has no JWT to attach and the call 401s.
  ///
  /// Passing null unregisters every device for this user ("sign out everywhere").
  Future<bool> unregister({String? fcmToken}) async {
    try {
      await _dio.post(
        '/devices/unregister',
        data: {if (fcmToken != null) 'fcm_token': fcmToken},
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>((ref) {
  return DeviceTokenRepository(ref.watch(dioProvider));
});
