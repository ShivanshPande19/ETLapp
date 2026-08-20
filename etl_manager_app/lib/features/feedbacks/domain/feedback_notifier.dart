// lib/features/feedbacks/domain/feedback_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// ✅ FIX: JWT wala dio (pehle app/dio_provider.dart tha jo token nahi bhejta)
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../outlets/domain/outlet_providers.dart'; // multi-outlet: selected outlet

// ─── Data Model ──────────────────────────────────────────────────────────────

class FeedbackModel {
  final int id;
  final String customerName;
  final String customerPhoneMasked; // ✅ Backend ab masked bhejta hai
  final int? outletRating;
  final String? outletComments;
  final DateTime createdAt;

  FeedbackModel({
    required this.id,
    required this.customerName,
    required this.customerPhoneMasked,
    this.outletRating,
    this.outletComments,
    required this.createdAt,
  });

  factory FeedbackModel.fromJson(Map<String, dynamic> json) {
    return FeedbackModel(
      id: json['id'] ?? 0,
      customerName: json['customer_name'] ?? 'Unknown',
      // ✅ FIX: New field name from backend
      customerPhoneMasked: json['customer_phone_masked'] ?? '***',
      outletRating: json['outlet_rating'],
      outletComments: json['outlet_comments'],
      // ✅ FIX: Backend ab 'Z' suffix bhejta hai — toLocal() sahi kaam karega
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
    );
  }
}

// ─── Analytics Model ─────────────────────────────────────────────────────────

class FeedbackAnalytics {
  final int totalCount;
  final double? avgOutletRating;
  final int fiveStarCount;
  final int oneStarCount;
  final int thisWeekCount;
  final int lastWeekCount;

  // ✅ Per-star distribution of outlet ratings: index 0 => 1★ ... index 4 => 5★.
  // Backend computes this over ALL feedbacks, so the home screen stays accurate
  // even though the list itself is paginated.
  final List<int> ratingDistribution;

  FeedbackAnalytics({
    required this.totalCount,
    this.avgOutletRating,
    required this.fiveStarCount,
    required this.oneStarCount,
    required this.thisWeekCount,
    required this.lastWeekCount,
    required this.ratingDistribution,
  });

  factory FeedbackAnalytics.fromJson(Map<String, dynamic> json) {
    // Defensive parse: always end up with exactly 5 buckets.
    final rawDist = json['rating_distribution'];
    final dist = List<int>.filled(5, 0);
    if (rawDist is List) {
      for (var i = 0; i < 5 && i < rawDist.length; i++) {
        dist[i] = (rawDist[i] as num?)?.toInt() ?? 0;
      }
    }

    return FeedbackAnalytics(
      totalCount: json['total_count'] ?? 0,
      avgOutletRating: json['avg_outlet_rating'] != null
          ? (json['avg_outlet_rating'] as num).toDouble()
          : null,
      fiveStarCount: json['five_star_count'] ?? 0,
      oneStarCount: json['one_star_count'] ?? 0,
      thisWeekCount: json['this_week_count'] ?? 0,
      lastWeekCount: json['last_week_count'] ?? 0,
      ratingDistribution: dist,
    );
  }

  // Total number of rated outlet reviews (sum of distribution buckets).
  int get ratedCount => ratingDistribution.fold(0, (a, b) => a + b);

  // Reviews that need attention (1★ + 2★).
  int get needsAttentionCount => ratingDistribution[0] + ratingDistribution[1];

  // Happy customers (4★ + 5★).
  int get happyCount => ratingDistribution[3] + ratingDistribution[4];

  // Week-over-week growth
  double get wowGrowth {
    if (lastWeekCount == 0) return thisWeekCount > 0 ? 100.0 : 0.0;
    return ((thisWeekCount - lastWeekCount) / lastWeekCount) * 100;
  }

  bool get isGrowing => wowGrowth >= 0;
}

// ─── State ───────────────────────────────────────────────────────────────────

class FeedbackData {
  // Accumulated, paginated list of feedbacks currently loaded into the screen.
  final List<FeedbackModel> feedbacks;
  final FeedbackAnalytics? analytics;
  final DateTime? selectedDate;

  // Pagination flags.
  final bool hasMore; // server might still have older pages
  final bool isLoadingMore; // a loadMore() request is in flight

  FeedbackData({
    required this.feedbacks,
    this.analytics,
    this.selectedDate,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  FeedbackData copyWith({
    List<FeedbackModel>? feedbacks,
    FeedbackAnalytics? analytics,
    DateTime? selectedDate,
    bool clearDate = false,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return FeedbackData(
      feedbacks: feedbacks ?? this.feedbacks,
      analytics: analytics ?? this.analytics,
      selectedDate: clearDate ? null : (selectedDate ?? this.selectedDate),
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class FeedbackNotifier extends Notifier<AsyncValue<FeedbackData>> {
  // Page size — keep in sync with backend default `limit`.
  static const int _pageSize = 20;

  @override
  AsyncValue<FeedbackData> build() {
    // MULTI-OUTLET: refetch when the owner switches outlet.
    ref.listen(selectedOutletIdProvider, (prev, next) {
      if (prev != next) fetchFeedbacks(isRefresh: true);
    });
    Future.microtask(() => fetchFeedbacks());
    return const AsyncValue.loading();
  }

  // Resolves the outlet id for the logged-in user, or null if not allowed.
  // MULTI-OUTLET: follows the selected outlet (defaults to the primary one for
  // single-outlet owners and for staff).
  int? _resolveOutletId() {
    final authState = ref.read(authNotifierProvider);
    final canView = authState.isOutletManager || authState.isOutletStaff;
    return canView ? ref.read(selectedOutletIdProvider) : null;
  }

  // Converts a selected (local) calendar day into UTC ISO day-boundaries so the
  // backend can filter correctly regardless of the device timezone.
  Map<String, String> _dayRangeParams(DateTime date) {
    final localStart = DateTime(date.year, date.month, date.day);
    final localEnd = localStart.add(const Duration(days: 1));
    return {
      'start': localStart.toUtc().toIso8601String(),
      'end': localEnd.toUtc().toIso8601String(),
    };
  }

  // Fetches a single page of feedbacks from the server.
  Future<List<FeedbackModel>> _fetchPage({
    required int outletId,
    required int offset,
    DateTime? date,
  }) async {
    final dio = ref.read(dioProvider); // ✅ JWT wala dio

    final query = <String, dynamic>{'limit': _pageSize, 'offset': offset};
    if (date != null) query.addAll(_dayRangeParams(date));

    final res = await dio.get(
      '/feedback/outlet/$outletId',
      queryParameters: query,
    );

    return (res.data as List)
        .map((e) => FeedbackModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Initial load (and pull-to-refresh): first page + overall analytics.
  Future<void> fetchFeedbacks({bool isRefresh = false}) async {
    if (!isRefresh || !state.hasValue) {
      state = const AsyncValue.loading();
    }

    try {
      final outletId = _resolveOutletId();
      if (outletId == null) {
        if (state.hasValue) return;
        state = AsyncValue.error(
          "No outlet assigned to your account.",
          StackTrace.current,
        );
        return;
      }

      // Preserve any active date filter across a refresh.
      final selectedDate = state.value?.selectedDate;
      final dio = ref.read(dioProvider);

      // First page + analytics in parallel. Analytics is always overall
      // (not date-filtered), matching the previous behaviour.
      final results = await Future.wait([
        _fetchPage(outletId: outletId, offset: 0, date: selectedDate),
        dio.get('/feedback/outlet/$outletId/analytics'),
      ]);

      final firstPage = results[0] as List<FeedbackModel>;
      final analyticsRes = results[1] as Response;

      final analytics = FeedbackAnalytics.fromJson(
        analyticsRes.data as Map<String, dynamic>,
      );

      state = AsyncValue.data(
        FeedbackData(
          feedbacks: firstPage,
          analytics: analytics,
          selectedDate: selectedDate,
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

  // Loads the next page and appends it to the current list (infinite scroll).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) return;
    if (!current.hasMore || current.isLoadingMore) return;

    final outletId = _resolveOutletId();
    if (outletId == null) return;

    // Flag the in-flight request so the UI can show a bottom spinner and we
    // don't fire duplicate requests while scrolling.
    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final nextPage = await _fetchPage(
        outletId: outletId,
        offset: current.feedbacks.length,
        date: current.selectedDate,
      );

      // Guard against the state being replaced while we were awaiting.
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
      // On failure just clear the loading flag; user can scroll to retry.
      final latest = state.value;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(isLoadingMore: false));
      }
    }
  }

  // Server-side date filter: reloads the first page for the chosen day
  // (or clears the filter). Analytics stays overall and is left untouched.
  Future<void> setDateFilter(DateTime? date) async {
    final current = state.value;
    if (current == null) return;

    final outletId = _resolveOutletId();
    if (outletId == null) return;

    // Optimistically reflect the new filter + show the list as loading-more
    // so the screen can render a spinner without dropping the analytics card.
    state = AsyncValue.data(
      current.copyWith(
        selectedDate: date,
        clearDate: date == null,
        isLoadingMore: true,
      ),
    );

    try {
      final firstPage = await _fetchPage(
        outletId: outletId,
        offset: 0,
        date: date,
      );

      final latest = state.value;
      if (latest == null) return;

      state = AsyncValue.data(
        latest.copyWith(
          feedbacks: firstPage,
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

  String _friendlyError(DioException e) {
    if (e.response?.statusCode == 401)
      return 'Session expired. Please log in again.';
    if (e.response?.statusCode == 403)
      return 'You don\'t have permission to view feedbacks.';
    if (e.type == DioExceptionType.connectionError)
      return 'Cannot reach server. Check your internet.';
    return 'Failed to load feedbacks. Pull to refresh.';
  }
}

final feedbackNotifierProvider =
    NotifierProvider<FeedbackNotifier, AsyncValue<FeedbackData>>(
      FeedbackNotifier.new,
    );
