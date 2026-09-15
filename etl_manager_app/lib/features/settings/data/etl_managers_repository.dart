// lib/features/settings/data/etl_managers_repository.dart
//
// ETL-manager account administration (ETL-manager only). Lists ETL-manager
// logins, invites new ones by name + email (backend emails a set-password
// link), and revokes/restores access. Backed by /managers/etl-managers, which
// the server gates behind require_etl_manager.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart'; // authenticated dioProvider

/// One ETL-manager account (from GET /managers/etl-managers).
class EtlManager {
  final int managerId;
  final String name;
  final String email;
  final bool isActive;
  final bool isSelf; // the currently logged-in ETL manager

  const EtlManager({
    required this.managerId,
    required this.name,
    required this.email,
    required this.isActive,
    required this.isSelf,
  });

  factory EtlManager.fromJson(Map<String, dynamic> j) => EtlManager(
        managerId: (j['manager_id'] ?? 0) as int,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        isActive: (j['is_active'] ?? true) as bool,
        isSelf: (j['is_self'] ?? false) as bool,
      );
}

class EtlManagersRepository {
  final Dio _dio;
  EtlManagersRepository(this._dio);

  /// All ETL-manager accounts (active first).
  Future<List<EtlManager>> list() async {
    final res = await _dio.get('/managers/etl-managers');
    final list = (res.data as List? ?? []);
    return list
        .map((e) => EtlManager.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a new ETL manager. Returns the response map, which contains an
  /// optional set_password_link (surface it when email_sent is false).
  Future<Map<String, dynamic>> create({
    required String name,
    required String email,
  }) async {
    final res = await _dio.post(
      '/managers/etl-managers',
      data: {'name': name, 'email': email},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Revoke an ETL manager's access.
  Future<void> deactivate(int managerId) async {
    await _dio.patch('/managers/etl-managers/$managerId/deactivate');
  }

  /// Restore a deactivated ETL manager's access.
  Future<void> reactivate(int managerId) async {
    await _dio.patch('/managers/etl-managers/$managerId/reactivate');
  }
}

final etlManagersRepositoryProvider = Provider<EtlManagersRepository>((ref) {
  return EtlManagersRepository(ref.watch(dioProvider));
});



// ══════════════════════════════════════════════════════════════════════════════
// ROLE SPLIT — generalised account administration (/managers/accounts).
// Manages ALL five ETL-side roles (management → managers table, maintenance →
// staff table). Management-only on the server.
// ══════════════════════════════════════════════════════════════════════════════

/// One ETL-side account (from GET /managers/accounts).
class Account {
  final String kind; // "manager" | "staff"
  final int accountId;
  final String name;
  final String email;
  final String role;
  final String roleLabel;
  final String? org;
  final int? zoneCourtId;
  final String? zoneName;
  final bool isActive;
  final bool isSelf;

  const Account({
    required this.kind,
    required this.accountId,
    required this.name,
    required this.email,
    required this.role,
    required this.roleLabel,
    required this.isActive,
    required this.isSelf,
    this.org,
    this.zoneCourtId,
    this.zoneName,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        kind: (j['kind'] ?? 'manager') as String,
        accountId: (j['account_id'] ?? 0) as int,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        roleLabel: (j['role_label'] ?? j['role'] ?? '') as String,
        org: j['org'] as String?,
        zoneCourtId: j['zone_court_id'] as int?,
        zoneName: j['zone_name'] as String?,
        isActive: (j['is_active'] ?? true) as bool,
        isSelf: (j['is_self'] ?? false) as bool,
      );
}

extension AccountsApi on EtlManagersRepository {
  /// Every ETL-side account (management + maintenance).
  Future<List<Account>> listAccounts() async {
    final res = await _dio.get('/managers/accounts');
    final list = (res.data as List? ?? []);
    return list
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create any of the 5 roles. `courtId` is required only for
  /// crownest_maintenance_head (its zone). Returns the response map (may hold a
  /// set_password_link when email_sent is false).
  Future<Map<String, dynamic>> createAccount({
    required String name,
    required String email,
    required String role,
    int? courtId,
  }) async {
    final res = await _dio.post('/managers/accounts', data: {
      'name': name,
      'email': email,
      'role': role,
      if (courtId != null) 'court_id': courtId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> deactivateAccount(String kind, int accountId) async {
    await _dio.patch('/managers/accounts/$kind/$accountId/deactivate');
  }

  Future<void> reactivateAccount(String kind, int accountId) async {
    await _dio.patch('/managers/accounts/$kind/$accountId/reactivate');
  }
}
