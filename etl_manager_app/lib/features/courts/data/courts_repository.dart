import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class Court {
  final int id;
  final String name;
  final String location;
  final bool isActive;

  Court({
    required this.id,
    required this.name,
    required this.location,
    required this.isActive,
  });

  factory Court.fromJson(Map<String, dynamic> json) {
    bool activeStatus = false;
    if (json['is_active'] != null) {
      if (json['is_active'] is int) {
        activeStatus = json['is_active'] == 1;
      } else if (json['is_active'] is bool) {
        activeStatus = json['is_active'];
      }
    } else if (json['status'] != null) {
      // Fallback incase old api is called
      activeStatus = json['status'].toString().toLowerCase() == 'live';
    }

    return Court(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown Court',
      location: json['location'] ?? json['court_uid'] ?? 'Food Court',
      isActive: activeStatus,
    );
  }
}

class CourtsRepository {
  final Dio _dio;
  CourtsRepository(this._dio);

  Future<List<Court>> getCourts() async {
    try {
      final response = await _dio.get('/courts/');
      print(
        'COURT API RESPONSE: ${response.data}',
      ); // <-- Ye line hume bata degi kya data aa raha h

      List list = [];
      if (response.data is List) {
        list = response.data;
      } else if (response.data is Map && response.data.containsKey('courts')) {
        list = response.data['courts'];
      }

      return list
          .map((c) => Court.fromJson(c as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print(
        'COURT API ERROR: $e',
      ); // <-- Agar fetch fail ho raha h to yahan print ho jayega
      return [];
    }
  }

  /// ETL manager: create a new court.
  Future<Court> createCourt({required String name, String? location}) async {
    final response = await _dio.post(
      '/courts/',
      data: {
        'name': name,
        if (location != null && location.trim().isNotEmpty)
          'location': location.trim(),
      },
    );
    return Court.fromJson(response.data as Map<String, dynamic>);
  }
}

final courtsRepositoryProvider = Provider<CourtsRepository>((ref) {
  return CourtsRepository(ref.watch(dioProvider));
});
