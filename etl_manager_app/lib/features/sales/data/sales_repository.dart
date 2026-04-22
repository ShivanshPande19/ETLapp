import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

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
      vendorName:   json['vendor_name'],
      sourceSystem: json['source_system'],
      totalSales:   (json['total_sales'] as num).toDouble(),
      billCount:    json['bill_count'],
      avgBillValue: (json['avg_bill_value'] as num).toDouble(),
      lastSynced:   json['last_synced'],
    );
  }
}

class SalesSummary {
  final String date;
  final double totalSales;
  final int totalBills;
  final double avgBillValue;
  final List<VendorSaleDetail> vendors;

  SalesSummary({
    required this.date,
    required this.totalSales,
    required this.totalBills,
    required this.avgBillValue,
    required this.vendors,
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    return SalesSummary(
      date:         json['date'],
      totalSales:   (json['total_sales'] as num).toDouble(),
      totalBills:   json['total_bills'],
      avgBillValue: (json['avg_bill_value'] as num).toDouble(),
      vendors:      (json['vendors'] as List)
                        .map((v) => VendorSaleDetail.fromJson(v))
                        .toList(),
    );
  }
}

class SalesRepository {
  final Dio _dio;
  SalesRepository(this._dio);

  Future<SalesSummary> getSalesSummary({int? courtId}) async {
    final response = await _dio.get(
      '/sales/summary',
      queryParameters: courtId != null ? {'court_id': courtId} : null,
    );
    return SalesSummary.fromJson(response.data);
  }
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(dioProvider));
});