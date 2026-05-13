// lib/core/services/sse_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../network/api_client.dart';
import '../utils/token_storage.dart';
import '../../features/staff/domain/housekeeping_notifier.dart';
import '../../features/housekeeping/presentation/manager_housekeeping_screen.dart'; // ✅

class SSEService {
  final Ref _ref;
  http.Client? _client;
  StreamSubscription? _subscription;
  bool _disposed = false;

  SSEService(this._ref);

  Future<void> connect() async {
    await disconnect();
    _disposed = false;

    final token = await TokenStorage.getToken();
    final zone = await TokenStorage.getZone();
    final isStaff = await TokenStorage.isStaff();

    if (token == null) return;

    final courtId = isStaff ? (_parseZone(zone) ?? 0) : 0;

    try {
      _client = http.Client();

      final uri = Uri.parse('$baseUrl/events/stream?court_id=$courtId');
      final request = http.Request('GET', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request);

      _subscription = response.stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: (_) => _reconnect(),
            onDone: () => _reconnect(),
            cancelOnError: false,
          );

      debugPrint('[SSE] Connected — court_id: $courtId');
    } catch (e) {
      debugPrint('[SSE] connect error: $e');
      _reconnect();
    }
  }

  String _buffer = '';

  void _onLine(String line) {
    if (line.startsWith(':')) return;

    if (line.startsWith('data:')) {
      _buffer = line.substring(5).trim();
    } else if (line.isEmpty && _buffer.isNotEmpty) {
      try {
        final data = jsonDecode(_buffer) as Map<String, dynamic>;
        _handleEvent(data);
      } catch (_) {}
      _buffer = '';
    }
  }

  void _handleEvent(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'housekeeping_update') {
      // ✅ Staff side
      _ref.invalidate(housekeepingNotifierProvider);

      // ✅ Manager side — aaj ki date ke saath invalidate
      final today = DateTime.now().toIso8601String().substring(0, 10);
      _ref.invalidate(managerHkProvider(today));
    }
  }

  void _reconnect() {
    if (_disposed) return;
    debugPrint('[SSE] Reconnecting in 5s...');
    Future.delayed(const Duration(seconds: 5), () {
      if (!_disposed) connect();
    });
  }

  Future<void> disconnect() async {
    _disposed = true;
    await _subscription?.cancel();
    _client?.close();
    _subscription = null;
    _client = null;
    _buffer = '';
  }

  int? _parseZone(String? zone) {
    if (zone == null) return null;
    final z = zone.trim().toUpperCase();
    final direct = int.tryParse(z);
    if (direct != null && direct >= 1 && direct <= 3) return direct;
    final letter = RegExp(r'[ABC]').firstMatch(z)?.group(0);
    if (letter != null) return const {'A': 1, 'B': 2, 'C': 3}[letter];
    final match = RegExp(r'(\d)').firstMatch(z);
    if (match != null) {
      final n = int.tryParse(match.group(1)!);
      if (n != null && n >= 1 && n <= 3) return n;
    }
    return null;
  }
}

final sseServiceProvider = Provider<SSEService>((ref) {
  final service = SSEService(ref);
  ref.onDispose(() => service.disconnect());
  return service;
});
