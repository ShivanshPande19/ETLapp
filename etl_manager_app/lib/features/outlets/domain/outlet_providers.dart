// lib/features/outlets/domain/outlet_providers.dart
//
// Multi-outlet state for the app:
//   • myOutletsProvider      — the outlets the logged-in manager can access
//                              (drives the header switcher). Empty for ETL
//                              managers / staff, so the switcher never shows.
//   • selectedOutletIdProvider — the currently-selected outlet id. Defaults to
//                              the manager's PRIMARY outlet, so a single-outlet
//                              owner behaves EXACTLY as before (zero UX change).
//   • selectedOutletProvider — the selected MyOutlet object (for labels).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/auth_notifier.dart';
import '../data/outlets_repository.dart';

/// The outlets the caller can access. Kept alive for the session; refetches
/// when auth changes (login/logout). Never throws — a failure yields [] so the
/// UI simply falls back to the single-outlet (primary) behaviour.
final myOutletsProvider = FutureProvider<List<MyOutlet>>((ref) async {
  final auth = ref.watch(authNotifierProvider);
  if (!auth.isOutletManager) return const <MyOutlet>[];
  try {
    return await ref.read(outletsRepositoryProvider).fetchMine();
  } catch (_) {
    return const <MyOutlet>[];
  }
});

/// The currently-selected outlet id.
///
/// Defaults to the manager's PRIMARY outlet (`AuthState.outletId`), which for a
/// single-outlet owner is their only outlet — so nothing changes for them. A
/// multi-outlet owner changes it via the switcher.
class SelectedOutletIdNotifier extends Notifier<int?> {
  @override
  int? build() {
    // Re-evaluates on auth changes (a new login resets to that user's primary
    // outlet). Stable during a normal session, so a manual selection sticks.
    final auth = ref.watch(authNotifierProvider);
    return auth.outletId;
  }

  /// Switch the active outlet (called by the switcher). Ignores a no-op.
  void select(int outletId) {
    if (state != outletId) state = outletId;
  }
}

final selectedOutletIdProvider =
    NotifierProvider<SelectedOutletIdNotifier, int?>(
  SelectedOutletIdNotifier.new,
);

/// The selected outlet as a full object (name/court), or null if unknown.
final selectedOutletProvider = Provider<MyOutlet?>((ref) {
  final id = ref.watch(selectedOutletIdProvider);
  if (id == null) return null;
  final outlets = ref.watch(myOutletsProvider).value ?? const <MyOutlet>[];
  for (final o in outlets) {
    if (o.outletId == id) return o;
  }
  return null;
});

/// True only when the manager has more than one outlet — the switcher shows
/// exactly in this case, so single-outlet owners see no new UI.
final hasMultipleOutletsProvider = Provider<bool>((ref) {
  final outlets = ref.watch(myOutletsProvider).value ?? const <MyOutlet>[];
  return outlets.length > 1;
});
