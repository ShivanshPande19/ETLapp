import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _nameKey = 'manager_name';
  static const _emailKey = 'manager_email';
  static const _roleKey = 'user_role';
  static const _zoneKey = 'user_zone';

  static Future<void> saveToken(String token) async =>
      await _storage.write(key: _tokenKey, value: token);

  static Future<String?> getToken() async =>
      await _storage.read(key: _tokenKey);

  static Future<void> saveManagerInfo(String name, String email) async {
    await _storage.write(key: _nameKey, value: name);
    await _storage.write(key: _emailKey, value: email);
  }

  static Future<void> saveRole(String role) async =>
      await _storage.write(key: _roleKey, value: role);

  static Future<void> saveZone(String? zone) async {
    if (zone != null) await _storage.write(key: _zoneKey, value: zone);
  }

  static Future<String?> getManagerName() async =>
      await _storage.read(key: _nameKey);

  static Future<String?> getManagerEmail() async =>
      await _storage.read(key: _emailKey);

  static Future<String?> getRole() async => await _storage.read(key: _roleKey);

  static Future<String?> getZone() async => await _storage.read(key: _zoneKey);

  static Future<void> clearAll() async => await _storage.deleteAll();
}
