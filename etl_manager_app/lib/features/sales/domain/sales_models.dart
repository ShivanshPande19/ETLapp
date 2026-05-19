// sales_models.dart

class SalesSummary {
  final String? date;
  final double totalSales;
  final int totalBills;
  final double avgBillValue;
  final List<VendorSaleDetail> vendors;

  SalesSummary({
    this.date,
    required this.totalSales,
    required this.totalBills,
    required this.avgBillValue,
    required this.vendors,
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    var vendorList = json['results'] as List? ?? [];
    return SalesSummary(
      date: json['business_date'] ?? json['sale_date'],
      totalSales: (json['total_sales'] ?? 0.0).toDouble(),
      totalBills: json['bill_count'] ?? json['total_bills'] ?? 0,
      avgBillValue: (json['avg_bill'] ?? json['avg_bill_value'] ?? 0.0)
          .toDouble(),
      vendors: vendorList.map((v) => VendorSaleDetail.fromJson(v)).toList(),
    );
  }
}

class VendorSaleDetail {
  final String vendorName;
  final double totalSales;
  final int billCount;
  final String sourceSystem;
  final String lastSynced;

  VendorSaleDetail({
    required this.vendorName,
    required this.totalSales,
    required this.billCount,
    required this.sourceSystem,
    required this.lastSynced,
  });

  factory VendorSaleDetail.fromJson(Map<String, dynamic> json) {
    return VendorSaleDetail(
      vendorName: json['vendor_name'] ?? 'Unknown Vendor',
      totalSales: (json['total_sales'] ?? 0.0).toDouble(),
      billCount: json['bill_count'] ?? 0,
      sourceSystem: json['source_system'] ?? 'Petpooja',
      lastSynced:
          json['fetched_at'] ??
          json['last_synced'] ??
          DateTime.now().toIso8601String(),
    );
  }
}

class VendorHistory {
  final List<dynamic> history;

  VendorHistory({required this.history});

  factory VendorHistory.fromJson(Map<String, dynamic> json) {
    return VendorHistory(history: json['results'] ?? json['history'] ?? []);
  }
}
