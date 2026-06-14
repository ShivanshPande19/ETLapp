// lib/features/maintenance/domain/maintenance_notifier.dart

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ✅ FIX: Ye wala dio JWT token attach karta hai (app/dio_provider.dart nahi karta tha)
import '../../../core/network/api_client.dart';
import '../../../core/cloudinary/cloudinary_service.dart';

// ─── Data Model ──────────────────────────────────────────────────────────────

class MaintenanceIssueModel {
  final int id;
  final int courtId;
  final String courtName;
  final int outletId;
  final String outletName;
  final String staffName;
  final String issueType;
  final String priority; // low | medium | high
  final String description;
  final String? photoUrl;
  final String status; // RAISED, ASSIGNED, RESOLVED, CLOSED, DISPUTED
  final String? technicianName;
  final String? technicianPhone;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final DateTime? autoCloseAt; // 24h verification deadline

  MaintenanceIssueModel({
    required this.id,
    required this.courtId,
    required this.courtName,
    required this.outletId,
    required this.outletName,
    required this.staffName,
    required this.issueType,
    required this.priority,
    required this.description,
    this.photoUrl,
    required this.status,
    this.technicianName,
    this.technicianPhone,
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.closedAt,
    this.autoCloseAt,
  });

  // ✅ Backend ab explicit UTC ('Z' suffix) bhejta hai — toLocal() sahi IST dega
  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  factory MaintenanceIssueModel.fromJson(Map<String, dynamic> json) {
    return MaintenanceIssueModel(
      id: json['id'] ?? 0,
      courtId: json['court_id'] ?? 0,
      courtName: json['court_name'] ?? 'Unknown Court',
      outletId: json['outlet_id'] ?? 0,
      outletName: json['outlet_name'] ?? 'Unknown Outlet',
      staffName: json['staff_name'] ?? 'Staff',
      issueType: json['issue_type'] ?? 'other',
      priority: json['priority'] ?? 'medium',
      description: json['description'] ?? '',
      photoUrl: json['photo_url'],
      status: json['status'] ?? 'RAISED',
      technicianName: json['technician_name'],
      technicianPhone: json['technician_phone'],
      createdAt: _dt(json['created_at']),
      updatedAt: _dt(json['updated_at']),
      resolvedAt: _dt(json['resolved_at']),
      closedAt: _dt(json['closed_at']),
      autoCloseAt: _dt(json['auto_close_at']),
    );
  }

  bool get isOpen => status != 'CLOSED';
  bool get needsVerification => status == 'RESOLVED';

  Duration? get timeUntilAutoClose {
    if (autoCloseAt == null) return null;
    final diff = autoCloseAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class MaintenanceNotifier
    extends Notifier<AsyncValue<List<MaintenanceIssueModel>>> {
  @override
  AsyncValue<List<MaintenanceIssueModel>> build() {
    Future.microtask(() => refresh());
    return const AsyncValue.loading();
  }

  Future<void> refresh() async {
    // Pehli load pe hi spinner, refresh pe purana data dikhta rahe
    if (!state.hasValue) state = const AsyncValue.loading();

    try {
      final dio = ref.read(dioProvider);

      // ✅ Backend ab role ke hisaab se khud scope karta hai —
      //    court_id / outlet_id bhejne ki zaroorat nahi
      final res = await dio.get(
        '/maintenance',
        queryParameters: {'limit': 100, 'offset': 0},
      );

      // ✅ New format: { items: [...], total, limit, offset }
      final items = (res.data['items'] as List? ?? [])
          .map((e) => MaintenanceIssueModel.fromJson(e as Map<String, dynamic>))
          .toList();

      state = AsyncValue.data(items);
    } catch (e, st) {
      debugPrint('❌ [MAINTENANCE_FETCH] $e');
      if (state.hasValue) return; // refresh fail — purana data rakho
      state = AsyncValue.error(_friendlyError(e), st);
    }
  }

  // ── 1. RAISE TICKET (Outlet user) ─────────────────────────────────────────
  // Returns null on success, error message on failure.
  Future<String?> raiseTicket({
    required String issueType,
    required String priority,
    required String description,
    File? photo,
  }) async {
    try {
      String? photoUrl;
      if (photo != null) {
        photoUrl = await HousekeepingStorageService.uploadMaintenancePhoto(
          photo: photo,
        );
        if (photoUrl == null) {
          return 'Photo upload failed. Check your connection.';
        }
      }

      final dio = ref.read(dioProvider);
      // ✅ outlet_id / staff_name ab JWT se aate hain — body mein nahi
      await dio.post(
        '/maintenance/',
        data: {
          'issue_type': issueType,
          'priority': priority,
          'description': description.trim(),
          if (photoUrl != null) 'photo_url': photoUrl,
        },
      );
      await refresh();
      return null;
    } catch (e) {
      debugPrint('❌ [MAINTENANCE_RAISE] $e');
      return _friendlyError(e);
    }
  }

  // ── 2. ASSIGN TECHNICIAN (ETL Manager) ────────────────────────────────────
  Future<String?> assignTechnician(
    int issueId,
    String techName,
    String techPhone,
  ) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.put(
        '/maintenance/$issueId/assign',
        data: {
          'technician_name': techName.trim(),
          'technician_phone': techPhone.trim(),
        },
      );
      await refresh();
      return null;
    } catch (e) {
      debugPrint('❌ [MAINTENANCE_ASSIGN] $e');
      return _friendlyError(e);
    }
  }

  // ── 3. MARK RESOLVED (ETL Manager) ────────────────────────────────────────
  Future<String?> markResolved(int issueId) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.put('/maintenance/$issueId/resolve');
      await refresh();
      return null;
    } catch (e) {
      debugPrint('❌ [MAINTENANCE_RESOLVE] $e');
      return _friendlyError(e);
    }
  }

  // ── 4. VERIFY CLOSURE (Outlet user) ───────────────────────────────────────
  Future<String?> verifyTicket(int issueId, bool isSatisfied) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.put(
        '/maintenance/$issueId/verify',
        data: {'is_satisfied': isSatisfied},
      );
      await refresh();
      return null;
    } catch (e) {
      debugPrint('❌ [MAINTENANCE_VERIFY] $e');
      return _friendlyError(e);
    }
  }

  // ── Error helper — backend ka exact detail dikhao ────────────────────────
  String _friendlyError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];
        if (detail is String) return detail;
      }
      final code = e.response?.statusCode;
      if (code == 401) return 'Session expired. Please log in again.';
      if (code == 403) return 'You don\'t have permission for this action.';
      if (code == 409) return 'This ticket was already updated. Refreshing...';
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return 'Cannot reach server. Check your internet.';
      }
      return 'Server error ($code). Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}

final maintenanceNotifierProvider =
    NotifierProvider<
      MaintenanceNotifier,
      AsyncValue<List<MaintenanceIssueModel>>
    >(MaintenanceNotifier.new);
