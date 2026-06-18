// lib/features/feedbacks/domain/court_feedback_notifier.dart
//
// Court-level feedback for the logged-in ETL staff's assigned court.
// Backed by /feedback/my-court (+ /analytics) — these only return feedbacks
// that carry a COURT rating, so staff see the venue voice (never outlet-only
// reviews).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_notifier.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class CourtFeedbackModel {
  final int id;
  final int courtId;
  final String customerName;
  final String customerPhoneMasked;
  final int? courtRating;
  final String? courtComments;
  final String source;
  final DateTime createdAt;

  CourtFeedbackModel({
    required this.id,
    required this.courtId,
    required this.customerName,
    required this.customerPhoneMasked,
    this.courtRating,
    this.courtComments,
    required this.source,
    required this.createdAt,
  });

  factory CourtFeedbackModel.fromJson(Map<String, dynamic> json) {
    return CourtFeedbackModel(
      id: json['id'] ?? 0,
      courtId: json['court_id'] ?? 0,
      customerName: json['customer_name'] ?? 'Guest',
      customerPhoneMasked: json['customer_phone_masked'] ?? '***',
      courtRating: json['court_rating'],
      courtComments: json['court_comments'],
      source: json['source'] ?? 'qr',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString()).toLocal()
          : DateTime.now(),
    );
  }

  bool get hasComment =>
      courtComments != null && courtComments!.trim().isNotEmpty;
}

class CourtFeedbackAnalytics {
  final int totalCount;
  final double? avgCourtRating;
  final int fiveStarCount;
  final int oneStarCount;
  final int thisWeekCount;
  final int lastWeekCount;

  CourtFeedbackAnalytics({
    required this.totalCount,
    this.avgCourtRating,
    required this.fiveStarCount,
    required this.oneStarCount,
    required this.thisWeekCount,
    required this.lastWeekCount,
  });

  factory CourtFeedbackAnalytics.fromJson(Map<String, dynamic> json) {
    return CourtFeedbackAnalytics(
      totalCount: json['total_count'] ?? 0,
      avgCourtRating: json['avg_court_rating'] != null
          ? (json['avg_court_rating'] as num).toDouble()
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

class CourtFeedbackData {
  final List<CourtFeedbackModel> feedbacks;
  final CourtFeedbackAnalytics? analytics;
  final bool hasMore;
  final bool isLoadingMore;

  CourtFeedbackData({
    required this.feedbacks,
    this.analytics,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  CourtFeedbackData copyWith({
    List<CourtFeedbackModel>? feedbacks,
    CourtFeedbackAnalytics? analytics,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return CourtFeedbackData(
      feedbacks: feedbacks ?? this.feedbacks,
      analytics: analytics ?? this.analytics,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class CourtFeedbackNotifier extends Notifier<AsyncValue<CourtFeedbackData>> {
  static const int _pageSize = 20;

  @override
  AsyncValue<CourtFeedbackData> build() {
    Future.microtask(() => fetch());
    return const AsyncValue.loading();
  }

  bool get _canView {
    final auth = ref.read(authNotifierProvider);
    return auth.isEtlStaff || auth.isEtlManager;
  }

  Future<List<CourtFeedbackModel>> _fetchPage(int offset) async {
    final dio = ref.read(dioProvider);
    final res = await dio.get(
      '/feedback/my-court',
      queryParameters: {'limit': _pageSize, 'offset': offset},
    );
    return (res.data as List? ?? [])
        .map((e) => CourtFeedbackModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> fetch({bool isRefresh = false}) async {
    if (!isRefresh || !state.hasValue) {
      state = const AsyncValue.loading();
    }

    try {
      if (!_canView) {
        if (state.hasValue) return;
        state = AsyncValue.error(
          'Court staff access required.',
          StackTrace.current,
        );
        return;
      }

      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        _fetchPage(0),
        dio.get('/feedback/my-court/analytics'),
      ]);

      final firstPage = results[0] as List<CourtFeedbackModel>;
      final analytics = CourtFeedbackAnalytics.fromJson(
        (results[1] as Response).data as Map<String, dynamic>,
      );

      state = AsyncValue.data(
        CourtFeedbackData(
          feedbacks: firstPage,
          analytics: analytics,
          hasMore: firstPage.length == _pageSize,
          isLoadingMore: false,
        ),
      );
    } on DioException catch (e) {
      if (state.hasValue) return;
      state = AsyncValue.error(_friendlyError(e), StackTrace.current);
    } catch (e, st) {
      if (state.hasValue) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) return;
    if (!current.hasMore || current.isLoadingMore) return;
    if (!_canView) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final nextPage = await _fetchPage(current.feedbacks.length);
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

  String _friendlyError(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Session expired. Please log in again.';
    }
    if (e.response?.statusCode == 403) {
      return 'No court assigned to your account.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot reach server. Check your internet.';
    }
    return 'Failed to load feedback. Pull to refresh.';
  }
}

final courtFeedbackNotifierProvider =
    NotifierProvider<CourtFeedbackNotifier, AsyncValue<CourtFeedbackData>>(
      CourtFeedbackNotifier.new,
    );
