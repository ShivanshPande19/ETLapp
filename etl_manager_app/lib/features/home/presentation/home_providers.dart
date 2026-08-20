// lib/features/home/presentation/home_providers.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../sales/data/sales_repository.dart';
import '../../staff/data/housekeeping_repository.dart';
import '../../staff/domain/housekeeping_models.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../courts/data/courts_repository.dart';
import '../../outlets/domain/outlet_providers.dart'; // multi-outlet: selected outlet

// ─── Models ───────────────────────────────────────────────────────────────────

class ShiftPillData {
  final String label;
  final int done;
  final int total;
  final bool isActive;

  const ShiftPillData({
    required this.label,
    required this.done,
    required this.total,
    this.isActive = false,
  });

  double get pct => total == 0 ? 0.0 : done / total;
  bool get isComplete => total > 0 && done == total;
}

class CourtHkRow {
  final String courtName;
  final List<ShiftPillData> shifts;

  const CourtHkRow({
    required this.courtName,
    required this.shifts,
  });

  /// Total tasks completed across all of this court's shifts today.
  int get done => shifts.fold(0, (sum, s) => sum + s.done);

  /// Total tasks configured across all of this court's shifts today.
  int get total => shifts.fold(0, (sum, s) => sum + s.total);

  /// Overall completion fraction for the court (0.0–1.0).
  double get pct => total == 0 ? 0.0 : done / total;

  /// True only when the court has tasks and every one of them is done.
  bool get isComplete => total > 0 && done == total;

  /// Number of shifts that are fully complete.
  int get completedShifts => shifts.where((s) => s.isComplete).length;
}

// ─── Revenue Card — Yesterday, All Courts ─────────────────────────────────────

final homeYesterdaySalesProvider = FutureProvider.autoDispose<double>((
  ref,
) async {
  try {
    final repo = ref.read(salesRepositoryProvider);
    final summary = await repo.getSalesSummary(
      courtId: null,
      period: 'yesterday',
    );
    return summary.totalSales;
  } on DioException catch (e) {
    debugPrint(
      '💰 [YESTERDAY_SALES] DioError: ${e.response?.statusCode} ${e.message}',
    );
    // Rethrow instead of returning 0.0: a network/timeout failure must NOT look
    // like a genuine zero-sales day. The card renders an "unavailable" dash for
    // the error state (see home_screen), so the manager can tell the difference.
    rethrow;
  } catch (e) {
    debugPrint('💰 [YESTERDAY_SALES] Exception: $e');
    rethrow;
  }
});

// ─── Sparkline Card — This Month Cumulative, All Courts ──────────────────────

final homeMonthSalesProvider = FutureProvider.autoDispose<double>((ref) async {
  try {
    final repo = ref.read(salesRepositoryProvider);
    final summary = await repo.getSalesSummary(courtId: null, period: 'month');
    return summary.totalSales;
  } on DioException catch (e) {
    debugPrint(
      '💰 [MONTH_SALES] DioError: ${e.response?.statusCode} ${e.message}',
    );
    // Rethrow instead of returning 0.0 — see homeYesterdaySalesProvider.
    rethrow;
  } catch (e) {
    debugPrint('💰 [MONTH_SALES] Exception: $e');
    rethrow;
  }
});

// ─── Housekeeping Provider ────────────────────────────────────────────────────

final homeHousekeepingProvider = FutureProvider.autoDispose<List<CourtHkRow>>((
  ref,
) async {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  debugPrint('🧹 [HK] Fetching for date: $today');

  try {
    final repo = ref.read(housekeepingRepoProvider);

    // ✅ Real court names (id → name) so the widget shows actual courts,
    // not hardcoded "Court 1/2/3".
    final courts = await ref.read(courtsRepositoryProvider).getCourts();
    final courtNames = {for (final c in courts) c.id: c.name};

    final status = await repo.getFullStatus(date: today);

    if (status == null || status.courts.isEmpty) return [];

    // ✅ Only show courts that actually exist in the DB (/courts/). Any stale
    // court id coming from the housekeeping status that isn't a real court is
    // skipped — so no more hardcoded-looking "Court 2 / Court 3".
    return status.courts
        .where((court) => courtNames.containsKey(court.courtId))
        .map((court) {
          final shifts = court.shifts
              .map(
                (s) => ShiftPillData(
                  label: s.shiftName,
                  done: s.done,
                  total: s.total,
                  isActive: s.isActiveNow,
                ),
              )
              .toList();

          return CourtHkRow(
            courtName: courtNames[court.courtId]!,
            shifts: shifts,
          );
        })
        .toList();
  } on DioException catch (e) {
    debugPrint('🧹 [HK] ❌ DioError: ${e.response?.statusCode} ${e.message}');
    return [];
  } catch (e) {
    debugPrint('🧹 [HK] ❌ EXCEPTION: $e');
    return [];
  }
});

// ─── Feedbacks Count (Replaced Complaints) ──────────────────────────────────

final homeFeedbacksProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final dio = ref.read(dioProvider);
    final res = await dio.get<dynamic>('/feedback/all');

    final data = res.data;
    if (data is List) return data.length;
    if (data is Map && data['feedbacks'] is List) {
      return (data['feedbacks'] as List).length;
    }
    if (data is Map && data['total'] is int) return data['total'] as int;

    return 0;
  } on DioException catch (e) {
    debugPrint('🔴 [FEEDBACKS] DioError: ${e.response?.statusCode}');
    return 0;
  } catch (_) {
    return 0;
  }
});

// ─── Open Maintenance Issues Count ───────────────────────────────────────────

final homeMaintenanceProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final dio = ref.read(dioProvider);
    // ✅ FIX: New API format {items: [...]} + new statuses
    final res = await dio.get<dynamic>(
      '/maintenance',
      queryParameters: {'limit': 100, 'offset': 0},
    );
    final data = res.data;
    if (data is Map && data['items'] is List) {
      // "Pending" = jo bhi CLOSED nahi hai
      return (data['items'] as List)
          .where((i) => i is Map && i['status'] != 'CLOSED')
          .length;
    }
    return 0;
  } on DioException catch (e) {
    debugPrint('🔧 [MAINTENANCE] DioError: ${e.response?.statusCode}');
    return 0;
  } catch (_) {
    return 0;
  }
});

// ─── OUTLET DASHBOARD PROVIDER (NAYA) ───────────────────────────────────────

final outletDashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      // MULTI-OUTLET: follow the switcher's selected outlet (defaults to the
      // manager's primary outlet, so single-outlet owners are unaffected).
      final outletId = ref.watch(selectedOutletIdProvider);

      if (outletId == null) {
        throw Exception("No outlet assigned to this manager");
      }

      try {
        final dio = ref.read(dioProvider);

        // Purani existing ETL API ko call kiya hai outlet_id ke sath
        final response = await dio.get(
          '/sales/summary',
          queryParameters: {'period': 'yesterday', 'outlet_id': outletId},
        );

        final data = response.data;

        return {
          'revenue': data['total_sales'] ?? 0,
          'orders': data['total_bills'] ?? 0,
        };
      } catch (e) {
        debugPrint('🔴 [OUTLET_DASHBOARD] Exception: $e');
        throw e;
      }
    });

// ─── WEEKLY INSIGHTS PROVIDER (REAL DB DATA) ────────────────────────────────

final weeklyInsightsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    final outletId = ref.watch(selectedOutletIdProvider); // MULTI-OUTLET

    if (outletId == null) {
      throw Exception("No outlet assigned to this manager");
    }

    try {
      final dio = ref.read(dioProvider);

      final response = await dio.get(
        '/sales/vendor/history',
        queryParameters: {'outlet_id': outletId},
      );

      return response.data;
    } catch (e) {
      debugPrint('🔴 [WEEKLY_INSIGHTS] Exception: $e');
      throw e;
    }
  },
);

// ─── ROSTER PROVIDER (REAL DB DATA) ─────────────────────────────────────────

// Selected roster day for the manager view. null => today.
class SelectedRosterDateNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void setDate(DateTime? date) => state = date;
}

final selectedRosterDateProvider =
    NotifierProvider<SelectedRosterDateNotifier, DateTime?>(
      SelectedRosterDateNotifier.new,
    );

String _ymd(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

final dailyRosterProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final outletId = ref.watch(selectedOutletIdProvider); // MULTI-OUTLET

  if (outletId == null) throw Exception("No outlet assigned");

  // Refetches automatically whenever the selected date changes.
  final selectedDate = ref.watch(selectedRosterDateProvider);

  try {
    final dio = ref.read(dioProvider);
    final query = <String, dynamic>{'outlet_id': outletId};
    if (selectedDate != null) {
      query['target_date'] = _ymd(selectedDate);
    }
    final response = await dio.get('/roster/', queryParameters: query);

    return response.data;
  } catch (e) {
    debugPrint('🔴 [ROSTER] Exception: $e');
    throw e;
  }
});


// ─── ETL MANAGER COURT-WISE ROSTER ──────────────────────────────────────────

// Selected court filter for the ETL roster. null => all courts.
class SelectedRosterCourtNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void setCourt(int? courtId) => state = courtId;
}

final selectedRosterCourtProvider =
    NotifierProvider<SelectedRosterCourtNotifier, int?>(
      SelectedRosterCourtNotifier.new,
    );

final etlRosterProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  // Date + court filter dono pe auto-refetch hota hai.
  final selectedDate = ref.watch(selectedRosterDateProvider);
  final courtId = ref.watch(selectedRosterCourtProvider);

  try {
    final dio = ref.read(dioProvider);
    final query = <String, dynamic>{};
    if (selectedDate != null) query['target_date'] = _ymd(selectedDate);
    if (courtId != null) query['court_id'] = courtId;

    final response = await dio.get('/roster/etl', queryParameters: query);
    return Map<String, dynamic>.from(response.data as Map);
  } catch (e) {
    debugPrint('🔴 [ETL_ROSTER] Exception: $e');
    rethrow;
  }
});


// ─── CURRENT OUTLET NAME (real data, no hardcoding) ─────────────────────────

final currentOutletNameProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final outletId = ref.watch(selectedOutletIdProvider); // MULTI-OUTLET
  if (outletId == null) return null;

  try {
    final dio = ref.read(dioProvider);
    final res = await dio.get('/outlets/');
    final data = res.data;
    final List list = data is List
        ? data
        : (data is Map ? (data['outlets'] ?? data['data'] ?? []) : []);

    for (final o in list) {
      if (o is Map && o['id'] == outletId) {
        final name = (o['vendor_name'] ?? o['name'])?.toString();
        return (name != null && name.isNotEmpty) ? name : null;
      }
    }
    return null;
  } catch (e) {
    debugPrint('🏪 [OUTLET_NAME] Exception: $e');
    return null;
  }
});
