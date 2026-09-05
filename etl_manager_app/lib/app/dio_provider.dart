import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Kept in sync with core/network/api_client.dart. Defaults to production; use
//   --dart-define=API_BASE_URL=http://192.168.x.x:8080
// for local development. (Base URL is not a secret — it ships in the binary.)
const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://app.eattrucklove.com',
);

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      // 30s (was 10s): Railway free-tier cold starts and slow mobile networks
      // routinely exceed 10s, which surfaced to users as a blank "₹0" dashboard
      // rather than a slow-but-successful load.
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );
});
