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
      vendorName: json['vendor_name'] ?? 'Unknown',
      sourceSystem: json['source_system'] ?? 'Petpooja',
      totalSales: (json['total_sales'] ?? 0).toDouble(),
      billCount: json['bill_count'] ?? 0,
      avgBillValue: (json['avg_bill'] ?? 0).toDouble(),
      lastSynced: json['fetched_at'] ?? DateTime.now().toIso8601String(),
    );
  }
}

// ── SalesSummary ──────────────────────────────────────────────────────────────

class SalesSummary {
  final String date;
  final String period;
  final double totalSales;
  final int totalBills;
  final double avgBillValue;
  final List<VendorSaleDetail> vendors;

  SalesSummary({
    required this.date,
    required this.period,
    required this.totalSales,
    required this.totalBills,
    required this.avgBillValue,
    required this.vendors,
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json, String periodReq) {
    // FIX 1: 'results' ki jagah 'vendors' key use karenge
    var vendorList = json['vendors'] as List? ?? [];
    return SalesSummary(
      date: json['date'] ?? json['business_date'] ?? json['sale_date'] ?? '',
      period: periodReq,
      totalSales: (json['total_sales'] ?? 0).toDouble(),
      totalBills: json['total_bills'] ?? json['bill_count'] ?? 0,
      avgBillValue: (json['avg_bill_value'] ?? json['avg_bill'] ?? 0)
          .toDouble(),
      vendors: vendorList
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
      date: json['date'] ?? json['sale_date'] ?? '',
      totalSales: (json['total_sales'] ?? 0).toDouble(),
      totalBills: json['total_bills'] ?? json['bill_count'] ?? 0,
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
    // FIX 2: 'results' ki jagah 'daily_history' key use karenge
    var resultsList = json['daily_history'] as List? ?? [];
    return VendorHistory(
      vendorName: json['vendor_name'] ?? 'Vendor',
      sourceSystem: json['source_system'] ?? 'Petpooja',
      totalSales: (json['total_sales'] ?? 0).toDouble(),
      billCount: json['bill_count'] ?? 0,
      avgBillValue: (json['avg_bill_value'] ?? 0).toDouble(),
      lastSynced: json['last_synced'] ?? '',
      weekTotal: (json['week_total'] ?? 0).toDouble(),
      lastWeekTotal: (json['last_week_total'] ?? 0).toDouble(),
      bestDay: json['best_day'] ?? '',
      dailyHistory: resultsList
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
    String period = 'yesterday',
    String? dateFrom,
    String? dateTo,
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
    // Backend se aaya data, model me bhejo
    return SalesSummary.fromJson(response.data as Map<String, dynamic>, period);
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
