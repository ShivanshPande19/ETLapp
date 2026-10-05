import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/courts_repository.dart';
import '../../auth/domain/auth_notifier.dart';

class CourtsNotifier extends Notifier<AsyncValue<List<Court>>> {
  @override
  AsyncValue<List<Court>> build() {
    // FIX: same pattern — build() must return before fetchCourts()
    // sets state = const AsyncValue.loading() on its first line.
    Future.microtask(() => fetchCourts());
    return const AsyncValue.loading();
  }

  Future<void> fetchCourts() async {
    state = const AsyncValue.loading();
    try {
      var courts = await ref.read(courtsRepositoryProvider).getCourts();
      // Belt-and-braces zone scoping: a view-only Crownest Zone Manager must
      // NEVER see an unassigned zone's chip/option anywhere in the app. The
      // backend already scopes /courts/, but we also hard-filter here so a
      // single missed endpoint can't re-expose other zones. (No-op for
      // full-access management, whose courtIds is empty → sees every zone.)
      final auth = ref.read(authNotifierProvider);
      if (auth.isCrownestZoneManager && auth.courtIds.isNotEmpty) {
        final allowed = auth.courtIds.toSet();
        courts = courts.where((c) => allowed.contains(c.id)).toList();
      }
      state = AsyncValue.data(courts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Create a new court, then refresh the list. Returns the created court.
  Future<Court> createCourt({
    required String name,
    String? location,
    double? latitude,
    double? longitude,
    int? geofenceRadius,
    String? address,
  }) async {
    final court = await ref.read(courtsRepositoryProvider).createCourt(
          name: name,
          location: location,
          latitude: latitude,
          longitude: longitude,
          geofenceRadius: geofenceRadius,
          address: address,
        );
    await fetchCourts();
    return court;
  }

  /// Set / edit an existing court's geofence location, then refresh.
  Future<void> updateCourtLocation({
    required int courtId,
    required double latitude,
    required double longitude,
    required int geofenceRadius,
    String? address,
  }) async {
    await ref.read(courtsRepositoryProvider).updateCourtLocation(
          courtId: courtId,
          latitude: latitude,
          longitude: longitude,
          geofenceRadius: geofenceRadius,
          address: address,
        );
    await fetchCourts();
  }

  /// Set a court's overnight business-day cutoff hour, then refresh.
  Future<void> updateCourtSettings({
    required int courtId,
    required int dayCutoffHour,
  }) async {
    await ref.read(courtsRepositoryProvider).updateCourtSettings(
          courtId: courtId,
          dayCutoffHour: dayCutoffHour,
        );
    await fetchCourts();
  }
}

final courtsNotifierProvider =
    NotifierProvider<CourtsNotifier, AsyncValue<List<Court>>>(() {
      return CourtsNotifier();
    });
