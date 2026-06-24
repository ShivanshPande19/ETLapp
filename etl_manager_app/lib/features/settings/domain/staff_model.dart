class StaffModel {
  final int id;
  final String name;
  final String email;
  final String role;
  final int? courtId;
  final String? phone;
  final String? photoUrl;
  final String? shiftStart; // "HH:MM" or null
  final String? shiftEnd; // "HH:MM" or null
  final bool isActive;

  const StaffModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.courtId,
    this.phone,
    this.photoUrl,
    this.shiftStart,
    this.shiftEnd,
    required this.isActive,
  });

  bool get hasShift =>
      (shiftStart != null && shiftStart!.isNotEmpty) &&
      (shiftEnd != null && shiftEnd!.isNotEmpty);

  /// Human label, e.g. "08:00 – 20:00".
  String get shiftLabel => hasShift ? '$shiftStart – $shiftEnd' : 'No shift set';

  factory StaffModel.fromJson(Map<String, dynamic> j) => StaffModel(
    id: j['id'],
    name: j['name'] ?? '',
    email: j['email'] ?? '',
    role: j['role'] ?? 'etl_staff',
    courtId: j['court_id'],
    phone: j['phone'],
    photoUrl: j['photo_url'],
    shiftStart: j['shift_start'],
    shiftEnd: j['shift_end'],
    isActive: j['is_active'] ?? true,
  );
}
