import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class Court {
  final int id;
  final String name;
  final String location;
  final String status;

  Court({
    required this.id,
    required this.name,
    required this.location,
    required this.status,
  });

  factory Court.fromJson(Map<String, dynamic> json) {
    return Court(
      id:       json['id'],
      name:     json['name'],
      location: json['location'],
      status:   json['status'],
    );
  }
}

class CourtsRepository {
  final Dio _dio;
  CourtsRepository(this._dio);

  Future<List<Court>> getCourts() async {
    final response = await _dio.get('/courts/');
    final list = response.data['courts'] as List;
    return list.map((c) => Court.fromJson(c)).toList();
  }
}

final courtsRepositoryProvider = Provider<CourtsRepository>((ref) {
  return CourtsRepository(ref.watch(dioProvider));
});