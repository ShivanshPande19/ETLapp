import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/notice_model.dart';

class NoticesResult {
  final List<NoticeModel> notices;
  final int unreadCount; // TOTAL unread in scope (drives the bell badge)
  final bool hasMore; // more rows exist beyond this page (for the current filter)
  const NoticesResult({
    required this.notices,
    required this.unreadCount,
    this.hasMore = false,
  });
}

class NoticesRepository {
  final Dio _dio;
  NoticesRepository(this._dio);

  /// [date] is an IST calendar day 'YYYY-MM-DD' (null = all days).
  Future<NoticesResult> getNotices({
    String? date,
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await _dio.get('/notices/', queryParameters: {
      if (date != null) 'date': date,
      'limit': limit,
      'offset': offset,
    });
    final data = res.data as Map<String, dynamic>;
    final list = (data['notices'] as List? ?? [])
        .map((e) => NoticeModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return NoticesResult(
      notices: list,
      unreadCount: (data['unread_count'] ?? 0) as int,
      hasMore: (data['has_more'] ?? false) as bool,
    );
  }

  Future<int> unreadCount() async {
    try {
      final res = await _dio.get('/notices/unread-count');
      return (res.data['unread_count'] ?? 0) as int;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markRead(int id) async {
    await _dio.patch('/notices/$id/read');
  }

  Future<void> markAllRead() async {
    await _dio.patch('/notices/read-all');
  }
}

final noticesRepositoryProvider = Provider<NoticesRepository>((ref) {
  return NoticesRepository(ref.watch(dioProvider));
});
