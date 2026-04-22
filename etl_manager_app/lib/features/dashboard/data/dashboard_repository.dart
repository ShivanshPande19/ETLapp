import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class DashboardSummaryModel {
  final String date;
  final double totalSales;
  final int totalBills;
  final List<VendorSaleModel> vendorBreakdown;
  final String lastSynced;

  DashboardSummaryModel({
    required this.date,
    required this.totalSales,
    required this.totalBills,
    required this.vendorBreakdown,
    required this.lastSynced,
  });

  factory DashboardSummaryModel.fromJson(Map<String, dynamic> json) {
    return DashboardSummaryModel(
      date: json['date'],
      totalSales: (json['total_sales'] as num).toDouble(),
      totalBills: json['total_bills'],
      vendorBreakdown: (json['vendor_breakdown'] as List)
          .map((v) => VendorSaleModel.fromJson(v))
          .toList(),
      lastSynced: json['last_synced'],
    );
  }
}

class VendorSaleModel {
  final String vendorName;
  final String sourceSystem;
  final double totalSales;
  final int billCount;

  VendorSaleModel({
    required this.vendorName,
    required this.sourceSystem,
    required this.totalSales,
    required this.billCount,
  });

  factory VendorSaleModel.fromJson(Map<String, dynamic> json) {
    return VendorSaleModel(
      vendorName: json['vendor_name'],
      sourceSystem: json['source_system'],
      totalSales: (json['total_sales'] as num).toDouble(),
      billCount: json['bill_count'],
    );
  }
}

class DashboardRepository {
  final Dio _dio;
  DashboardRepository(this._dio);

  Future<DashboardSummaryModel> getSummary() async {
    final response = await _dio.get('/dashboard/summary');
    return DashboardSummaryModel.fromJson(response.data);
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(dioProvider));
});