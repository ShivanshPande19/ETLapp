// lib/features/outlets/data/outlets_repository.dart
//
// Multi-outlet ownership: the outlets a manager can access (for the switcher)
// and the manage-access CRUD an owner uses to add/remove co-managers.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart'; // authenticated dioProvider

/// One outlet the logged-in manager can access (from GET /outlets/mine).
class MyOutlet {
  final int outletId;
  final String vendorName;
  final int courtId;
  final String courtName;
  final String membershipRole; // "owner" | "manager"

  const MyOutlet({
    required this.outletId,
    required this.vendorName,
    required this.courtId,
    required this.courtName,
    required this.membershipRole,
  });

  bool get isOwner => membershipRole == 'owner';

  /// Label shown in the switcher, e.g. "Central 50 · Coffee Vault".
  String get label => '$courtName · $vendorName';

  factory MyOutlet.fromJson(Map<String, dynamic> j) => MyOutlet(
        outletId: (j['outlet_id'] ?? 0) as int,
        vendorName: (j['vendor_name'] ?? '') as String,
        courtId: (j['court_id'] ?? 0) as int,
        courtName: (j['court_name'] ?? '') as String,
        membershipRole: (j['membership_role'] ?? 'manager') as String,
      );
}

/// A manager linked to an outlet (from GET /outlets/{id}/managers).
class OutletManager {
  final int managerId;
  final String name;
  final String email;
  final String membershipRole;
  final bool isActive;

  const OutletManager({
    required this.managerId,
    required this.name,
    required this.email,
    required this.membershipRole,
    required this.isActive,
  });

  bool get isOwner => membershipRole == 'owner';

  factory OutletManager.fromJson(Map<String, dynamic> j) => OutletManager(
        managerId: (j['manager_id'] ?? 0) as int,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        membershipRole: (j['membership_role'] ?? 'manager') as String,
        isActive: (j['is_active'] ?? true) as bool,
      );
}

class OutletsRepository {
  final Dio _dio;
  OutletsRepository(this._dio);

  /// The outlets the caller can access (empty for ETL managers / staff).
  Future<List<MyOutlet>> fetchMine() async {
    final res = await _dio.get('/outlets/mine');
    final list = (res.data as List? ?? []);
    return list
        .map((e) => MyOutlet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Managers linked to an outlet (owner-only on the server).
  Future<List<OutletManager>> listManagers(int outletId) async {
    final res = await _dio.get('/outlets/$outletId/managers');
    final list = (res.data as List? ?? []);
    return list
        .map((e) => OutletManager.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Owner assigns a limited co-manager. Returns the response map (contains an
  /// optional set_password_link for brand-new accounts).
  Future<Map<String, dynamic>> addManager(
    int outletId, {
    required String name,
    required String email,
  }) async {
    final res = await _dio.post(
      '/outlets/$outletId/managers',
      data: {'name': name, 'email': email},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Owner revokes a co-manager's access to this outlet.
  Future<void> removeManager(int outletId, int managerId) async {
    await _dio.delete('/outlets/$outletId/managers/$managerId');
  }

  /// ETL admin: correct an outlet owner's name / email / phone.
  Future<Map<String, dynamic>> updateOutletOwner(
    int outletId, {
    String? name,
    String? email,
    String? phone,
  }) async {
    final res = await _dio.patch(
      '/outlets/$outletId/owner',
      data: {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// ETL admin: permanently delete an outlet and all its data.
  Future<void> deleteOutlet(int outletId) async {
    await _dio.delete('/outlets/$outletId');
  }
}

final outletsRepositoryProvider = Provider<OutletsRepository>((ref) {
  return OutletsRepository(ref.watch(dioProvider));
});
