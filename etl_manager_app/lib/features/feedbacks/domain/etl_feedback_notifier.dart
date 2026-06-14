// lib/features/feedbacks/domain/etl_feedback_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// ✅ FIX: JWT wala dio
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_notifier.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class SimpleCourt {
  final int id;
  final String name;
  SimpleCourt({required this.id, required this.name});

  factory SimpleCourt.fromJson(Map<String, dynamic> json) => SimpleCourt(
    id: json['id'] ?? json['court_id'] ?? 0,
    name: json['name'] ?? json['court_name'] ?? 'Unknown Court',
  );
}

class SimpleOutlet {
  final int id;
  final String name;
  final int courtId;
  SimpleOutlet({required this.id, required this.name, required this.courtId});

  factory SimpleOutlet.fromJson(Map<String, dynamic> json) => SimpleOutlet(
    id: json['id'] ?? json['outlet_id'] ?? 0,
    name:
        json['vendor_name'] ??
        json['name'] ??
        json['outlet_name'] ??
        'Unknown Outlet',
    courtId: json['court_id'] ?? 0,
  );
}

class EtlFeedbackModel {
  final int id;
  final int courtId;
  final int? outletId;
  final String customerName;
  final String customerPhoneMasked; // ✅ Masked
  final int? courtRating;
  final String? courtComments;
  final int? outletRating;
  final String? outletComments;
  final String source;
  final DateTime createdAt;

  EtlFeedbackModel({
    required this.id,
    required this.courtId,
    this.outletId,
    required this.customerName,
    required this.customerPhoneMasked,
    this.courtRating,
    this.courtComments,
    this.outletRating,
    this.outletComments,
    required this.source,
    required this.createdAt,
  });

  factory EtlFeedbackModel.fromJson(Map<String, dynamic> json) {
    return EtlFeedbackModel(
      id: json['id'] ?? 0,
      courtId: json['court_id'] ?? 0,
      outletId: json['outlet_id'],
      customerName: json['customer_name'] ?? 'Unknown',
      // ✅ FIX: New masked field
      customerPhoneMasked: json['customer_phone_masked'] ?? '***',
      courtRating: json['court_rating'],
      courtComments: json['court_comments'],
      outletRating: json['outlet_rating'],
      outletComments: json['outlet_comments'],
      source: json['source'] ?? 'qr',
      // ✅ FIX: 'Z' suffix se toLocal() sahi kaam karega
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
    );
  }

  bool get hasCourtFeedback => courtRating != null;
  bool get hasOutletFeedback => outletRating != null;
}

class EtlFeedbackAnalytics {
  final int totalCount;
  final double? avgCourtRating;
  final double? avgOutletRating;
  final int fiveStarCount;
  final int oneStarCount;
  final int thisWeekCount;
  final int lastWeekCount;

  EtlFeedbackAnalytics({
    required this.totalCount,
    this.avgCourtRating,
    this.avgOutletRating,
    required this.fiveStarCount,
    required this.oneStarCount,
    required this.thisWeekCount,
    required this.lastWeekCount,
  });

  factory EtlFeedbackAnalytics.fromJson(Map<String, dynamic> json) {
    return EtlFeedbackAnalytics(
      totalCount: json['total_count'] ?? 0,
      avgCourtRating: json['avg_court_rating'] != null
          ? (json['avg_court_rating'] as num).toDouble()
          : null,
      avgOutletRating: json['avg_outlet_rating'] != null
          ? (json['avg_outlet_rating'] as num).toDouble()
          : null,
      fiveStarCount: json['five_star_count'] ?? 0,
      oneStarCount: json['one_star_count'] ?? 0,
      thisWeekCount: json['this_week_count'] ?? 0,
      lastWeekCount: json['last_week_count'] ?? 0,
    );
  }

  double get wowGrowth {
    if (lastWeekCount == 0) return thisWeekCount > 0 ? 100.0 : 0.0;
    return ((thisWeekCount - lastWeekCount) / lastWeekCount) * 100;
  }

  bool get isGrowing => wowGrowth >= 0;
}

// ─── State ───────────────────────────────────────────────────────────────────

class EtlFeedbackData {
  final List<EtlFeedbackModel> allFeedbacks;
  final List<EtlFeedbackModel> displayedFeedbacks;
  final EtlFeedbackAnalytics? analytics;
  final List<SimpleCourt> courts;
  final List<SimpleOutlet> outlets;
  final int? selectedCourtId;
  final int? selectedOutletId;
  final DateTime? selectedDate;

  EtlFeedbackData({
    required this.allFeedbacks,
    required this.displayedFeedbacks,
    this.analytics,
    required this.courts,
    required this.outlets,
    this.selectedCourtId,
    this.selectedOutletId,
    this.selectedDate,
  });

  EtlFeedbackData copyWith({
    List<EtlFeedbackModel>? allFeedbacks,
    List<EtlFeedbackModel>? displayedFeedbacks,
    EtlFeedbackAnalytics? analytics,
    List<SimpleCourt>? courts,
    List<SimpleOutlet>? outlets,
    int? selectedCourtId,
    bool clearCourt = false,
    int? selectedOutletId,
    bool clearOutlet = false,
    DateTime? selectedDate,
    bool clearDate = false,
  }) {
    return EtlFeedbackData(
      allFeedbacks: allFeedbacks ?? this.allFeedbacks,
      displayedFeedbacks: displayedFeedbacks ?? this.displayedFeedbacks,
      analytics: analytics ?? this.analytics,
      courts: courts ?? this.courts,
      outlets: outlets ?? this.outlets,
      selectedCourtId: clearCourt
          ? null
          : (selectedCourtId ?? this.selectedCourtId),
      selectedOutletId: clearOutlet
          ? null
          : (selectedOutletId ?? this.selectedOutletId),
      selectedDate: clearDate ? null : (selectedDate ?? this.selectedDate),
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class EtlFeedbackNotifier extends Notifier<AsyncValue<EtlFeedbackData>> {
  @override
  AsyncValue<EtlFeedbackData> build() {
    Future.microtask(() => fetchEtlData());
    return const AsyncValue.loading();
  }

  Future<void> fetchEtlData({bool isRefresh = false}) async {
    if (!isRefresh || !state.hasValue) {
      state = const AsyncValue.loading();
    }

    try {
      final dio = ref.read(dioProvider); // ✅ JWT wala dio
      final authState = ref.read(authNotifierProvider);

      if (!authState.isEtlManager) {
        state = AsyncValue.error(
          "ETL manager access required.",
          StackTrace.current,
        );
        return;
      }

      // ✅ Parallel fetch: feedbacks + analytics + courts + outlets
      final results = await Future.wait([
        dio.get('/feedback/all'),
        dio.get('/feedback/all/analytics'),
        dio.get('/courts/'),
        dio.get('/outlets/'),
      ]);

      // Feedbacks
      final feedbacksList = (results[0].data as List? ?? [])
          .map((e) => EtlFeedbackModel.fromJson(e as Map<String, dynamic>))
          .toList();
      feedbacksList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Analytics
      final analytics = EtlFeedbackAnalytics.fromJson(
        results[1].data as Map<String, dynamic>,
      );

      // Courts
      List<SimpleCourt> courtsList = [];
      final courtsRaw = results[2].data;
      List cList = [];
      if (courtsRaw is List) {
        cList = courtsRaw;
      } else if (courtsRaw is Map) {
        cList = courtsRaw['courts'] ?? courtsRaw['data'] ?? [];
      }
      courtsList = cList
          .map((e) => SimpleCourt.fromJson(e as Map<String, dynamic>))
          .toList();

      // Outlets
      List<SimpleOutlet> outletsList = [];
      final outletsRaw = results[3].data;
      List oList = [];
      if (outletsRaw is List) {
        oList = outletsRaw;
      } else if (outletsRaw is Map) {
        oList = outletsRaw['outlets'] ?? outletsRaw['data'] ?? [];
      }
      outletsList = oList
          .map((e) => SimpleOutlet.fromJson(e as Map<String, dynamic>))
          .toList();

      // Preserve existing filters
      final prev = state.value;
      final newData = EtlFeedbackData(
        allFeedbacks: feedbacksList,
        displayedFeedbacks: feedbacksList,
        analytics: analytics,
        courts: courtsList,
        outlets: outletsList,
        selectedCourtId: prev?.selectedCourtId,
        selectedOutletId: prev?.selectedOutletId,
        selectedDate: prev?.selectedDate,
      );

      state = AsyncValue.data(newData);
      _applyFilters();
    } on DioException catch (e) {
      final msg = _friendlyError(e);
      if (state.hasValue) return;
      state = AsyncValue.error(msg, StackTrace.current);
    } catch (e, st) {
      if (state.hasValue) return;
      state = AsyncValue.error(e, st);
    }
  }

  // ─── Filters ─────────────────────────────────────────────────────────────

  void setCourtFilter(int? courtId) {
    if (state.value == null) return;
    state = AsyncValue.data(
      state.value!.copyWith(
        selectedCourtId: courtId,
        clearCourt: courtId == null,
        // ✅ Court change hone pe outlet filter reset
        selectedOutletId: null,
        clearOutlet: true,
      ),
    );
    _applyFilters();
  }

  void setOutletFilter(int? outletId) {
    if (state.value == null) return;
    state = AsyncValue.data(
      state.value!.copyWith(
        selectedOutletId: outletId,
        clearOutlet: outletId == null,
      ),
    );
    _applyFilters();
  }

  void setDateFilter(DateTime? date) {
    if (state.value == null) return;
    state = AsyncValue.data(
      state.value!.copyWith(selectedDate: date, clearDate: date == null),
    );
    _applyFilters();
  }

  void _applyFilters() {
    final current = state.value;
    if (current == null) return;

    final filtered = current.allFeedbacks.where((f) {
      // Court filter
      if (current.selectedCourtId != null &&
          f.courtId != current.selectedCourtId)
        return false;
      // Outlet filter
      if (current.selectedOutletId != null &&
          f.outletId != current.selectedOutletId)
        return false;
      // Date filter
      if (current.selectedDate != null) {
        final d = current.selectedDate!;
        if (f.createdAt.year != d.year ||
            f.createdAt.month != d.month ||
            f.createdAt.day != d.day)
          return false;
      }
      return true;
    }).toList();

    state = AsyncValue.data(current.copyWith(displayedFeedbacks: filtered));
  }

  String _friendlyError(DioException e) {
    if (e.response?.statusCode == 401)
      return 'Session expired. Please log in again.';
    if (e.response?.statusCode == 403) return 'ETL manager access required.';
    if (e.type == DioExceptionType.connectionError)
      return 'Cannot reach server. Check your internet.';
    return 'Failed to load feedbacks. Pull to refresh.';
  }
}

final etlFeedbackNotifierProvider =
    NotifierProvider<EtlFeedbackNotifier, AsyncValue<EtlFeedbackData>>(
      EtlFeedbackNotifier.new,
    );
