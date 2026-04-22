import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/courts_repository.dart';

class CourtsNotifier extends Notifier<AsyncValue<List<Court>>> {
  @override
  AsyncValue<List<Court>> build() {
    fetchCourts();
    return const AsyncValue.loading();
  }

  Future<void> fetchCourts() async {
    state = const AsyncValue.loading();
    try {
      final courts = await ref.read(courtsRepositoryProvider).getCourts();
      state = AsyncValue.data(courts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final courtsNotifierProvider =
    NotifierProvider<CourtsNotifier, AsyncValue<List<Court>>>(() {
  return CourtsNotifier();
});