// lib/features/feedbacks/domain/feedback_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// ✅ FIX: JWT wala dio (pehle app/dio_provider.dart tha jo token nahi bhejta)
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_notifier.dart';

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

  FeedbackAnalytics({
    required this.totalCount,
    this.avgOutletRating,
    required this.fiveStarCount,
    required this.oneStarCount,
    required this.thisWeekCount,
    required this.lastWeekCount,
  });

  factory FeedbackAnalytics.fromJson(Map<String, dynamic> json) {
    return FeedbackAnalytics(
      totalCount: json['total_count'] ?? 0,
      avgOutletRating: json['avg_outlet_rating'] != null
          ? (json['avg_outlet_rating'] as num).toDouble()
          : null,
      fiveStarCount: json['five_star_count'] ?? 0,
      oneStarCount: json['one_star_count'] ?? 0,
      thisWeekCount: json['this_week_count'] ?? 0,
      lastWeekCount: json['last_week_count'] ?? 0,
    );
  }

  // Week-over-week growth
  double get wowGrowth {
    if (lastWeekCount == 0) return thisWeekCount > 0 ? 100.0 : 0.0;
    return ((thisWeekCount - lastWeekCount) / lastWeekCount) * 100;
  }

  bool get isGrowing => wowGrowth >= 0;
}

// ─── State ───────────────────────────────────────────────────────────────────

class FeedbackData {
  final List<FeedbackModel> allFeedbacks;
  final List<FeedbackModel> displayedFeedbacks;
  final FeedbackAnalytics? analytics;
  final DateTime? selectedDate;
  final bool isLoadingAnalytics;

  FeedbackData({
    required this.allFeedbacks,
    required this.displayedFeedbacks,
    this.analytics,
    this.selectedDate,
    this.isLoadingAnalytics = false,
  });

  FeedbackData copyWith({
    List<FeedbackModel>? allFeedbacks,
    List<FeedbackModel>? displayedFeedbacks,
    FeedbackAnalytics? analytics,
    DateTime? selectedDate,
    bool clearDate = false,
    bool? isLoadingAnalytics,
  }) {
    return FeedbackData(
      allFeedbacks: allFeedbacks ?? this.allFeedbacks,
      displayedFeedbacks: displayedFeedbacks ?? this.displayedFeedbacks,
      analytics: analytics ?? this.analytics,
      selectedDate: clearDate ? null : (selectedDate ?? this.selectedDate),
      isLoadingAnalytics: isLoadingAnalytics ?? this.isLoadingAnalytics,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class FeedbackNotifier extends Notifier<AsyncValue<FeedbackData>> {
  @override
  AsyncValue<FeedbackData> build() {
    Future.microtask(() => fetchFeedbacks());
    return const AsyncValue.loading();
  }

  Future<void> fetchFeedbacks({bool isRefresh = false}) async {
    if (!isRefresh || !state.hasValue) {
      state = const AsyncValue.loading();
    }

    try {
      final dio = ref.read(dioProvider); // ✅ JWT wala dio
      final authState = ref.read(authNotifierProvider);

      final canView = authState.isOutletManager || authState.isOutletStaff;
      final outletId = canView ? authState.outletId : null;

      if (outletId == null) {
        state = AsyncValue.error(
          "No outlet assigned to your account.",
          StackTrace.current,
        );
        return;
      }

      // ✅ Feedbacks + Analytics parallel fetch
      final results = await Future.wait([
        dio.get('/feedback/outlet/$outletId'),
        dio.get('/feedback/outlet/$outletId/analytics'),
      ]);

      final feedbackRes = results[0];
      final analyticsRes = results[1];

      final feedbacksList = (feedbackRes.data as List)
          .map((e) => FeedbackModel.fromJson(e as Map<String, dynamic>))
          .toList();

      feedbacksList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final analytics = FeedbackAnalytics.fromJson(
        analyticsRes.data as Map<String, dynamic>,
      );

      final previousDate = state.value?.selectedDate;

      final data = FeedbackData(
        allFeedbacks: feedbacksList,
        displayedFeedbacks: feedbacksList,
        analytics: analytics,
        selectedDate: previousDate,
      );

      state = AsyncValue.data(data);

      // Re-apply date filter if was active
      if (previousDate != null) {
        setDateFilter(previousDate);
      }
    } on DioException catch (e) {
      final msg = _friendlyError(e);
      if (state.hasValue) return;
      state = AsyncValue.error(msg, StackTrace.current);
    } catch (e, st) {
      if (state.hasValue) return;
      state = AsyncValue.error(e, st);
    }
  }

  void setDateFilter(DateTime? date) {
    if (state.value == null) return;
    final current = state.value!;

    if (date == null) {
      state = AsyncValue.data(
        current.copyWith(
          displayedFeedbacks: current.allFeedbacks,
          clearDate: true,
        ),
      );
      return;
    }

    final filtered = current.allFeedbacks.where((f) {
      return f.createdAt.year == date.year &&
          f.createdAt.month == date.month &&
          f.createdAt.day == date.day;
    }).toList();

    state = AsyncValue.data(
      current.copyWith(displayedFeedbacks: filtered, selectedDate: date),
    );
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
