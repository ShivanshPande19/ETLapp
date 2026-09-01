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
