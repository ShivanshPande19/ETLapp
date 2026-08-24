import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notices_repository.dart';
import 'notice_model.dart';

/// State for the notices screen: a single IST day at a time, paginated.
class NoticesState {
  final List<NoticeModel> notices;
  final int unreadCount; // TOTAL unread in scope (all days) — for the badge
  final bool hasMore;
  final DateTime selectedDate; // the IST day being viewed (date-only)
  final bool loading; // initial / date-switch load
  final bool loadingMore; // pagination append
  final Object? error;

  const NoticesState({
    this.notices = const [],
    this.unreadCount = 0,
    this.hasMore = false,
    required this.selectedDate,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  NoticesState copyWith({
    List<NoticeModel>? notices,
    int? unreadCount,
    bool? hasMore,
    DateTime? selectedDate,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return NoticesState(
      notices: notices ?? this.notices,
      unreadCount: unreadCount ?? this.unreadCount,
      hasMore: hasMore ?? this.hasMore,
      selectedDate: selectedDate ?? this.selectedDate,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NoticesNotifier extends Notifier<NoticesState> {
  static const int _pageSize = 30;

  @override
  NoticesState build() {
    final today = _dateOnly(DateTime.now());
    Future.microtask(() => _load(today, reset: true));
    return NoticesState(selectedDate: today, loading: true);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  bool get isToday {
    final t = _dateOnly(DateTime.now());
    final s = state.selectedDate;
    return s.year == t.year && s.month == t.month && s.day == t.day;
  }

  Future<void> _load(DateTime date, {required bool reset}) async {
    state = state.copyWith(
      selectedDate: date,
      loading: reset,
      clearError: true,
    );
    try {
      final res = await ref.read(noticesRepositoryProvider).getNotices(
            date: _fmt(date),
            limit: _pageSize,
            offset: 0,
          );
      state = state.copyWith(
        notices: res.notices,
        unreadCount: res.unreadCount,
        hasMore: res.hasMore,
        loading: false,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, loadingMore: false, error: e);
    }
  }

  /// Pull-to-refresh / re-fetch the current day.
  Future<void> refresh() => _load(state.selectedDate, reset: true);

  /// Switch to a different IST day (from the date picker).
  Future<void> selectDate(DateTime date) => _load(_dateOnly(date), reset: true);

  /// Jump back to today.
  Future<void> goToToday() => _load(_dateOnly(DateTime.now()), reset: true);

  /// Append the next page for the current day.
  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final res = await ref.read(noticesRepositoryProvider).getNotices(
            date: _fmt(state.selectedDate),
            limit: _pageSize,
            offset: state.notices.length,
          );
      state = state.copyWith(
        notices: [...state.notices, ...res.notices],
        unreadCount: res.unreadCount,
        hasMore: res.hasMore,
        loadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(loadingMore: false);
    }
  }

  /// Called when the inbox opens: clears the unread count + app badge server
  /// side WITHOUT re-fetching, so the red highlights stay visible for this
  /// viewing session but the user never has to tap to "mark read".
  Future<void> markAllReadSilently() async {
    if (state.unreadCount == 0) return;
    try {
      await ref.read(noticesRepositoryProvider).markAllRead();
    } catch (_) {
      // best-effort — a failed clear must not break the screen
    }
    state = state.copyWith(unreadCount: 0);
    ref.invalidate(unreadCountProvider);
  }
}

final noticesNotifierProvider =
    NotifierProvider<NoticesNotifier, NoticesState>(NoticesNotifier.new);

/// Lightweight unread-count for the home bell badge (auto-refreshed on demand).
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(noticesRepositoryProvider).unreadCount();
});
