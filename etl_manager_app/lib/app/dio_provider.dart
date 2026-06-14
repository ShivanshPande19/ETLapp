import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String baseUrl = 'http://172.20.10.4:8080'; // Tumhara backend IP

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
