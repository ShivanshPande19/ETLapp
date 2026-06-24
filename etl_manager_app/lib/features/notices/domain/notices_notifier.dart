import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notices_repository.dart';

class NoticesNotifier extends Notifier<AsyncValue<NoticesResult>> {
  @override
  AsyncValue<NoticesResult> build() {
    Future.microtask(fetch);
    return const AsyncValue.loading();
  }

  Future<void> fetch() async {
    try {
      final res = await ref.read(noticesRepositoryProvider).getNotices();
      state = AsyncValue.data(res);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> markRead(int id) async {
    await ref.read(noticesRepositoryProvider).markRead(id);
    await fetch();
    ref.invalidate(unreadCountProvider);
  }

  Future<void> markAllRead() async {
    await ref.read(noticesRepositoryProvider).markAllRead();
    await fetch();
    ref.invalidate(unreadCountProvider);
  }
}

final noticesNotifierProvider =
    NotifierProvider<NoticesNotifier, AsyncValue<NoticesResult>>(
  NoticesNotifier.new,
);

/// Lightweight unread-count for badges (auto-refreshed on demand).
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(noticesRepositoryProvider).unreadCount();
});
