// lib/features/onboarding/domain/onboarding_models.dart

class OutletApplication {
  final int id;
  final int courtId;
  final String? courtName;
  final String outletName;
  final String ownerName;
  final String ownerPhone;
  final String ownerEmail;
  final String? gstUrl;
  final String? fssaiUrl;
  final String? termSheetUrl;
  final String? agreementUrl;
  final String status; // pending | approved | rejected
  final String? rejectionReason;
  final int? createdOutletId;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  OutletApplication({
    required this.id,
    required this.courtId,
    this.courtName,
    required this.outletName,
    required this.ownerName,
    required this.ownerPhone,
    required this.ownerEmail,
    this.gstUrl,
    this.fssaiUrl,
    this.termSheetUrl,
    this.agreementUrl,
    required this.status,
    this.rejectionReason,
    this.createdOutletId,
    this.createdAt,
    this.reviewedAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory OutletApplication.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    return OutletApplication(
      id: j['id'] ?? 0,
      courtId: j['court_id'] ?? 0,
      courtName: j['court_name'],
      outletName: j['outlet_name'] ?? '',
      ownerName: j['owner_name'] ?? '',
      ownerPhone: j['owner_phone'] ?? '',
      ownerEmail: j['owner_email'] ?? '',
      gstUrl: j['gst_url'],
      fssaiUrl: j['fssai_url'],
      termSheetUrl: j['term_sheet_url'],
      agreementUrl: j['agreement_url'],
      status: j['status'] ?? 'pending',
      rejectionReason: j['rejection_reason'],
      createdOutletId: j['created_outlet_id'],
      createdAt: parse(j['created_at']),
      reviewedAt: parse(j['reviewed_at']),
    );
  }
}

class ApplicationsData {
  final List<OutletApplication> applications;
  final int pendingCount;

  ApplicationsData({required this.applications, required this.pendingCount});
}

/// Result of an approve call.
class ApproveResult {
  final int outletId;
  final String managerEmail;
  final String setPasswordLink;
  final bool emailSent;
  final String message;

  ApproveResult({
    required this.outletId,
    required this.managerEmail,
    required this.setPasswordLink,
    required this.emailSent,
    required this.message,
  });

  factory ApproveResult.fromJson(Map<String, dynamic> j) => ApproveResult(
    outletId: j['outlet_id'] ?? 0,
    managerEmail: j['manager_email'] ?? '',
    setPasswordLink: j['set_password_link'] ?? '',
    emailSent: j['email_sent'] ?? false,
    message: j['message'] ?? '',
  );
}
