// lib/features/home/presentation/home_providers.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../staff/data/housekeeping_repository.dart';
import '../../staff/domain/housekeeping_models.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class ShiftPillData {
  final String label;
  final int done;
  final int total;

  const ShiftPillData({
    required this.label,
    required this.done,
    required this.total,
  });

  double get pct => total == 0 ? 0.0 : done / total;
  bool get isComplete => total > 0 && done == total;
}

class CourtHkRow {
  final String courtName;
  final ShiftPillData morning;
  final ShiftPillData day;
  final ShiftPillData night;

  const CourtHkRow({
    required this.courtName,
    required this.morning,
    required this.day,
    required this.night,
  });
}

// ─── Helper ───────────────────────────────────────────────────────────────────

ShiftPillData _emptyPill(String label) =>
    ShiftPillData(label: label, done: 0, total: 0);

// ─── Housekeeping provider ────────────────────────────────────────────────────

final homeHousekeepingProvider = FutureProvider.autoDispose<List<CourtHkRow>>((
  ref,
) async {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  debugPrint('🧹 [HK] Fetching for date: $today');

  try {
    final repo = ref.read(housekeepingRepoProvider);
    final status = await repo.getFullStatus(date: today);

    if (status == null || status.courts.isEmpty) return [];

    return status.courts.map((court) {
      ShiftPillData morning = _emptyPill('M');
      ShiftPillData day = _emptyPill('D');
      ShiftPillData night = _emptyPill('N');

      for (final s in court.shifts) {
        final pill = ShiftPillData(
          label: s.shift == Shift.morning
              ? 'M'
              : s.shift == Shift.day
              ? 'D'
              : 'N',
          done: s.done,
          total: s.total,
        );
        if (s.shift == Shift.morning) {
          morning = pill;
        } else if (s.shift == Shift.day) {
          day = pill;
        } else {
          night = pill;
        }
      }

      return CourtHkRow(
        courtName: 'Court ${court.courtId}',
        morning: morning,
        day: day,
        night: night,
      );
    }).toList();
  } on DioException catch (e) {
    debugPrint('🧹 [HK] ❌ DioError: ${e.response?.statusCode} ${e.message}');
    return [];
  } catch (e) {
    debugPrint('🧹 [HK] ❌ EXCEPTION: $e');
    return [];
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
    return 0;
  } on DioException catch (e) {
    debugPrint('🔴 [COMPLAINTS] DioError: ${e.response?.statusCode}');
    return 0;
  } catch (_) {
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
    return 0;
  } on DioException catch (e) {
    debugPrint('🔧 [MAINTENANCE] DioError: ${e.response?.statusCode}');
    return 0;
  } catch (_) {
    return 0;
  }
});
