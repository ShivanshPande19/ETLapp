import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Kept in sync with core/network/api_client.dart. Defaults to production; use
//   --dart-define=API_BASE_URL=http://192.168.x.x:8080
// for local development. (Base URL is not a secret — it ships in the binary.)
const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://etlapp-production.up.railway.app',
);

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );
});
