// NEW FILE — create at: lib/features/home/presentation/home_providers.dart
// This is the debug file for Bug 3 — wires up real API data for the home screen.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../staff/data/housekeeping_repository.dart';

// ─── Housekeeping summary model ───────────────────────────────────────────────

class HkHomeSummary {
  final int done;
  final int total;
  const HkHomeSummary({required this.done, required this.total});

  double get pct => total == 0 ? 0.0 : done / total;
  int get pending => total - done;
  String get label => '$done / $total zones';
}

// ─── Housekeeping provider (Bug 3 — full debug) ───────────────────────────────

final homeHousekeepingProvider = FutureProvider.autoDispose<HkHomeSummary>((
  ref,
) async {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  debugPrint('🧹 [HK] Fetching for date: $today');

  try {
    final repo = ref.read(housekeepingRepoProvider);
    final status = await repo.getFullStatus(date: today);

    // ── Bug 3 checkpoint 1: did the API return null? ──────────────────────
    if (status == null) {
      debugPrint('🧹 [HK] ❌ getFullStatus() returned NULL');
      debugPrint(
        '🧹 [HK]    Cause: API call failed silently (check Dio logs above)',
      );
      return const HkHomeSummary(done: 0, total: 0);
    }

    debugPrint('🧹 [HK] ✅ API returned — date: ${status.date}');

    // ── Bug 3 checkpoint 2: are courts empty? ────────────────────────────
    if (status.courts.isEmpty) {
      debugPrint('🧹 [HK] ⚠️  courts list is EMPTY');
      debugPrint(
        '🧹 [HK]    Cause A: No housekeeping submissions exist for $today',
      );
      debugPrint(
        '🧹 [HK]    Cause B: Backend /housekeeping/status returned courts:[]',
      );
      debugPrint('🧹 [HK]    Raw response date field: ${status.date}');
      return const HkHomeSummary(done: 0, total: 0);
    }

    debugPrint('🧹 [HK] courts count: ${status.courts.length}');

    int done = 0, total = 0;
    for (final court in status.courts) {
      // ── Bug 3 checkpoint 3: are shifts empty per court? ────────────────
      if (court.shifts.isEmpty) {
        debugPrint('🧹 [HK]   Court ${court.courtId} has NO shifts for $today');
        continue;
      }
      for (final shift in court.shifts) {
        debugPrint(
          '🧹 [HK]   Court ${court.courtId} | ${shift.shift.name} '
          '| done=${shift.done} total=${shift.total} submitted=${shift.submitted}',
        );
        done += shift.done;
        total += shift.total;
      }
    }

    // ── Bug 3 checkpoint 4: totals are both 0 even with courts data ───────
    if (total == 0) {
      debugPrint('🧹 [HK] ⚠️  total=0 despite ${status.courts.length} courts');
      debugPrint(
        '🧹 [HK]    Cause: All shifts have total=0 — no tasks configured for today',
      );
    }

    final pct = total == 0 ? 0 : (done / total * 100).round();
    debugPrint('🧹 [HK] ✅ RESULT: done=$done total=$total ($pct%)');
    return HkHomeSummary(done: done, total: total);
  } on DioException catch (e) {
    debugPrint('🧹 [HK] ❌ DioException: ${e.response?.statusCode} ${e.type}');
    debugPrint('🧹 [HK]    URL: ${e.requestOptions.uri}');
    debugPrint('🧹 [HK]    Message: ${e.message}');
    return const HkHomeSummary(done: 0, total: 0);
  } catch (e, st) {
    debugPrint('🧹 [HK] ❌ EXCEPTION: $e');
    debugPrint('🧹 [HK]    STACKTRACE: $st');
    return const HkHomeSummary(done: 0, total: 0);
  }
});

// ─── Open complaints count ────────────────────────────────────────────────────

final homeComplaintsProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final dio = ref.read(dioProvider);
    final res = await dio.get<dynamic>(
      '/complaints',
      queryParameters: {'status': 'open'},
    );
    final data = res.data;
    if (data is List) return data.length;
    if (data is Map && data['complaints'] is List)
      return (data['complaints'] as List).length;
    if (data is Map && data['total'] is int) return data['total'] as int;
    debugPrint('🔴 [COMPLAINTS] Unexpected response shape: $data');
    return 0;
  } on DioException catch (e) {
    debugPrint(
      '🔴 [COMPLAINTS] DioError: ${e.response?.statusCode} ${e.message}',
    );
    return 0;
  } catch (e) {
    debugPrint('🔴 [COMPLAINTS] Error: $e');
    return 0;
  }
});

// ─── Open maintenance issues count ───────────────────────────────────────────

final homeMaintenanceProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final dio = ref.read(dioProvider);
    final res = await dio.get<dynamic>(
      '/maintenance',
      queryParameters: {'status': 'open'},
    );
    final data = res.data;
    if (data is List) return data.length;
    if (data is Map && data['issues'] is List)
      return (data['issues'] as List).length;
    if (data is Map && data['total'] is int) return data['total'] as int;
    debugPrint('🔧 [MAINTENANCE] Unexpected response shape: $data');
    return 0;
  } on DioException catch (e) {
    debugPrint(
      '🔧 [MAINTENANCE] DioError: ${e.response?.statusCode} ${e.message}',
    );
    return 0;
  } catch (e) {
    debugPrint('🔧 [MAINTENANCE] Error: $e');
    return 0;
  }
});
