import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/token_storage.dart';
import '../../features/auth/domain/auth_notifier.dart';

// Backend API base URL.
//
// Defaults to the production Railway backend, so a normal `flutter build`
// (and App Store / Play Store releases) point at prod automatically.
//
// For local development against a machine on your LAN, override at build/run
// time WITHOUT editing this file:
//   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8080
//
// NOTE: this is NOT a secret — the URL ships inside every app binary regardless.
// Real secrets (JWT key, Petpooja/Resend keys, DB URL) live only in the
// backend's Railway env vars, never here.
const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://etlapp-production.up.railway.app',
);

/// Resolves a stored media path to a fully-qualified URL.
///
/// Backend now returns relative paths like `uploads/housekeeping/xyz.jpg`
/// (served by the `/uploads` StaticFiles mount). Older records may still hold
/// absolute Cloudinary URLs (`https://...`) — those are returned untouched so
/// legacy photos keep loading.
String? resolveMediaUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final cleaned = path.startsWith('/') ? path.substring(1) : path;
  return '$baseUrl/$cleaned';
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenStorage.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        // Any authenticated request coming back 401 means the JWT expired or is
        // no longer valid. Sign the user out cleanly so the router sends them to
        // login, instead of leaving the app in a half-broken state (some
        // screens erroring, others showing stale cached data).
        //
        // Auth endpoints are skipped: a 401 there is a wrong password / bad
        // reset link, handled locally by those screens — not a session expiry.
        final statusCode = error.response?.statusCode;
        final path = error.requestOptions.path;
        final isAuthCall = path.contains('/auth/');
        if (statusCode == 401 && !isAuthCall) {
          ref.read(authNotifierProvider.notifier).sessionExpired();
        }
        return handler.next(error);
      },
    ),
  );

  return dio;
});
