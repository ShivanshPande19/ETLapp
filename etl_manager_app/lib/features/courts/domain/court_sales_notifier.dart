import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sales/data/sales_repository.dart';

/// A family provider — Riverpod creates one independent instance
/// per court ID so each court card fetches its own sales data.
///
/// Usage:
///   ref.watch(courtSalesProvider(court.id))
///
final courtSalesProvider = FutureProvider.family<SalesSummary, int>(
  (ref, courtId) async {
    return ref
        .read(salesRepositoryProvider)
        .getSalesSummary(courtId: courtId);
  },
);