import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

// ── VendorSaleDetail ──────────────────────────────────────────────────────────

class VendorSaleDetail {
  final String vendorName;
  final String sourceSystem;
  final double totalSales;
  final int billCount;
  final double avgBillValue;
  final String lastSynced;

  VendorSaleDetail({
    required this.vendorName,
    required this.sourceSystem,
    required this.totalSales,
    required this.billCount,
    required this.avgBillValue,
    required this.lastSynced,
  });

  factory VendorSaleDetail.fromJson(Map<String, dynamic> json) {
    return VendorSaleDetail(
      vendorName: json['vendor_name'],
      sourceSystem: json['source_system'],
      totalSales: (json['total_sales'] as num).toDouble(),
      billCount: json['bill_count'],
      avgBillValue: (json['avg_bill_value'] as num).toDouble(),
      lastSynced: json['last_synced'],
    );
  }
}

// ── SalesSummary ──────────────────────────────────────────────────────────────

class SalesSummary {
  final String date;
  final String period; // ← added
  final double totalSales;
  final int totalBills;
  final double avgBillValue;
  final List<VendorSaleDetail> vendors;

  SalesSummary({
    required this.date,
    required this.period, // ← added
    required this.totalSales,
    required this.totalBills,
    required this.avgBillValue,
    required this.vendors,
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    return SalesSummary(
      date: json['date'],
      period: json['period'] ?? 'yesterday', // ← added
      totalSales: (json['total_sales'] as num).toDouble(),
      totalBills: json['total_bills'],
      avgBillValue: (json['avg_bill_value'] as num).toDouble(),
      vendors: (json['vendors'] as List)
          .map((v) => VendorSaleDetail.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── DailySnapshot ─────────────────────────────────────────────────────────────

class DailySnapshot {
  final String date;
  final double totalSales;
  final int totalBills;

  DailySnapshot({
    required this.date,
    required this.totalSales,
    required this.totalBills,
  });

  factory DailySnapshot.fromJson(Map<String, dynamic> json) {
    return DailySnapshot(
      date: json['date'] as String,
      totalSales: (json['total_sales'] as num).toDouble(),
      totalBills: json['total_bills'] as int,
    );
  }
}

// ── VendorHistory ─────────────────────────────────────────────────────────────

class VendorHistory {
  final String vendorName;
  final String sourceSystem;
  final double totalSales;
  final int billCount;
  final double avgBillValue;
  final String lastSynced;
  final double weekTotal;
  final double lastWeekTotal;
  final String bestDay;
  final List<DailySnapshot> dailyHistory;

  VendorHistory({
    required this.vendorName,
    required this.sourceSystem,
    required this.totalSales,
    required this.billCount,
    required this.avgBillValue,
    required this.lastSynced,
    required this.weekTotal,
    required this.lastWeekTotal,
    required this.bestDay,
    required this.dailyHistory,
  });

  factory VendorHistory.fromJson(Map<String, dynamic> json) {
    return VendorHistory(
      vendorName: json['vendor_name'] as String,
      sourceSystem: json['source_system'] as String,
      totalSales: (json['total_sales'] as num).toDouble(),
      billCount: json['bill_count'] as int,
      avgBillValue: (json['avg_bill_value'] as num).toDouble(),
      lastSynced: json['last_synced'] as String,
      weekTotal: (json['week_total'] as num).toDouble(),
      lastWeekTotal: (json['last_week_total'] as num).toDouble(),
      bestDay: json['best_day'] as String,
      dailyHistory: (json['daily_history'] as List)
          .map((e) => DailySnapshot.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── SalesRepository ───────────────────────────────────────────────────────────

class SalesRepository {
  final Dio _dio;
  SalesRepository(this._dio);

  Future<SalesSummary> getSalesSummary({
    int? courtId,
    String period = 'yesterday', // ← added
    String? dateFrom, // ← added (custom range)
    String? dateTo, // ← added (custom range)
  }) async {
    final response = await _dio.get(
      '/sales/summary',
      queryParameters: <String, dynamic>{
        'period': period,
        if (courtId != null) 'court_id': courtId,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
      },
    );
    return SalesSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<VendorHistory> fetchVendorHistory({
    required String vendorName,
    required int courtId,
  }) async {
    final response = await _dio.get(
      '/sales/vendor/history',
      queryParameters: {'vendor_name': vendorName, 'court_id': courtId},
    );
    return VendorHistory.fromJson(response.data as Map<String, dynamic>);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(dioProvider));
});
