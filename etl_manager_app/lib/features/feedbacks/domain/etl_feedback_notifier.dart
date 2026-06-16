// lib/features/feedbacks/domain/etl_feedback_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// ✅ JWT wala dio
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
      customerPhoneMasked: json['customer_phone_masked'] ?? '***',
      courtRating: json['court_rating'],
      courtComments: json['court_comments'],
      outletRating: json['outlet_rating'],
      outletComments: json['outlet_comments'],
      source: json['source'] ?? 'qr',
      // ✅ Backend ab 'Z' suffix bhejta hai — toLocal() sahi kaam karega
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
  // Accumulated, paginated list of feedbacks currently loaded.
  final List<EtlFeedbackModel> feedbacks;
  // Analytics now comes straight from the server, computed over the SAME
  // filters as the list (no more local recompute over a partial page).
  final EtlFeedbackAnalytics? analytics;
  final List<SimpleCourt> courts;
  final List<SimpleOutlet> outlets;
  final int? selectedCourtId;
  final int? selectedOutletId;
  final DateTime? selectedDate;

  // Pagination flags.
  final bool hasMore;
  final bool isLoadingMore;

  EtlFeedbackData({
    required this.feedbacks,
    this.analytics,
    required this.courts,
    required this.outlets,
    this.selectedCourtId,
    this.selectedOutletId,
    this.selectedDate,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  EtlFeedbackData copyWith({
    List<EtlFeedbackModel>? feedbacks,
    EtlFeedbackAnalytics? analytics,
    List<SimpleCourt>? courts,
    List<SimpleOutlet>? outlets,
    int? selectedCourtId,
    bool clearCourt = false,
    int? selectedOutletId,
    bool clearOutlet = false,
    DateTime? selectedDate,
    bool clearDate = false,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return EtlFeedbackData(
      feedbacks: feedbacks ?? this.feedbacks,
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
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class EtlFeedbackNotifier extends Notifier<AsyncValue<EtlFeedbackData>> {
  // Page size — keep in sync with backend default `limit`.
  static const int _pageSize = 20;

  @override
  AsyncValue<EtlFeedbackData> build() {
    Future.microtask(() => fetchEtlData());
    return const AsyncValue.loading();
  }

  bool get _isEtl => ref.read(authNotifierProvider).isEtlManager;

  // Builds the server-side filter params from the given selections.
  Map<String, dynamic> _filterParams({
    int? courtId,
    int? outletId,
    DateTime? date,
  }) {
    final params = <String, dynamic>{};
    if (courtId != null) params['court_id'] = courtId;
    if (outletId != null) params['outlet_id'] = outletId;
    if (date != null) {
      final localStart = DateTime(date.year, date.month, date.day);
      final localEnd = localStart.add(const Duration(days: 1));
      params['start'] = localStart.toUtc().toIso8601String();
      params['end'] = localEnd.toUtc().toIso8601String();
    }
    return params;
  }

  // Fetches a single page of feedbacks honouring the active filters.
  Future<List<EtlFeedbackModel>> _fetchPage({
    required int offset,
    int? courtId,
    int? outletId,
    DateTime? date,
  }) async {
    final dio = ref.read(dioProvider);
    final query = <String, dynamic>{
      'limit': _pageSize,
      'offset': offset,
      ..._filterParams(courtId: courtId, outletId: outletId, date: date),
    };
    final res = await dio.get('/feedback/all', queryParameters: query);
    return (res.data as List? ?? [])
        .map((e) => EtlFeedbackModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Fetches analytics for the active filters.
  Future<EtlFeedbackAnalytics> _fetchAnalytics({
    int? courtId,
    int? outletId,
    DateTime? date,
  }) async {
    final dio = ref.read(dioProvider);
    final res = await dio.get(
      '/feedback/all/analytics',
      queryParameters: _filterParams(
        courtId: courtId,
        outletId: outletId,
        date: date,
      ),
    );
    return EtlFeedbackAnalytics.fromJson(res.data as Map<String, dynamic>);
  }

  List<T> _parseList<T>(
    dynamic raw,
    List<String> mapKeys,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    List list = [];
    if (raw is List) {
      list = raw;
    } else if (raw is Map) {
      for (final k in mapKeys) {
        if (raw[k] is List) {
          list = raw[k];
          break;
        }
      }
    }
    return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }

  // Full load: courts + outlets + first page + analytics (current filters).
  Future<void> fetchEtlData({bool isRefresh = false}) async {
    if (!isRefresh || !state.hasValue) {
      state = const AsyncValue.loading();
    }

    try {
      if (!_isEtl) {
        if (state.hasValue) return;
        state = AsyncValue.error(
          "ETL manager access required.",
          StackTrace.current,
        );
        return;
      }

      // Preserve any active filters across a refresh.
      final prev = state.value;
      final courtId = prev?.selectedCourtId;
      final outletId = prev?.selectedOutletId;
      final date = prev?.selectedDate;

      final dio = ref.read(dioProvider);

      final results = await Future.wait([
        _fetchPage(offset: 0, courtId: courtId, outletId: outletId, date: date),
        _fetchAnalytics(courtId: courtId, outletId: outletId, date: date),
        dio.get('/courts/'),
        dio.get('/outlets/'),
      ]);

      final firstPage = results[0] as List<EtlFeedbackModel>;
      final analytics = results[1] as EtlFeedbackAnalytics;
      final courts = _parseList(
        (results[2] as Response).data,
        ['courts', 'data'],
        SimpleCourt.fromJson,
      );
      final outlets = _parseList(
        (results[3] as Response).data,
        ['outlets', 'data'],
        SimpleOutlet.fromJson,
      );

      state = AsyncValue.data(
        EtlFeedbackData(
          feedbacks: firstPage,
          analytics: analytics,
          courts: courts,
          outlets: outlets,
          selectedCourtId: courtId,
          selectedOutletId: outletId,
          selectedDate: date,
          hasMore: firstPage.length == _pageSize,
          isLoadingMore: false,
        ),
      );
    } on DioException catch (e) {
      final msg = _friendlyError(e);
      if (state.hasValue) return;
      state = AsyncValue.error(msg, StackTrace.current);
    } catch (e, st) {
      if (state.hasValue) return;
      state = AsyncValue.error(e, st);
    }
  }

  // Reloads the first page + analytics for the current filters (after a filter
  // change). Reuses the already-loaded courts/outlets lists.
  Future<void> _reloadForFilters() async {
    final current = state.value;
    if (current == null || !_isEtl) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final results = await Future.wait([
        _fetchPage(
          offset: 0,
          courtId: current.selectedCourtId,
          outletId: current.selectedOutletId,
          date: current.selectedDate,
        ),
        _fetchAnalytics(
          courtId: current.selectedCourtId,
          outletId: current.selectedOutletId,
          date: current.selectedDate,
        ),
      ]);

      final firstPage = results[0] as List<EtlFeedbackModel>;
      final analytics = results[1] as EtlFeedbackAnalytics;

      final latest = state.value;
      if (latest == null) return;

      state = AsyncValue.data(
        latest.copyWith(
          feedbacks: firstPage,
          analytics: analytics,
          hasMore: firstPage.length == _pageSize,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      final latest = state.value;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(isLoadingMore: false));
      }
    }
  }

  // Loads the next page and appends it (infinite scroll).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) return;
    if (!current.hasMore || current.isLoadingMore) return;
    if (!_isEtl) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final nextPage = await _fetchPage(
        offset: current.feedbacks.length,
        courtId: current.selectedCourtId,
        outletId: current.selectedOutletId,
        date: current.selectedDate,
      );

      final latest = state.value;
      if (latest == null) return;

      state = AsyncValue.data(
        latest.copyWith(
          feedbacks: [...latest.feedbacks, ...nextPage],
          hasMore: nextPage.length == _pageSize,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      final latest = state.value;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(isLoadingMore: false));
      }
    }
  }

  // ─── Filters (all reload from the server) ──────────────────────────────────

  void setCourtFilter(int? courtId) {
    if (state.value == null) return;
    state = AsyncValue.data(
      state.value!.copyWith(
        selectedCourtId: courtId,
        clearCourt: courtId == null,
        // Court change hone pe outlet filter reset.
        selectedOutletId: null,
        clearOutlet: true,
      ),
    );
    _reloadForFilters();
  }

  void setOutletFilter(int? outletId) {
    if (state.value == null) return;
    state = AsyncValue.data(
      state.value!.copyWith(
        selectedOutletId: outletId,
        clearOutlet: outletId == null,
      ),
    );
    _reloadForFilters();
  }

  void setDateFilter(DateTime? date) {
    if (state.value == null) return;
    state = AsyncValue.data(
      state.value!.copyWith(selectedDate: date, clearDate: date == null),
    );
    _reloadForFilters();
  }

  String _friendlyError(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Session expired. Please log in again.';
    }
    if (e.response?.statusCode == 403) return 'ETL manager access required.';
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot reach server. Check your internet.';
    }
    return 'Failed to load feedbacks. Pull to refresh.';
  }
}

final etlFeedbackNotifierProvider =
    NotifierProvider<EtlFeedbackNotifier, AsyncValue<EtlFeedbackData>>(
      EtlFeedbackNotifier.new,
    );
