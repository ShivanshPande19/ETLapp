class StaffModel {
  final int id;
  final String name;
  final String email;
  final String role;
  final int? courtId;
  final String? phone;
  final String? photoUrl;
  final bool isActive;

  const StaffModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.courtId,
    this.phone,
    this.photoUrl,
    required this.isActive,
  });

  factory StaffModel.fromJson(Map<String, dynamic> j) => StaffModel(
    id: j['id'],
    name: j['name'] ?? '',
    email: j['email'] ?? '',
    role: j['role'] ?? 'etl_staff',
    courtId: j['court_id'],
    phone: j['phone'],
    photoUrl: j['photo_url'],
    isActive: j['is_active'] ?? true,
  );
}
